function [c, c_a, c_e] = fixedpoint_turbo_decoder(d_a, pi, max_iterations, params)
% FIXEDPOINT_TURBO_DECODER  Fixed-point Max-Log-MAP *iterative* turbo
% decoder for the LTE turbo code (TS36.212 §5.1.3.2). This is the P2
% bit-exact oracle for the HDL core in
% openspec/changes/add-fpga-turbo-decode-loop — it wraps the P1
% fixed-point constituent reference (scripts/fixedpoint_constituent_decoder.m)
% inside the exact loop algebra of the float oracle turbo_decoder.m.
%
%   c = FIXEDPOINT_TURBO_DECODER(d_a, pi, max_iterations) decodes a code
%       block. d_a is the 3x(K+4) channel-LLR matrix (real LLRs, as fed to
%       turbo_decoder.m). pi is the QPP interleaver pattern (row vector of
%       length K, indices 0..K-1, c_prime = c(pi+1)). max_iterations is a
%       multiple of 0.5 (fixed iteration count; NO early termination, NO
%       filler/NaN — those are P3). c is the 1xK row of decoded hard bits.
%
%   [c, c_a, c_e] = ... also returns the final cyclic interleaved-extrinsic
%       state c_a[0..K-1] and the upper-decoder cyclic extrinsic c_e[0..K-1]
%       (both in real LLR space) for golden-vector / diagnostic use.
%
%   ... = FIXEDPOINT_TURBO_DECODER(..., params) overrides any field of the
%       parameter struct (see DEFAULT_PARAMS) — e.g. to widen the
%       extrinsic-exchange Q-format during characterization.
%
% ---------------------------------------------------------------------------
% Relationship to the float oracle (turbo_decoder.m):
%   This routine reproduces turbo_decoder.m's loop EXACTLY, but
%   (a) re-framed as H = round(2*max_iterations) half-iterations
%       (h even -> UPPER half, h odd -> LOWER half) so the "skip the final
%       lower half when 2*max_iter is odd" case falls out as simply stopping
%       at h == H (no ceil/floor), matching the HDL FSM; and
%   (b) every LLR add/quantize is a fixed-point saturating operation on a
%       pinned Q-format, with the inner constituent decoder being the P1
%       fixed-point reference UNMODIFIED (its internal alpha/beta/delta
%       widths and +/-inf sentinel are inherited; see its header).
%
% Float turbo_decoder.m per (full) iteration:
%       x_a(1:K) = c_a + d_a(1,1:K);                 % systematic a priori
%       x_e      = constituent_decoder(x_a, z_a);    % UPPER
%       c_e      = x_e(1:K) + d_a(1,1:K);
%       x'_a(1:K)= c_e(pi+1);                         % interleave
%       x'_e     = constituent_decoder(x'_a, z'_a);  % LOWER
%       c_a(pi+1)= x'_e(1:K);                         % deinterleave
%       c        = (c_a + c_e) < 0;                   % hard decision
%   The termination triplets x_a(K+1..K+3)/x'_a(K+1..K+3) and the parity
%   a-priori z_a/z'_a are CONSTANT across iterations; only the systematic
%   a-priori body x_a(1:K)/x'_a(1:K) changes. We mirror that exactly.
%
% ---------------------------------------------------------------------------
% Fixed-point format (the one genuinely NEW P2 decision: the
% extrinsic-exchange Q-format). Everything inside the constituent core is
% the P1 pin, inherited unchanged:
%
%   Inner core (inherited from P1, NOT re-derived here):
%     W_in=9 (Q4.4, F_in=4, LSB=2^-4), W_gamma=10, W_ab=15, W_delta=17,
%     W_xe=18; +/-inf sentinel MIN_SENT=-2^14; per-step max-norm; saturating.
%
%   Extrinsic exchange (NEW, pinned here; same fractional scale F_in=4 as the
%   core so the boundary is a pure width/saturate, no re-scaling):
%     - All persistent / cyclic LLR words (ch_sys, z_a, z'_a, c_a, c_e) and
%       the termination triplets are quantized ONCE to the same Q-format the
%       core uses for its inputs but stored in a WIDER signed word W_ext
%       (>= W_in) so extrinsics that grow across iterations are not clipped
%       prematurely. F is the same (F_in), so a value's integer code is just
%       value/2^-F_in.
%     - The combiner adds (x_a = c_a + ch_sys ; c_e = x_e + ch_sys ;
%       (c_a + c_e) for the hard decision) accumulate in a still-wider word
%       W_acc, saturating to the W_acc range, then are re-quantized
%       (saturated) to W_ext for storage as c_e/c_a, and to W_in for the
%       core input x_a/x'_a.
%     - The W_ext saturation reuses P1's sentinel *philosophy*: a single
%       symmetric saturating magnitude, no wrap, no new +/-inf token.
%
%   Why a separate W_ext > W_in: in turbo_decoder.m the systematic a-priori
%   fed to the core, x_a = c_a + ch_sys, is a SUM of two LLRs and c_a itself
%   accumulates extrinsic confidence across iterations. Re-quantizing that
%   sum to W_in=9 (range ~[-16,+16) at F_in=4) before the core is REQUIRED
%   (the core input must be W_in), but keeping the *stored* c_a/c_e and the
%   *accumulator* wider avoids saturating the exchange itself, which would
%   inject loss the float oracle does not have. The widths are pinned by the
%   outer BER characterization (scripts/characterize_turbo_decoder.m) ~1.5x
%   above worst observed, exactly as P1 pinned its equivalence band.
%
% Operation order (the HDL must replicate exactly, bit-for-bit):
%   0. Quantize ch_sys, z_a/z'_a bodies, and the termination triplets to the
%      exchange grid (round-half-away-from-zero + saturate to W_ext).
%      c_a := 0.
%   For h = 0 .. H-1:
%     UPPER (h even):
%       1. x_a(1:K)   = sat_add_acc(c_a, ch_sys)         [W_acc]
%       2. x_a_core   = requantize(x_a(1:K) -> W_in), termination triplets
%          requantized to W_in too (constant, but the core input width is W_in)
%       3. x_e        = fixedpoint_constituent_decoder(x_a_core, z_a_core)
%       4. c_e(1:K)   = sat_to_ext( sat_add_acc(x_e(1:K), ch_sys) )  [-> W_ext]
%     LOWER (h odd):
%       5. x'_a(1:K)  = c_e(pi+1)                          (interleave read)
%       6. x'_a_core  = requantize(x'_a(1:K) -> W_in); termination -> W_in
%       7. x'_e       = fixedpoint_constituent_decoder(x'_a_core, z'_a_core)
%       8. c_a(pi+1)  = sat_to_ext( x'_e(1:K) )            (deinterleave scatter)
%   Final: c(k) = ( sat_add_acc(c_a(k), c_e(k)) ) < 0     for k = 0..K-1
%
% This routine is intentionally written to mirror the HDL's likely structure
% (explicit per-element saturating ops, fixed op order) rather than to be
% Octave-idiomatic; clarity and bit-exactness > vectorization.

    if nargin < 4
        params = struct();
    end
    p = default_params();
    fns = fieldnames(params);
    for ii = 1:numel(fns)
        p.(fns{ii}) = params.(fns{ii});
    end

    % --- Shape / argument checks (mirror turbo_decoder.m). ---
    if size(d_a, 1) ~= 3
        error('fixedpoint_turbo_decoder:bad_d_a_rows', 'd_a should have 3 rows');
    end
    K = size(d_a, 2) - 4;
    if length(pi) ~= K
        error('fixedpoint_turbo_decoder:pi_length_mismatch', ...
              'length of pi does not match K');
    end
    if ~isnumeric(max_iterations) || ~isscalar(max_iterations) ...
            || ~isreal(max_iterations) || ~isfinite(max_iterations)
        error('fixedpoint_turbo_decoder:iterations_invalid', ...
              'max_iterations must be a real, finite numeric scalar');
    end
    if max_iterations ~= round(2 * max_iterations) / 2
        error('fixedpoint_turbo_decoder:iterations_not_half_multiple', ...
              'max_iterations must be a multiple of 0.5');
    end
    if max_iterations < 0
        error('fixedpoint_turbo_decoder:iterations_negative', ...
              'max_iterations must be non-negative');
    end
    if any(isnan(d_a(:)))
        % P2 boundary: no filler / NaN->+inf handling (that is P3).
        error('fixedpoint_turbo_decoder:filler_not_supported', ...
              'P2 does not handle filler/NaN in d_a (deferred to P3)');
    end

    % --- Saturation bounds. ---
    in_min  = -2^(p.W_in  - 1);    in_max  = 2^(p.W_in  - 1) - 1;   % core input
    ext_min = -2^(p.W_ext - 1);    ext_max = 2^(p.W_ext - 1) - 1;   % stored c_a/c_e
    acc_min = -2^(p.W_acc - 1);    acc_max = 2^(p.W_acc - 1) - 1;   % combiner accum
    lsb = 2^(-p.F_in);             % shared fractional scale (core + exchange)

    % Inner-core params struct passed to the P1 reference UNMODIFIED. We only
    % forward the inherited inner widths so an override of W_ext/W_acc here
    % never perturbs the core's bit-exact behaviour.
    core_p = struct('W_in', p.W_in, 'F_in', p.F_in, 'W_gamma', p.W_gamma, ...
                    'W_ab', p.W_ab, 'W_delta', p.W_delta, 'W_xe', p.W_xe);

    % --- De-mux d_a -> upper (x_a, z_a) / lower (x'_a, z'_a) + ch_sys, in
    %     REAL LLR space first (exactly as turbo_decoder.m lines 80-94). ---
    z_a       = zeros(1, K + 3);
    z_prime_a = zeros(1, K + 3);
    x_a       = zeros(1, K + 3);   % termination triplet x_a(K+1..K+3) is constant
    x_prime_a = zeros(1, K + 3);

    z_a(1:K)       = d_a(2, 1:K);
    z_prime_a(1:K) = d_a(3, 1:K);
    ch_sys         = d_a(1, 1:K);          % channel systematic LLR (persistent)

    x_a(K+1) = d_a(1, K+1);  z_a(K+1) = d_a(2, K+1);
    x_a(K+2) = d_a(3, K+1);  z_a(K+2) = d_a(1, K+2);
    x_a(K+3) = d_a(2, K+2);  z_a(K+3) = d_a(3, K+2);
    x_prime_a(K+1) = d_a(1, K+3);  z_prime_a(K+1) = d_a(2, K+3);
    x_prime_a(K+2) = d_a(3, K+3);  z_prime_a(K+2) = d_a(1, K+4);
    x_prime_a(K+3) = d_a(2, K+4);  z_prime_a(K+3) = d_a(3, K+4);

    % --- Quantize the PERSISTENT words to the exchange grid (W_ext, F_in).
    %     These are set once and never change across iterations. ---
    ch_sys_q = sat_round(ch_sys / lsb, ext_min, ext_max);   % integer codes

    % The parity a-priori z_a/z'_a bodies and the termination triplets are the
    % CORE's inputs, so they live at the core input width W_in. They are
    % constant across iterations -> quantize once.
    za_core      = sat_round(z_a       / lsb, in_min, in_max);
    zpa_core     = sat_round(z_prime_a / lsb, in_min, in_max);
    xa_term      = sat_round(x_a(K+1:K+3)       / lsb, in_min, in_max);
    xpa_term     = sat_round(x_prime_a(K+1:K+3) / lsb, in_min, in_max);

    % --- Cyclic state (integer codes on the exchange grid). ---
    c_a_q = zeros(1, K);    % interleaved extrinsic (state); c_a = 0 init.
    c_e_q = zeros(1, K);    % upper-decoder cyclic extrinsic.

    % --- Half-iteration loop. H = round(2*max_iterations). ---
    H = round(2 * max_iterations);

    for h = 0:H-1
        if mod(h, 2) == 0
            % ======================= UPPER half =======================
            % 1. systematic a priori x_a(1:K) = c_a + ch_sys, accumulator width.
            % 2. re-quantize to the core input width W_in (saturating).
            xa_body_core = zeros(1, K);
            for k = 1:K
                acc = sat_add(c_a_q(k), ch_sys_q(k), acc_min, acc_max);
                xa_body_core(k) = sat_clip(acc, in_min, in_max);
            end
            % Assemble the full K+3 core input (body + constant termination).
            xa_core = [xa_body_core, xa_term];

            % 3. UPPER constituent decoder (P1 reference, UNMODIFIED). It
            %    quantizes its inputs to W_in internally too; we pass integer
            %    codes scaled back to real LLR space (* lsb) since the core
            %    re-quantizes on entry. (Round-trip is exact: integer*lsb/lsb
            %    rounds to the same integer, and it is within [in_min,in_max].)
            [x_e_real, x_e_q] = fixedpoint_constituent_decoder( ...
                double(xa_core) * lsb, double(za_core) * lsb, core_p); %#ok<ASGLU>

            % 4. c_e(1:K) = x_e(1:K) + ch_sys, accumulate then store at W_ext.
            %    x_e_q is in W_xe integer codes at the SAME F_in scale (the
            %    core's output LSB == its input LSB), so the add is grid-aligned.
            for k = 1:K
                acc = sat_add(x_e_q(k), ch_sys_q(k), acc_min, acc_max);
                c_e_q(k) = sat_clip(acc, ext_min, ext_max);
            end
        else
            % ======================= LOWER half =======================
            % 5. interleave read: x'_a(1:K) = c_e(pi+1).
            % 6. re-quantize the (already on-grid) c_e to W_in for the core.
            xpa_body_core = zeros(1, K);
            ce_perm = c_e_q(pi + 1);          % interleave read (gather)
            for k = 1:K
                xpa_body_core(k) = sat_clip(ce_perm(k), in_min, in_max);
            end
            xpa_core = [xpa_body_core, xpa_term];

            % 7. LOWER constituent decoder (P1 reference, UNMODIFIED).
            [xp_e_real, xp_e_q] = fixedpoint_constituent_decoder( ...
                double(xpa_core) * lsb, double(zpa_core) * lsb, core_p); %#ok<ASGLU>

            % 8. deinterleave scatter: c_a(pi+1) = x'_e(1:K), stored at W_ext.
            scatter = zeros(1, K);
            for k = 1:K
                scatter(k) = sat_clip(xp_e_q(k), ext_min, ext_max);
            end
            c_a_q(pi + 1) = scatter;          % deinterleave (scatter)
        end
    end

    % --- Final hard decision: c(k) = (c_a(k) + c_e(k)) < 0. ---
    c = zeros(1, K);
    for k = 1:K
        acc = sat_add(c_a_q(k), c_e_q(k), acc_min, acc_max);
        c(k) = double(acc < 0);
    end

    % --- Diagnostics returned in real LLR space (integer code * lsb). ---
    c_a = double(c_a_q) * lsb;
    c_e = double(c_e_q) * lsb;
end

% --------------------------------------------------------------------- %
% Helpers — local, so the file is self-contained for review. The arith   %
% helpers mirror the P1 reference's sat_round/sat_add naming/semantics.  %
% --------------------------------------------------------------------- %

function p = default_params()
    % Inner-core widths are the P1 pin (inherited UNCHANGED — do not
    % re-derive; see scripts/fixedpoint_constituent_decoder.m).
    %
    % Extrinsic-exchange widths (the P2 pin, set by the BER characterization):
    %   W_ext = 12  : stored c_a/c_e word (3 integer bits over W_in's range:
    %                 ~[-128,+128) at F_in=4). Extrinsics accumulate confidence
    %                 across H=16 half-iterations; W_in=9 (~[-16,+16)) clips
    %                 strong extrinsics and injects loss the float oracle lacks.
    %   W_acc = 14  : combiner accumulator for c_a+ch_sys, x_e+ch_sys, c_a+c_e
    %                 (one bit over W_ext for the two-operand sum + margin).
    % F_in is shared with the core so the exchange<->core boundary is a pure
    % width/saturate (no rescaling).
    p = struct( ...
        'W_in',    9, ...   % core input LLR (Q4.4)  -- P1 pin
        'F_in',    4, ...   % LSB = 2^-4 = 0.0625    -- P1 pin (shared)
        'W_gamma', 10, ...  % P1 pin
        'W_ab',    15, ...  % P1 pin
        'W_delta', 17, ...  % P1 pin
        'W_xe',    18, ...  % P1 pin
        'W_ext',   12, ...  % NEW P2 pin: stored extrinsic c_a/c_e word
        'W_acc',   14);     % NEW P2 pin: combiner accumulator word
end

function y = sat_round(x, lo, hi)
    % Round to nearest integer (half away from zero) then saturate.
    r = sign(x) .* floor(abs(x) + 0.5);
    y = max(lo, min(hi, r));
end

function y = sat_clip(x, lo, hi)
    % Saturate an already-integer code to [lo, hi] (no rounding).
    if x > hi
        y = hi;
    elseif x < lo
        y = lo;
    else
        y = x;
    end
end

function y = sat_add(a, b, lo, hi)
    % Two-operand saturating signed add (scalar; the HDL does the same).
    s = a + b;
    if s > hi
        y = hi;
    elseif s < lo
        y = lo;
    else
        y = s;
    end
end
