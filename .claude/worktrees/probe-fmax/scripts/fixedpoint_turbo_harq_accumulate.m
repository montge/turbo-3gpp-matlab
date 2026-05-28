function [buf, d_combined] = fixedpoint_turbo_harq_accumulate(buf, d_a, params)
% FIXEDPOINT_TURBO_HARQ_ACCUMULATE  Fixed-point HARQ soft-combining buffer
% for the P3 turbo decoder, mirroring turbo_decoding_chain.m's
%   obj.buffers{r+1} = obj.buffers{r+1} + d;
% accumulation (with resetImpl zeroing the buffer between information
% blocks). This is the bit-exact reference for the HDL HARQ soft-accumulate
% stage (openspec/changes/add-fpga-turbo-decoder-termination, design.md
% Decision 5).
%
%   [buf, d_combined] = FIXEDPOINT_TURBO_HARQ_ACCUMULATE(buf, d_a)
%       accumulates one retransmission's 3x(K+4) channel-LLR matrix d_a into
%       the soft buffer buf, returning the updated buffer AND the combined
%       matrix to feed the decoder.
%
%   buf   — the running soft buffer in INTEGER LSB codes on the HARQ
%           accumulator grid (W_harq bits, F_in fractional). Pass [] (or a
%           zero matrix) for the first transmission; the helper sizes it from
%           d_a. To RESET between information blocks, pass [] again (the
%           float resetImpl equivalent).
%   d_a   — the incoming retransmission's 3x(K+4) channel LLRs in REAL LLR
%           space (the same matrix fed to the float turbo_decoder). NaN
%           filler entries are mapped to the +inf token (P1 MAX_SENT) and
%           accumulate idempotently (a known bit stays known — saturating add
%           of two saturated max-magnitude codes stays saturated).
%   params— optional fixed-point format overrides (see the decoder's
%           DEFAULT_PARAMS). Uses W_harq (the HARQ accumulator width), W_ext
%           (the exchange word the combined matrix is re-quantized to before
%           decoding) and F_in (shared fractional scale).
%
%   d_combined — the accumulated buffer SATURATED back to the W_ext exchange
%           word and returned in REAL LLR space (= integer code * 2^-F_in),
%           ready to pass as d_a to fixedpoint_turbo_decoder_term. Filler
%           positions remain +inf (the sentinel survives the re-quantize).
%
% ---------------------------------------------------------------------------
% PINNED WIDTH (design.md "Fixed-point format" table; the ONLY new P3 knob):
%   Channel-LLR exchange word ........ W_ext  = 12  (Q7.4, range [-2048, 2047])
%   Max retransmissions .............. N_retx_max = 4   (user-confirmed)
%   HARQ accumulator word ............ W_harq = 16  (Q11.4, range [-32768, 32767])
%
%   Sizing rationale: a saturating sum of N_retx_max = 4 channel-LLR words
%   reaches at most 4 * 2047 = 8188 in magnitude (needs 14 bits signed). The
%   accumulator is widened to 16 bits = W_ext + ceil(log2(4)) + 2 margin bits,
%   i.e. ~1.5x above the worst-case sum (32767 / 8188 ~= 4.0x headroom — fully
%   inside the "~1.5x above worst observed need" band P1/P2 used, and never
%   wraps for the pinned N_retx_max=4). The add SATURATES to the W_harq range
%   (no wrap); the combined matrix is then SATURATED to W_ext before decoding
%   (the de-mux input format is unchanged from P2). The decode datapath gets
%   NO new format — only this accumulator (design.md Decision 6).
%
%   Filler MAX_SENT idempotency: a filler position is +inf -> ext_max in the
%   exchange grid; on the accumulator grid it saturates to harq_max. Adding
%   another +inf retransmission saturates again to harq_max; re-quantizing to
%   W_ext saturates to ext_max -> still +inf at the core input. A known bit
%   therefore stays known across all retransmissions (design.md Decision 5).

    if nargin < 3
        params = struct();
    end
    p = default_params();
    fns = fieldnames(params);
    for ii = 1:numel(fns)
        p.(fns{ii}) = params.(fns{ii});
    end

    if size(d_a, 1) ~= 3
        error('fixedpoint_turbo_harq_accumulate:bad_d_a_rows', ...
              'd_a should have 3 rows');
    end

    lsb       = 2^(-p.F_in);
    harq_min  = -2^(p.W_harq - 1);   harq_max = 2^(p.W_harq - 1) - 1;
    ext_min   = -2^(p.W_ext  - 1);   ext_max  = 2^(p.W_ext  - 1) - 1;

    % --- Map NaN filler -> +inf (P1 sentinel), exactly as the decoder does. ---
    d_a(isnan(d_a)) = inf;

    % --- Quantize the incoming retransmission to the HARQ accumulator grid
    %     (round-half-away-from-zero + saturate to W_harq). +inf -> harq_max. ---
    d_q = sat_round(d_a / lsb, harq_min, harq_max);

    % --- Initialise / reset the buffer (float resetImpl: zeros(3, D_r)). ---
    if isempty(buf)
        buf = zeros(size(d_q));
    end
    if ~isequal(size(buf), size(d_q))
        error('fixedpoint_turbo_harq_accumulate:size_mismatch', ...
              'buffer size [%s] does not match d_a [%s]', ...
              num2str(size(buf)), num2str(size(d_q)));
    end

    % --- Saturating accumulate: buffer = buffer + d (element-wise). ---
    s   = buf + d_q;
    buf = max(harq_min, min(harq_max, s));

    % --- Re-quantize (saturate) to the W_ext exchange word and return in real
    %     LLR space, ready for the decoder's de-mux. ---
    d_ext      = max(ext_min, min(ext_max, buf));
    d_combined = double(d_ext) * lsb;
end

% --------------------------------------------------------------------- %

function p = default_params()
    p = struct( ...
        'W_in',    9, ...
        'F_in',    4, ...
        'W_gamma', 10, ...
        'W_ab',    15, ...
        'W_delta', 17, ...
        'W_xe',    18, ...
        'W_ext',   12, ...
        'W_acc',   14, ...
        'W_harq',  16);     % NEW P3 pin (the only new fixed-point knob)
end

function y = sat_round(x, lo, hi)
    r = sign(x) .* floor(abs(x) + 0.5);
    y = max(lo, min(hi, r));
end
