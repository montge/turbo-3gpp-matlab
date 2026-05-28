function [c, iterations_performed, c_a, c_e] = ...
        fixedpoint_turbo_decoder_term(d_a, pi, max_iterations, opts)
% FIXEDPOINT_TURBO_DECODER_TERM  P3 extension of the fixed-point
% Max-Log-MAP iterative turbo decoder (TS36.212 §5.1.3.2). It is the
% bit-exact oracle for the HDL core in
% openspec/changes/add-fpga-turbo-decoder-termination, layering the three
% P3-deferred behaviours around the P2 loop EXACTLY as the float oracle
% turbo_decoder.m / turbo_decoding_chain.m do:
%
%   1. CRC-aided early termination  (turbo_decoder.m, nargin == 4 path).
%   2. HARQ soft combining          (turbo_decoding_chain.m obj.buffers).
%   3. Filler-bit handling          (NaN -> +inf -> MAX_SENT sentinel).
%
% ---------------------------------------------------------------------------
% RELATIONSHIP TO P2 (CRITICAL — bit-exact regression contract):
%   The inner loop algebra (de-mux, half-iteration exchange, the P1
%   constituent core, the Q-format) is IDENTICAL to
%   scripts/fixedpoint_turbo_decoder.m (the P2 oracle). This file does NOT
%   modify that file. With NO P3 options supplied (or all disabled), this
%   function produces byte-identical hard bits / c_a / c_e to
%   fixedpoint_turbo_decoder(d_a, pi, max_iterations) — verified by the
%   characterization harness (regression cell). The P2 cocotb lane vectors
%   (hdl/vectors/turbo_decoder_top.csv) are therefore unaffected.
%
% ---------------------------------------------------------------------------
% USAGE
%   c = FIXEDPOINT_TURBO_DECODER_TERM(d_a, pi, max_iterations)
%       Plain P2 behaviour: H = round(2*max_iterations) fixed half-iterations,
%       no early termination, no filler, no HARQ. d_a must be finite.
%       iterations_performed returns max_iterations.
%
%   [c, iterations_performed] = FIXEDPOINT_TURBO_DECODER_TERM(d_a, pi,
%       max_iterations, opts) enables the P3 behaviours via the opts struct:
%
%     opts.G_max   (default []) — CRC generator matrix (K_max x L), as
%                  produced by get_crc_generator_matrix(K_max, poly) for the
%                  selected polynomial (CRC24A for a transport-block CRC when
%                  C == 1, CRC24B for a code-block CRC when C > 1; the caller
%                  picks which, mirroring turbo_decoding_chain.m). When
%                  non-empty, CRC-aided early termination is enabled, exactly
%                  like turbo_decoder.m's 4th argument: the CRC is checked on
%                  the hard decision before the loop and after each half, and
%                  the function returns as soon as the CRC passes, setting
%                  iterations_performed (0 pre-loop, iteration_index-0.5 post-
%                  upper, iteration_index post-lower, max_iterations if never).
%
%     opts.filler_bits (default []) — column indices (1..K, 1-based) of the
%                  systematic positions that are filler. Mirrors
%                  turbo_decoding_chain.m's d(1:2,1:F_r)=NaN: filler positions
%                  carry NaN systematic LLRs on input, are mapped to the +inf
%                  token (= the P1 MAX_SENT sentinel) at de-mux, decode as
%                  strongly-known 0 bits, and are forced to NaN on output
%                  (matching turbo_decoder.m's c(filler_bits)=NaN). The CRC,
%                  if enabled, is computed on the hard decision BEFORE that
%                  NaN overwrite (identical order to the float). Filler may
%                  alternatively be signalled by passing NaN entries directly
%                  in d_a (rows 1:2 of the filler columns); this function
%                  detects them the same way turbo_decoder.m does
%                  (filler_bits = find(isnan(d_a(1,:)))) and unions with
%                  opts.filler_bits.
%
%     opts.params  (default struct()) — overrides for the fixed-point format
%                  struct (see DEFAULT_PARAMS). The decode datapath widths are
%                  the inherited P1/P2 pins; the only NEW P3 knob is the HARQ
%                  accumulator width W_harq (see HARQ note below).
%
%   HARQ soft combining is performed by the CALLER (mirroring
%   turbo_decoding_chain.m, which accumulates obj.buffers BEFORE calling
%   turbo_decoder). Use the companion helper:
%
%       buf = fixedpoint_turbo_harq_accumulate(buf, d_a, params)
%
%   to saturating-accumulate successive retransmissions' channel-LLR matrices
%   into a soft buffer (real-LLR space, on the W_harq accumulator grid), then
%   pass the accumulated matrix as d_a to this decoder. See that helper's
%   header for the pinned accumulator width and saturation.
%
%   c                    — 1xK decoded hard bits (filler positions = NaN when
%                          filler is signalled, else 0/1).
%   iterations_performed — half-iteration index at which decoding stopped (a
%                          multiple of 0.5), or max_iterations if the CRC
%                          never passed / early termination disabled.
%   c_a, c_e             — final cyclic extrinsic state in real LLR space
%                          (diagnostic; same as the P2 oracle).
%
% ---------------------------------------------------------------------------
% DETERMINISM (bit-exact lane preservation):
%   The early-stop point is a PURE FUNCTION of the quantized inputs: the CRC
%   is evaluated at fixed check points (pre-loop, post-upper, post-lower) in a
%   fixed order on a deterministic hard decision, so the same (d_a, pi,
%   max_iterations, G_max, filler) always yields the same iterations_performed
%   AND the same c. No timing/race dependence. This is the analogue of P1/P2's
%   "identical quantization / saturation / op-order" contract, extended to
%   "identical CRC check schedule" (design.md Decision 3).
%
% ---------------------------------------------------------------------------
% FILLER -> +inf -> MAX_SENT (P1 sentinel, reused UNCHANGED):
%   turbo_decoding_chain.m marks the first F_r systematic LLRs NaN;
%   turbo_decoder.m maps d_a(isnan)=inf. In fixed-point, +inf at a systematic
%   position becomes the saturating max-magnitude code at every width it flows
%   through: it saturates to in_max (=255 at W_in) at the constituent-core
%   input, where it pins the bit as strongly-known 0 (LLR = ln[P(0)/P(1)],
%   +inf => 0). Inside the constituent core this is the P1 MAX_SENT =
%   2^(W_ab-1)-1 = 16383 sentinel (the symmetric counterpart of the
%   alpha/beta MIN_SENT = -16384). The sentinel is idempotent under the
%   saturating accumulate (a known bit stays known across retransmissions).
%   No new fixed-point token or format is introduced (design.md Decision 4).
%
% This routine mirrors the HDL's likely structure (explicit per-element
% saturating ops, fixed op order) rather than being Octave-idiomatic;
% clarity and bit-exactness > vectorization.

    if nargin < 4
        opts = struct();
    end
    if ~isfield(opts, 'G_max');        opts.G_max        = [];          end
    if ~isfield(opts, 'filler_bits');  opts.filler_bits  = [];          end
    if ~isfield(opts, 'params');       opts.params       = struct();    end

    p = default_params();
    fns = fieldnames(opts.params);
    for ii = 1:numel(fns)
        p.(fns{ii}) = opts.params.(fns{ii});
    end

    % --- Shape / argument checks (mirror turbo_decoder.m). ---
    if size(d_a, 1) ~= 3
        error('fixedpoint_turbo_decoder_term:bad_d_a_rows', 'd_a should have 3 rows');
    end
    K = size(d_a, 2) - 4;
    if length(pi) ~= K
        error('fixedpoint_turbo_decoder_term:pi_length_mismatch', ...
              'length of pi does not match K');
    end
    if ~isnumeric(max_iterations) || ~isscalar(max_iterations) ...
            || ~isreal(max_iterations) || ~isfinite(max_iterations)
        error('fixedpoint_turbo_decoder_term:iterations_invalid', ...
              'max_iterations must be a real, finite numeric scalar');
    end
    if max_iterations ~= round(2 * max_iterations) / 2
        error('fixedpoint_turbo_decoder_term:iterations_not_half_multiple', ...
              'max_iterations must be a multiple of 0.5');
    end
    if max_iterations < 0
        error('fixedpoint_turbo_decoder_term:iterations_negative', ...
              'max_iterations must be non-negative');
    end

    crc_enabled = ~isempty(opts.G_max);

    % --- Filler positions: union of NaN-signalled (turbo_decoder.m style)
    %     and explicitly-listed filler. The float records
    %     filler_bits = find(isnan(d_a(1,:))) then d_a(isnan)=inf.
    %     We reproduce the SAME order and mapping. ---
    nan_filler = find(isnan(d_a(1, :)));
    filler_bits = unique([nan_filler(:).', opts.filler_bits(:).']);
    filler_bits = filler_bits(filler_bits >= 1 & filler_bits <= K);

    % Map NaN -> +inf in real-LLR space (exactly turbo_decoder.m's
    % d_a(isnan(d_a)) = inf), so de-mux below sees +inf at filler positions.
    % Also force the +inf token at the listed filler systematic positions even
    % if they were not NaN on input (the chain always passes them as NaN, but
    % being explicit keeps the two signalling paths consistent).
    d_a(isnan(d_a)) = inf;
    if ~isempty(filler_bits)
        d_a(1, filler_bits) = inf;   % systematic row, filler body positions
    end

    % --- Saturation bounds. ---
    in_min  = -2^(p.W_in  - 1);    in_max  = 2^(p.W_in  - 1) - 1;   % core input
    ext_min = -2^(p.W_ext - 1);    ext_max = 2^(p.W_ext - 1) - 1;   % stored c_a/c_e
    acc_min = -2^(p.W_acc - 1);    acc_max = 2^(p.W_acc - 1) - 1;   % combiner accum
    lsb = 2^(-p.F_in);             % shared fractional scale (core + exchange)

    core_p = struct('W_in', p.W_in, 'F_in', p.F_in, 'W_gamma', p.W_gamma, ...
                    'W_ab', p.W_ab, 'W_delta', p.W_delta, 'W_xe', p.W_xe);

    % --- De-mux d_a (identical to the P2 oracle). ---
    z_a       = zeros(1, K + 3);
    z_prime_a = zeros(1, K + 3);
    x_a       = zeros(1, K + 3);
    x_prime_a = zeros(1, K + 3);

    z_a(1:K)       = d_a(2, 1:K);
    z_prime_a(1:K) = d_a(3, 1:K);
    ch_sys         = d_a(1, 1:K);

    x_a(K+1) = d_a(1, K+1);  z_a(K+1) = d_a(2, K+1);
    x_a(K+2) = d_a(3, K+1);  z_a(K+2) = d_a(1, K+2);
    x_a(K+3) = d_a(2, K+2);  z_a(K+3) = d_a(3, K+2);
    x_prime_a(K+1) = d_a(1, K+3);  z_prime_a(K+1) = d_a(2, K+3);
    x_prime_a(K+2) = d_a(3, K+3);  z_prime_a(K+2) = d_a(1, K+4);
    x_prime_a(K+3) = d_a(2, K+4);  z_prime_a(K+3) = d_a(3, K+4);

    % --- Quantize persistent words to the exchange grid (W_ext, F_in).
    %     +inf (filler) saturates to ext_max here, then to in_max at the core
    %     input below — the P1 MAX_SENT pin propagated through the widths. ---
    ch_sys_q = sat_round(ch_sys / lsb, ext_min, ext_max);

    za_core  = sat_round(z_a       / lsb, in_min, in_max);
    zpa_core = sat_round(z_prime_a / lsb, in_min, in_max);
    xa_term  = sat_round(x_a(K+1:K+3)       / lsb, in_min, in_max);
    xpa_term = sat_round(x_prime_a(K+1:K+3) / lsb, in_min, in_max);

    % --- Cyclic state. ---
    c_a_q = zeros(1, K);
    c_e_q = zeros(1, K);

    H = round(2 * max_iterations);

    % --- Pre-loop hard decision + CRC (turbo_decoder.m: c = d_a(1:K) < 0,
    %     using COLUMN-MAJOR linear indexing across all 3 rows — replicated
    %     EXACTLY for bit-identical iterations_performed). The float computes
    %     this on the post-NaN->inf d_a; we compute it on the quantized matrix
    %     so the stop point is a pure function of the quantized inputs. The
    %     two agree in sign for all finite values and for the +inf token. ---
    if crc_enabled
        d_a_q = quantize_matrix(d_a, lsb, ext_min, ext_max);   % 3x(K+4) codes
        c0 = double(d_a_q(1:K) < 0);                            % linear index
        [stop, iterations_performed, c] = ...
            crc_stop_check(c0, opts.G_max, 0, filler_bits);
        if stop
            [c_a, c_e] = realify(c_a_q, c_e_q, lsb);
            return;
        end
    end

    for h = 0:H-1
        if mod(h, 2) == 0
            % ======================= UPPER half =======================
            xa_body_core = zeros(1, K);
            for k = 1:K
                acc = sat_add(c_a_q(k), ch_sys_q(k), acc_min, acc_max);
                xa_body_core(k) = sat_clip(acc, in_min, in_max);
            end
            xa_core = [xa_body_core, xa_term];

            [x_e_real, x_e_q] = fixedpoint_constituent_decoder( ...
                double(xa_core) * lsb, double(za_core) * lsb, core_p); %#ok<ASGLU>

            for k = 1:K
                acc = sat_add(x_e_q(k), ch_sys_q(k), acc_min, acc_max);
                c_e_q(k) = sat_clip(acc, ext_min, ext_max);
            end
        else
            % ======================= LOWER half =======================
            xpa_body_core = zeros(1, K);
            ce_perm = c_e_q(pi + 1);
            for k = 1:K
                xpa_body_core(k) = sat_clip(ce_perm(k), in_min, in_max);
            end
            xpa_core = [xpa_body_core, xpa_term];

            [xp_e_real, xp_e_q] = fixedpoint_constituent_decoder( ...
                double(xpa_core) * lsb, double(zpa_core) * lsb, core_p); %#ok<ASGLU>

            scatter = zeros(1, K);
            for k = 1:K
                scatter(k) = sat_clip(xp_e_q(k), ext_min, ext_max);
            end
            c_a_q(pi + 1) = scatter;
        end

        % --- CRC check after this half (matches turbo_decoder.m's per-half
        %     hard decision c = (c_a + c_e) < 0 and the check points:
        %     post-upper => iteration_index-0.5, post-lower => iteration_index).
        if crc_enabled
            c_half = zeros(1, K);
            for k = 1:K
                acc = sat_add(c_a_q(k), c_e_q(k), acc_min, acc_max);
                c_half(k) = double(acc < 0);
            end
            if mod(h, 2) == 0
                iters_here = (h / 2) + 0.5;     % post-upper
            else
                iters_here = (h + 1) / 2;       % post-lower
            end
            [stop, iterations_performed, c] = ...
                crc_stop_check(c_half, opts.G_max, iters_here, filler_bits);
            if stop
                [c_a, c_e] = realify(c_a_q, c_e_q, lsb);
                return;
            end
        end
    end

    % --- Final hard decision (CRC never passed, or disabled). ---
    c = zeros(1, K);
    for k = 1:K
        acc = sat_add(c_a_q(k), c_e_q(k), acc_min, acc_max);
        c(k) = double(acc < 0);
    end
    iterations_performed = max_iterations;
    if ~isempty(filler_bits)
        c(filler_bits) = NaN;       % matches turbo_decoder.m output
    end

    [c_a, c_e] = realify(c_a_q, c_e_q, lsb);
end

% --------------------------------------------------------------------- %
% Helpers — local, self-contained.                                       %
% --------------------------------------------------------------------- %

function [stop, iters, c_out] = crc_stop_check(c_hard, G_max, iters_here, filler_bits)
    % Run calculate_crc_bits on the hard decision (BEFORE the filler NaN
    % overwrite, matching turbo_decoder.m). Returns stop=true and the
    % filler-NaN'd output when the CRC passes.
    pchk = calculate_crc_bits(c_hard, G_max);
    if sum(pchk) == 0
        stop  = true;
        iters = iters_here;
        c_out = c_hard;
        if ~isempty(filler_bits)
            c_out(filler_bits) = NaN;
        end
    else
        stop  = false;
        iters = iters_here;     % unused by caller when stop==false
        c_out = c_hard;
    end
end

function dq = quantize_matrix(d_a, lsb, lo, hi)
    % Quantize the full 3x(K+4) real-LLR matrix to integer codes on the
    % exchange grid (round-half-away-from-zero + saturate). +inf saturates to
    % hi; this is only used for the deterministic pre-loop sign test, whose
    % only requirement is that the sign matches the float's d_a(1:K) < 0.
    r  = d_a / lsb;
    dq = sign(r) .* floor(abs(r) + 0.5);
    dq = max(lo, min(hi, dq));
end

function [c_a, c_e] = realify(c_a_q, c_e_q, lsb)
    c_a = double(c_a_q) * lsb;
    c_e = double(c_e_q) * lsb;
end

function p = default_params()
    % Inner-core widths are the P1 pin; the extrinsic-exchange widths are the
    % P2 pin — both inherited UNCHANGED. The only NEW P3 knob is the HARQ
    % accumulator width W_harq, used by fixedpoint_turbo_harq_accumulate.m
    % (carried in the same struct so a single params override drives both).
    p = struct( ...
        'W_in',    9, ...   % core input LLR (Q4.4)  -- P1 pin
        'F_in',    4, ...   % LSB = 2^-4 = 0.0625    -- P1 pin (shared)
        'W_gamma', 10, ...  % P1 pin
        'W_ab',    15, ...  % P1 pin  (MAX_SENT = 2^14-1 = 16383)
        'W_delta', 17, ...  % P1 pin
        'W_xe',    18, ...  % P1 pin
        'W_ext',   12, ...  % P2 pin: stored extrinsic c_a/c_e word
        'W_acc',   14, ...  % P2 pin: combiner accumulator word
        'W_harq',  16);     % NEW P3 pin: HARQ soft-accumulator word (Q11.4)
end

function y = sat_round(x, lo, hi)
    r = sign(x) .* floor(abs(x) + 0.5);
    y = max(lo, min(hi, r));
end

function y = sat_clip(x, lo, hi)
    if x > hi
        y = hi;
    elseif x < lo
        y = lo;
    else
        y = x;
    end
end

function y = sat_add(a, b, lo, hi)
    s = a + b;
    if s > hi
        y = hi;
    elseif s < lo
        y = lo;
    else
        y = s;
    end
end
