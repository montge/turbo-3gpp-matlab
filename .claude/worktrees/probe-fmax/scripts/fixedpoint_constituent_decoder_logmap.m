function [x_e, x_e_q] = fixedpoint_constituent_decoder_logmap(x_a, z_a, params)
% FIXEDPOINT_CONSTITUENT_DECODER_LOGMAP  Fixed-point *exact* Log-MAP port of
% constituent_decoder.m for the LTE turbo constituent code (TS36.212
% §5.1.3.2). This is the M1 (add-fpga-decoder-exact-log-map) bit-exact
% oracle: the Max-Log-MAP fixed-point datapath of
% scripts/fixedpoint_constituent_decoder.m with the Jacobian-logarithm
% correction  max*(a,b) = max(a,b) + f(|a-b|),  f(d)=ln(1+e^-d)  applied
% (as a quantized LUT add) at every 2-way max of the alpha / beta
% recurrences and at every 2-way node of the two extrinsic max-trees.
% See openspec/changes/add-fpga-decoder-exact-log-map/design.md (§2 LUT
% mapping, §3 pinned LUT depth/contents, §4 the 8-way fold order/bit-exact
% contract, §5 the superset gate).
%
%   x_e            = FIXEDPOINT_CONSTITUENT_DECODER_LOGMAP(x_a, z_a) decodes
%                    a code block in scaled-real space using a fixed-point
%                    exact-Log-MAP Log-BCJR. x_a / z_a are real-valued
%                    a-priori LLRs (length K+3) quantized internally to the
%                    W_in/F_in Q-format. Returned x_e is in the same real
%                    LLR space (= integer code * 2^-F_in), length K+3.
%   [x_e, x_e_q]   = also returns the raw extrinsic integer codes in the
%                    W_xe-bit signed range (for golden-CSV generation,
%                    task 1.2 / stage 2).
%   ... = FIXEDPOINT_CONSTITUENT_DECODER_LOGMAP(x_a, z_a, params) overrides
%                    any field of the parameter struct (see DEFAULT_PARAMS).
%
% SUPERSET CONTRACT (asserted by the self-test / characterizer):
%   With params.EXACT_LOGMAP = false (or the LUT forced to all-zero), this
%   routine reproduces scripts/fixedpoint_constituent_decoder.m BYTE-EXACT:
%   max*(a,b) collapses to plain max(a,b) (the correction add is 0), the
%   8-way folds reduce to plain 8-way max (max is associative, so the
%   left-fold order is irrelevant for the value), and every width /
%   sentinel / normalization step is identical. With EXACT_LOGMAP = true
%   the correction tracks the float exact-Log-MAP oracle
%   (constituent_decoder.m with the global approx_star = false).
%
% Bit-exactness contract (must match the HDL exactly):
%   - max*(a,b) = max(a,b) + corr_code(sat(|a-b|, 0..LUT_D-1)). The
%     correction is an integer LSB code added to the integer max; index is
%     the saturated absolute difference (same F_in grid, no rescale).
%   - Sites: EVERY 2-way max of the alpha aggregation (2 transitions into
%     each state), beta aggregation (2 transitions out of each state), and
%     each 2-way node of the extrinsic delta max-trees (folded as a
%     sequential LEFT FOLD in ascending transition index, seeded from the
%     first delta of the set — the non-associative fold order is part of
%     the contract; design.md §4).
%   - NOT applied at: the per-step alpha/beta max-normalization (a plain
%     max+subtract bookkeeping offset that cancels in log_p0-log_p1) nor
%     the final sat_sub(log_p0, log_p1). Those stay plain ops in both modes
%     (design.md §2).
%   - Inherited Max-Log-MAP pins (UNCHANGED from the P1 reference): signed
%     saturating Q-format, per-step max-normalization, +/-inf sentinel
%     MIN_SENT = -2^(W_ab-1).
%
% Pinned widths (inherited from scripts/fixedpoint_constituent_decoder.m):
%   W_in = 9, F_in = 4, W_gamma = 10, W_ab = 15, W_delta = 17, W_xe = 18.
%
% Like the P1 reference, this is written to mirror the HDL's likely
% structure (explicit scalar saturating ops, fixed op order) rather than
% to be Octave-idiomatic; clarity + bit-exactness > vectorization.

    if nargin < 3
        params = struct();
    end
    p = default_params();
    fns = fieldnames(params);
    for ii = 1:numel(fns)
        p.(fns{ii}) = params.(fns{ii});
    end

    if length(x_a) ~= length(z_a)
        error('fixedpoint_constituent_decoder_logmap:LengthMismatch', ...
              'LLR sequences must have the same length');
    end
    if size(x_a, 1) ~= 1 || size(z_a, 1) ~= 1
        x_a = x_a(:).';
        z_a = z_a(:).';
    end

    N = length(x_a);        % = K + 3 termination symbols included
    STATES = 8;             % memory-3 trellis
    TRANS = 16;             % 2 transitions per from-state

    % --- Trellis (identical to constituent_decoder.m, indices 1..8). ---
    % Columns: FromState, ToState, x (input bit), z (parity bit).
    transitions = [ ...
        1, 1, 0, 0;  2, 5, 0, 0;  3, 6, 0, 1;  4, 2, 0, 1; ...
        5, 3, 0, 1;  6, 7, 0, 1;  7, 8, 0, 0;  8, 4, 0, 0; ...
        1, 5, 1, 1;  2, 1, 1, 1;  3, 2, 1, 0;  4, 6, 1, 0; ...
        5, 7, 1, 0;  6, 3, 1, 0;  7, 4, 1, 1;  8, 8, 1, 1];

    from_state = transitions(:, 1);
    to_state   = transitions(:, 2);
    x_bit      = transitions(:, 3);
    z_bit      = transitions(:, 4);

    % Precompute, for each state, which two transitions enter it (alpha
    % aggregation) and which two leave it (beta aggregation). Order is
    % fixed (ascending transition index) so the HDL can do the same — and
    % so the lower-index candidate is `cand1` (design.md §4).
    into_state  = cell(STATES, 1);
    outof_state = cell(STATES, 1);
    for s = 1:STATES
        into_state{s}  = find(to_state   == s);
        outof_state{s} = find(from_state == s);
    end

    % The x=0 and x=1 transition index sets, in ASCENDING order (the fold
    % order for the extrinsic max-trees; pinned in design.md §4).
    x0_idx = find(x_bit == 0).';   % {1,2,3,4,5,6,7,8}
    x1_idx = find(x_bit == 1).';   % {9,10,11,12,13,14,15,16}

    % --- Saturation bounds for each width. ---
    in_min   = -2^(p.W_in   - 1);   in_max   = 2^(p.W_in   - 1) - 1;
    ab_min   = -2^(p.W_ab   - 1);   ab_max   = 2^(p.W_ab   - 1) - 1;
    de_min   = -2^(p.W_delta- 1);   de_max   = 2^(p.W_delta- 1) - 1;
    xe_min   = -2^(p.W_xe   - 1);   xe_max   = 2^(p.W_xe   - 1) - 1;

    MIN_SENT = ab_min;              % +/-inf sentinel for alpha/beta init.

    % --- Correction LUT (design.md §3). Built by the pinned formula and
    %     cross-checked against the pinned table; if EXACT_LOGMAP=false it
    %     is forced all-zero so max* == max (the superset). ---
    lut = build_correction_lut(p.LUT_D, p.F_in);
    if ~p.EXACT_LOGMAP
        lut = zeros(size(lut));     % f == 0  =>  max*(a,b) == max(a,b)
    end

    % --- 1. Quantize inputs to Q(W_in-1-F_in).F_in (signed, saturating).
    lsb = 2^(-p.F_in);
    x_q = sat_round(x_a / lsb, in_min, in_max);
    z_q = sat_round(z_a / lsb, in_min, in_max);

    % --- 2. Branch metrics per bit position (integer LSB units).
    gammas_x = zeros(TRANS, N);
    gammas_x(x_bit == 1, :) = repmat(-x_q, sum(x_bit == 1), 1);

    gammas_z = zeros(TRANS, N);
    gammas_z(z_bit == 1, :) = repmat(-z_q, sum(z_bit == 1), 1);

    gammas = gammas_x + gammas_z;   % values in (-2^W_in, 2^W_in)

    % --- 3. Forward recursion. alphas in W_ab bits, normalized per step.
    alphas = zeros(STATES, N);
    alphas(2:end, 1) = MIN_SENT;    % start state is state 1; others = -inf
    for k = 2:N
        new_alpha = zeros(STATES, 1);
        for s = 1:STATES
            t_idx = into_state{s};   % exactly 2 transition indices (ascending)
            cand1 = sat_add(alphas(from_state(t_idx(1)), k-1), ...
                            gammas(t_idx(1), k-1), ab_min, ab_max);
            cand2 = sat_add(alphas(from_state(t_idx(2)), k-1), ...
                            gammas(t_idx(2), k-1), ab_min, ab_max);
            % 2-way max* (= max + correction); ab_max guards the +corr add.
            new_alpha(s) = maxstar_fp(cand1, cand2, lut, ab_min, ab_max);
        end
        % Per-step max-normalization: plain max+subtract (NO correction).
        m = max(new_alpha);
        for s = 1:STATES
            alphas(s, k) = sat_sub(new_alpha(s), m, ab_min, ab_max);
        end
    end

    % --- 4. Backward recursion. Symmetrical to alpha.
    betas = zeros(STATES, N);
    betas(2:end, end) = MIN_SENT;   % terminated in state 1; others = -inf
    for k = N-1:-1:1
        new_beta = zeros(STATES, 1);
        for s = 1:STATES
            t_idx = outof_state{s};  % exactly 2 transition indices (ascending)
            cand1 = sat_add(betas(to_state(t_idx(1)), k+1), ...
                            gammas(t_idx(1), k+1), ab_min, ab_max);
            cand2 = sat_add(betas(to_state(t_idx(2)), k+1), ...
                            gammas(t_idx(2), k+1), ab_min, ab_max);
            new_beta(s) = maxstar_fp(cand1, cand2, lut, ab_min, ab_max);
        end
        m = max(new_beta);
        for s = 1:STATES
            betas(s, k) = sat_sub(new_beta(s), m, ab_min, ab_max);
        end
    end

    % --- 5. Per-transition delta and 6. extrinsic.
    x_e_q = zeros(1, N);
    for k = 1:N
        deltas_k = zeros(TRANS, 1);
        for t = 1:TRANS
            ab_sum = sat_add(alphas(from_state(t), k), ...
                             betas (to_state  (t), k), ...
                             de_min, de_max);
            deltas_k(t) = sat_add(ab_sum, gammas_z(t, k), de_min, de_max);
        end

        % 8-way max* over x=0 / x=1 as a SEQUENTIAL LEFT FOLD in ascending
        % transition index, seeded from the first delta of the set.
        % max* is NOT associative, so the fold order is part of the
        % bit-exact contract (design.md §4). The delta width W_delta bounds
        % the +corr add.
        log_p0 = maxstar_fold(deltas_k(x0_idx), lut, de_min, de_max);
        log_p1 = maxstar_fold(deltas_k(x1_idx), lut, de_min, de_max);

        % Final extrinsic difference: plain saturating subtract (no corr).
        x_e_q(k) = sat_sub(log_p0, log_p1, xe_min, xe_max);
    end

    % --- Scale back to real LLR space (= integer code * 2^-F_in).
    x_e = double(x_e_q) * lsb;
end

% --------------------------------------------------------------------- %
% Helpers — kept local so the file is fully self-contained for review.   %
% --------------------------------------------------------------------- %

function p = default_params()
    % Inner-core widths are the P1 pin (inherited UNCHANGED; see
    % scripts/fixedpoint_constituent_decoder.m). The only NEW knobs are the
    % exact-Log-MAP enable and the correction-LUT depth.
    p = struct( ...
        'W_in',   9, ...        % signed Q(4).(4) input LLRs
        'F_in',   4, ...        %   => LSB = 2^-4 = 0.0625
        'W_gamma',10, ...       % |gamma| <= |x_a| + |z_a| <= 2^W_in
        'W_ab',   15, ...       % post-norm alpha/beta width
        'W_delta',17, ...       % alpha + beta + gamma_z (two saturating adds)
        'W_xe',   18, ...       % max(delta|x=0) - max(delta|x=1)
        'EXACT_LOGMAP', true, ...   % M1: exact Log-MAP correction ON by default
        'LUT_D',  56);          % correction-LUT depth (design.md §3)
end

function lut = build_correction_lut(D, F_in)
    % Quantized Jacobian-logarithm correction (design.md §2/§3):
    %   corr_code(dcode) = round( ln(1 + e^-(dcode * 2^-F_in)) * 2^F_in )
    % for the integer absolute-difference code dcode = 0 .. D-1. The
    % returned vector is 1-indexed (lut(dcode+1)). With the pinned
    % D=56, F_in=4 this reproduces the design.md §3 table and is flat-0
    % at dcode>=56 (sub-1/2-LSB beyond), so saturating the INDEX to D-1 is
    % exact. Generator-side cross-check below pins the embedded HDL
    % constants to these values.
    scale = 2 ^ F_in;
    dcode = (0:D-1);
    f = log(1 + exp(-(dcode / scale)));         % real correction, LLR units
    lut = round(f * scale);                     % integer LSB codes (>= 0)

    % Cross-check the pinned anchors from design.md §3 (depth-56, F_in=4).
    if D == 56 && F_in == 4
        anchors = [ ...
            0,  11;  1, 11;  2, 10;  4, 9;  6, 8;  9, 7; 12, 6; ...
           15,  5; 18, 4; 23, 3; 31, 2; 55, 1];
        for r = 1:size(anchors, 1)
            di = anchors(r, 1); want = anchors(r, 2);
            got = lut(di + 1);
            if got ~= want
                error('fixedpoint_constituent_decoder_logmap:LUTMismatch', ...
                  'LUT[%d] = %d, design.md §3 pins %d', di, got, want);
            end
        end
        % Pin the flat-0 tail boundary: corr_code(55)=1, and the next
        % grid point would round to 0 (the depth is exhaustive).
        if lut(56) ~= 1
            error('fixedpoint_constituent_decoder_logmap:LUTTail', ...
                  'LUT[55] expected 1, got %d', lut(56));
        end
        if round(log(1 + exp(-(56 / scale))) * scale) ~= 0
            error('fixedpoint_constituent_decoder_logmap:LUTTail', ...
                  'correction at dcode=56 should round to 0 (flat-0 tail)');
        end
    end
end

function c = maxstar_fp(a, b, lut, lo, hi)
    % Fixed-point 2-way Jacobian max: max(a,b) + lut(sat(|a-b|)).
    % a, b are integer codes on the same F_in grid; the correction is
    % indexed by the saturated absolute difference (design.md §3 index
    % handling). The +corr is a saturating add into [lo,hi].
    m = max(a, b);
    d = abs(a - b);
    D = numel(lut);
    if d > D - 1
        d = D - 1;          % saturate the INDEX (exact: LUT flat-0 above)
    end
    corr = lut(d + 1);      % 1-indexed
    c = sat_add(m, corr, lo, hi);
end

function acc = maxstar_fold(v, lut, lo, hi)
    % Sequential LEFT FOLD of max* over the column vector v (ascending
    % order as supplied), seeded from v(1). Pins the non-associative
    % fold order (design.md §4). For an all-zero LUT this is exactly a
    % plain n-ary max (max is associative), giving the superset.
    acc = v(1);
    for i = 2:numel(v)
        acc = maxstar_fp(acc, v(i), lut, lo, hi);
    end
end

function y = sat_round(x, lo, hi)
    % Round to nearest integer (half away from zero) then saturate.
    r = sign(x) .* floor(abs(x) + 0.5);
    y = max(lo, min(hi, r));
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

function y = sat_sub(a, b, lo, hi)
    % Two-operand saturating signed subtract.
    s = a - b;
    if s > hi
        y = hi;
    elseif s < lo
        y = lo;
    else
        y = s;
    end
end
