function [d_a, d_a_q] = fixedpoint_de_rate_matching(e, K, F_r, N_ref, I_LBRM, rv_idx, E, params)
% FIXEDPOINT_DE_RATE_MATCHING  Fixed-point de-rate-matching (rate
% DEmatching) reference for the LTE turbo code (TS36.212 §5.1.4.1). This is
% the P4 (RX-chain) bit-exact inner oracle for the HDL core in
% openspec/changes/add-fpga-rx-chain-integration — see that change's
% design.md (Decision 1 inverse circular-buffer soft-combine + inverse
% subblock-interleave, Decision 3 fixed-point pins).
%
% The float de-rate-match is NOT a standalone .m — it is inline in
% turbo_decoding_chain.m (lines 86-93). This routine factors that algebra
% into a callable function AND adds the fixed-point quantization /
% saturating soft-combine, mirroring how P1/P2/P3 authored their fixed-point
% references (fixedpoint_constituent_decoder.m / fixedpoint_turbo_decoder.m
% / fixedpoint_turbo_decoder_term.m).
%
%   d_a = FIXEDPOINT_DE_RATE_MATCHING(e, K, F_r, N_ref, I_LBRM, rv_idx, E)
%       de-rate-matches the length-E received channel-LLR vector e back to
%       the 3x(K+4) soft d_a matrix the turbo decoder loads. e is in REAL
%       LLR space; it is quantized internally to the W_LLR (Q3.4) channel
%       grid. d_a is returned in REAL LLR space (= integer code * 2^-F_in),
%       with filler positions = +inf (the float oracle's NaN, which the
%       decoder maps to +inf) and untransmitted (erasure) positions = 0.
%
%   [d_a, d_a_q] = ... also returns the raw W_EXT integer codes (the
%       saturated W_EXT grid words) for golden-CSV generation (P4 task 2.1).
%       In d_a_q, filler positions hold the +inf sentinel ext_max (the P1
%       MAX_SENT mapped onto the W_EXT grid); erasure positions hold 0.
%
%   ... = FIXEDPOINT_DE_RATE_MATCHING(..., params) overrides any field of
%       the parameter struct (see DEFAULT_PARAMS) — e.g. to widen W_LLR /
%       W_DRM during characterization.
%
% ---------------------------------------------------------------------------
% Relationship to the float oracle (turbo_decoding_chain.m lines 86-93):
%       d_vec = zeros(1,3*D);                              % erasure default = 0
%       for k = 0:length(pi)-1
%           d_vec(pi(k+1)+1) = d_vec(pi(k+1)+1) + e(k+1);  % SCATTER-ACCUMULATE
%       end
%       d = reshape(d_vec,3,D);
%       d(1:2,1:F_r) = NaN;                                % filler -> +inf
%   where pi == rate_matching_patterns{r+1} is the SAME length-E permutation
%   the TX rate_matching(d, N_ref, I_LBRM, rv_idx, E) produces (the inverse
%   of the gather e = d_vec(pi+1)). D = K+4. The scatter visits a w-position
%   more than once when E > N_cb (circular-buffer wrap / high coding rate),
%   so the inverse is an ACCUMULATE that soft-combines every LLR landing on
%   that position; positions the read never visited stay 0 (erasure, no
%   channel information). This routine reproduces that EXACTLY, but
%   (a) builds pi via the existing rate_matching.m helper (same construction
%       as turbo_coding_chain.m processTunedPropertiesImpl), so the
%       permutation/accumulate is INTEGER-EXACT against the float path; and
%   (b) every LLR is quantized/accumulated as a fixed-point saturating
%       operation on the pinned grids below.
%
% ---------------------------------------------------------------------------
% Fixed-point format (PINNED in design.md Decision 3; the only NEW P4 knob is
% the soft-combine accumulator width W_DRM):
%
%   Received channel LLR input e[k] .. W_LLR = 8  (Q3.4, F_in=4, range
%                                      [-128, +127] codes => ~[-8, +8) LLR) —
%                                      the demapper/test-harness input
%                                      contract; e is quantized to this grid
%                                      on entry.
%   Soft-combine accumulator w_soft .. W_DRM = 16 (Q11.4, range
%                                      [-32768, 32767]); the inverse
%                                      circular-buffer scatter-accumulate
%                                      d_vec(pi+1) += e is a SATURATING add on
%                                      this grid (reuses the P3 W_harq = 16
%                                      precedent so a deferred HARQ accumulate
%                                      can share the buffer/width).
%   Output d_a word ................. W_EXT = 12 (Q7.4, range [-2048, 2047]) —
%                                      the decoder's inherited exchange word;
%                                      the W_DRM accumulator is SATURATED to
%                                      W_EXT at the output.
%   Filler-bit token ................ +inf -> ext_max (the P1 MAX_SENT
%                                      sentinel, reused unchanged; the float
%                                      d(1:2,1:F_r)=NaN, which the decoder
%                                      maps to +inf).
%   Erasure (untransmitted position)  0 LLR (equal-probability) — the
%                                      zero-init of the accumulate; no new
%                                      token.
%
%   Sizing rationale (the >=1.5x band P1/P2/P3 used): the channel-LLR word is
%   W_LLR = 8 (max magnitude 128). A w-position can be hit by at most a few
%   wrap visits within one transmission (and, in the deferred HARQ case,
%   across up to N_retx = 4 transmissions); a saturating sum of conservatively
%   4*128 = 512 needs 11 signed bits. W_DRM = 16 (+/-32768) gives
%   32767 / 512 ~= 64x headroom — it never wraps for any realistic visit
%   count. The accumulate SATURATES to W_DRM; the result is SATURATED to
%   W_EXT at the output (decoder load format unchanged). The +inf filler is
%   idempotent under the saturating accumulate (a known bit stays known),
%   matching the P3 filler treatment.
%
% Operation order (the HDL must replicate exactly, bit-for-bit):
%   1. Build the length-E rate-matching permutation pi via rate_matching.m on
%      the index template (identical to turbo_coding_chain.m
%      processTunedPropertiesImpl): the inverse uses the SAME pi the TX
%      gather used.
%   2. Quantize the E received LLRs e[k] to the W_LLR channel grid
%      (round-half-away-from-zero + saturate). Integer codes e_q[k].
%   3. Zero the 3*D-length soft accumulator w_soft (W_DRM codes); 0 = erasure.
%   4. SCATTER-ACCUMULATE, in k = 0..E-1 order (matching the float loop
%      order, which is the only thing that matters since saturating add of
%      same-sign-bounded LLRs is order-robust but we fix the order anyway):
%          w_soft(pi(k)+1) = sat_add_W_DRM( w_soft(pi(k)+1), e_q(k) ).
%   5. Reshape w_soft to 3xD (column-major), recovering d_a's body.
%   6. Filler: set d_a(1, 1:F_r) and d_a(2, 1:F_r) to the +inf token
%      (ext_max on the W_EXT grid). (Row 3 is NOT filler-masked, matching the
%      float which sets only rows 1:2.)
%   7. Saturate every non-filler d_a word from W_DRM down to W_EXT.
%
% This routine is intentionally written to mirror the HDL's likely structure
% (explicit per-element saturating ops, fixed op order) rather than to be
% Octave-idiomatic; clarity and bit-exactness > vectorization.

    if nargin < 8
        params = struct();
    end
    p = default_params();
    fns = fieldnames(params);
    for ii = 1:numel(fns)
        p.(fns{ii}) = params.(fns{ii});
    end

    % --- Argument checks. ---
    if ~isvector(e)
        error('fixedpoint_de_rate_matching:bad_e', 'e must be a vector');
    end
    e = e(:).';                          % force row
    if numel(e) ~= E
        error('fixedpoint_de_rate_matching:E_mismatch', ...
              'length(e) = %d does not match E = %d', numel(e), E);
    end
    if F_r < 0 || F_r > K
        error('fixedpoint_de_rate_matching:bad_F_r', ...
              'F_r = %d out of range [0, K = %d]', F_r, K);
    end

    D = K + 4;                           % D_r = K_r + 4 (turbo_coding_chain.m)

    % --- Saturation bounds for each width. ---
    lsb     = 2^(-p.F_in);               % shared fractional scale.
    llr_min = -2^(p.W_LLR - 1);   llr_max = 2^(p.W_LLR - 1) - 1;   % channel in
    drm_min = -2^(p.W_DRM - 1);   drm_max = 2^(p.W_DRM - 1) - 1;   % accumulator
    ext_min = -2^(p.W_EXT - 1);   ext_max = 2^(p.W_EXT - 1) - 1;   % output word

    MAX_SENT = ext_max;                  % +inf filler token on the W_EXT grid
                                         % (the P1 sentinel; the float NaN).

    % --- 1. Build the length-E rate-matching permutation pi, EXACTLY as
    %        turbo_coding_chain.m processTunedPropertiesImpl does (the same
    %        pi the TX gather used; the RX scatter is its inverse). pi holds
    %        0-based indices into the 3*D-length d_vec. ---
    d_idx = reshape(0:3*D-1, 3, D);
    d_idx(1:2, 1:F_r) = NaN;             % filler punctured in the TX template
    pii = rate_matching(d_idx, N_ref, I_LBRM, rv_idx, E);   % length E, 0-based

    % --- 2. Quantize the received LLRs to the W_LLR channel grid. ---
    e_q = sat_round(e / lsb, llr_min, llr_max);   % integer codes, length E

    % --- 3. Zero the soft accumulator (3*D W_DRM codes); 0 = erasure. ---
    w_soft = zeros(1, 3 * D);

    % --- 4. Scatter-accumulate (saturating add on the W_DRM grid), k order. ---
    %     This is the float d_vec(pi(k)+1) += e(k) loop, position by position;
    %     wrap visits (E > N_cb) soft-combine, never-visited positions stay 0.
    for k = 1:E
        idx = pii(k) + 1;                % 0-based pi -> 1-based index
        w_soft(idx) = sat_add(w_soft(idx), e_q(k), drm_min, drm_max);
    end

    % --- 5. Reshape to 3xD (column-major), recovering the d_a body. ---
    d_a_q = reshape(w_soft, 3, D);

    % --- 7. Saturate every word from W_DRM down to the W_EXT output grid. ---
    %     (Done before the filler write so the filler token is exactly
    %     ext_max and is not itself re-saturated.)
    for c = 1:D
        for rrow = 1:3
            d_a_q(rrow, c) = sat_clip(d_a_q(rrow, c), ext_min, ext_max);
        end
    end

    % --- 6. Filler: rows 1:2 of the first F_r columns -> +inf token. The
    %        float sets d(1:2,1:F_r) = NaN (-> +inf in the decoder). Row 3 is
    %        NOT masked (matching the float). ---
    if F_r > 0
        d_a_q(1, 1:F_r) = MAX_SENT;
        d_a_q(2, 1:F_r) = MAX_SENT;
    end

    % --- Return in REAL LLR space. Filler -> +inf so it compares directly to
    %     the float oracle's NaN (which the decoder treats as +inf); erasure
    %     and finite values = integer code * lsb. ---
    d_a = double(d_a_q) * lsb;
    if F_r > 0
        d_a(1, 1:F_r) = inf;
        d_a(2, 1:F_r) = inf;
    end
end

% --------------------------------------------------------------------- %
% Helpers — local, so the file is self-contained for review. The arith   %
% helpers mirror the P1/P2/P3 reference sat_round/sat_add semantics.      %
% --------------------------------------------------------------------- %

function p = default_params()
    % PINNED widths per design.md Decision 3 (the only NEW P4 knob is W_DRM).
    %   W_LLR = 8  : received channel-LLR input word (Q3.4). The RX input
    %                contract — the demapper/test harness quantizes channel
    %                LLRs to this grid before the RX chain.
    %   W_DRM = 16 : soft-combine accumulator (Q11.4); reuses the P3 W_harq.
    %   W_EXT = 12 : decoder load word (Q7.4); inherited from P2 UNCHANGED.
    %   F_in  = 4  : shared fractional scale across all three grids, so every
    %                grid->grid boundary is a pure width/saturate (no rescale).
    p = struct( ...
        'W_LLR', 8, ...     % channel-LLR input (Q3.4)
        'F_in',  4, ...     % LSB = 2^-4 = 0.0625 (shared)
        'W_DRM', 16, ...    % soft-combine accumulator (Q11.4) -- the NEW knob
        'W_EXT', 12);       % decoder load word (Q7.4) -- inherited (P2)
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
