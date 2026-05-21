function [x_e, x_e_q] = fixedpoint_constituent_decoder(x_a, z_a, params)
% FIXEDPOINT_CONSTITUENT_DECODER  Fixed-point Max-Log-MAP port of
% constituent_decoder.m for the LTE turbo constituent code (TS36.212
% §5.1.3.2). Authored to be the bit-exact oracle for the HDL core in
% openspec/changes/add-fpga-constituent-decoder — see that change's
% design.md (§3 per-step max-normalization, §4 Q-format first-cut table,
% §4a ±inf sentinel, §2 max-log-map => plain max).
%
%   x_e            = FIXEDPOINT_CONSTITUENT_DECODER(x_a, z_a) decodes a
%                    code block in scaled-real space using a fixed-point
%                    Max-Log-MAP Log-BCJR. x_a and z_a are real-valued
%                    a-priori LLRs (length K+3) that the function
%                    internally quantizes to the W_in/F_in Q-format. The
%                    returned x_e is in the same real LLR space
%                    (= integer code * 2^-F_in), length K+3.
%   [x_e, x_e_q]   = also returns the raw extrinsic integer codes in the
%                    W_xe-bit signed range — useful for golden-CSV
%                    generation later (task 2.1).
%   ... = FIXEDPOINT_CONSTITUENT_DECODER(x_a, z_a, params) overrides any
%                    field in the parameter struct (see DEFAULT_PARAMS).
%
% Bit-exactness contract (must match the HDL exactly):
%   - Max-Log-MAP: plain max (associative + exact in fixed-point, so
%     reduction order is irrelevant for the *value*, but op-order is
%     documented here so the HDL matches).
%   - Per-step max-normalization: after each alpha and each beta trellis
%     step, subtract m = max over the 8 states from the metric vector,
%     so the running max is pinned at 0. The constant cancels in
%     x_e = max(delta|x=0) - max(delta|x=1), so the extrinsic is
%     unaffected (see design.md §3).
%   - Signed Q-format, saturating: all alpha/beta/delta adds saturate
%     (never wrap). Inputs are quantized via round-to-nearest then
%     saturated to [-2^(W_in-1), 2^(W_in-1)-1].
%   - +/-inf sentinel: impossible alpha/beta states are initialised to
%     MIN_SENT = -2^(W_ab-1). Saturating add can only push it further
%     from 0, so max(MIN_SENT, real) == real always — it never
%     spuriously wins (design.md §4a). P3's filler +inf reuses
%     MAX_SENT = 2^(W_ab-1)-1 symmetrically.
%
% Operation order (the HDL must replicate exactly):
%   1. Quantize x_a, z_a to W_in via round-half-away-from-zero + saturate.
%   2. Build the 16-row branch metric vector gamma = gamma_x + gamma_z per
%      bit position k (gamma in W_gamma bits, no saturation needed since
%      |gamma| <= |x_a|+|z_a| <= 2*(2^(W_in-1)-1) < 2^W_in).
%   3. Forward recursion k=2..K+3:
%      for each next-state s (in fixed order 1..8) take the saturating
%      sum of the two predecessor alphas and their branch metrics,
%      compute the 2-way max — that is alpha(s, k) before normalization.
%      Then m = max over the 8 next-state alphas, and store
%      alpha(:,k) <- saturating_sub(alpha(:,k), m).
%   4. Backward recursion k=K+2..1 symmetrically with betas.
%   5. delta = sat_add(sat_add(alpha(from), beta(to)), gamma_z) per
%      transition (W_delta = W_ab+2 bits is enough since the sum of two
%      W_ab values + one W_in-value cannot exceed 2*(2^(W_ab-1))-1+
%      (2^(W_in-1)-1); a wider W_delta guards the edge case where
%      saturation hasn't kicked in yet).
%   6. x_e_q = sat_sub(max over the 8 transitions with input bit=0,
%                       max over the 8 transitions with input bit=1)
%      using the W_xe bit width (one bit wider than W_delta).
%
% Defaults are the design.md pinned widths (one F bump from the "first
% cut" table per task 1.2 — F=3 was insufficient for the outer equivalence
% band at low SNR; F=4 halves the quantization error):
%   W_in = 9, F_in = 4, W_gamma = 10, W_ab = 15, W_delta = 17, W_xe = 18.
%
% This routine is intentionally written to mirror the HDL's likely
% structure rather than to be Octave-idiomatic; clarity > vectorization.

    if nargin < 3
        params = struct();
    end
    p = default_params();
    fns = fieldnames(params);
    for ii = 1:numel(fns)
        p.(fns{ii}) = params.(fns{ii});
    end

    if length(x_a) ~= length(z_a)
        error('fixedpoint_constituent_decoder:LengthMismatch', ...
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
    % fixed (ascending transition index) so the HDL can do the same.
    into_state  = cell(STATES, 1);
    outof_state = cell(STATES, 1);
    for s = 1:STATES
        into_state{s}  = find(to_state   == s);
        outof_state{s} = find(from_state == s);
    end

    % --- Saturation bounds for each width. ---
    in_min   = -2^(p.W_in   - 1);   in_max   = 2^(p.W_in   - 1) - 1;
    ab_min   = -2^(p.W_ab   - 1);   ab_max   = 2^(p.W_ab   - 1) - 1;
    de_min   = -2^(p.W_delta- 1);   de_max   = 2^(p.W_delta- 1) - 1;
    xe_min   = -2^(p.W_xe   - 1);   xe_max   = 2^(p.W_xe   - 1) - 1;

    MIN_SENT = ab_min;              % +/-inf sentinel for alpha/beta init.

    % --- 1. Quantize inputs to Q(W_in - 1 - F_in).F_in (signed, saturating).
    lsb = 2^(-p.F_in);
    x_q = sat_round(x_a / lsb, in_min, in_max);
    z_q = sat_round(z_a / lsb, in_min, in_max);

    % --- 2. Branch metrics per bit position (integer LSB units).
    %     gamma(t, k) = -x_q(k) * x_bit(t) + -z_q(k) * z_bit(t)
    %     |gamma| <= |x_q| + |z_q| < 2^W_in, fits in W_gamma = W_in+1.
    % Stored as a TRANS x N matrix; no saturation needed.
    gammas_x = zeros(TRANS, N);
    gammas_x(x_bit == 1, :) = repmat(-x_q, sum(x_bit == 1), 1);

    gammas_z = zeros(TRANS, N);
    gammas_z(z_bit == 1, :) = repmat(-z_q, sum(z_bit == 1), 1);

    gammas = gammas_x + gammas_z;   % values in (-2^W_in, 2^W_in)

    % --- 3. Forward recursion. alphas in W_ab bits, normalized per step.
    alphas = zeros(STATES, N);
    alphas(2:end, 1) = MIN_SENT;    % start state is state 1; others = -inf
    for k = 2:N
        % Combine the two predecessor alphas per next-state, then 2-way max.
        new_alpha = zeros(STATES, 1);
        for s = 1:STATES
            t_idx = into_state{s};   % exactly 2 transition indices
            % Saturating add of W_ab + W_gamma (kept in W_ab via saturation).
            cand1 = sat_add(alphas(from_state(t_idx(1)), k-1), ...
                            gammas(t_idx(1), k-1), ab_min, ab_max);
            cand2 = sat_add(alphas(from_state(t_idx(2)), k-1), ...
                            gammas(t_idx(2), k-1), ab_min, ab_max);
            % 2-way max (exact in fixed point).
            new_alpha(s) = max(cand1, cand2);
        end
        % Per-step max-normalization: pin running max to 0.
        m = max(new_alpha);
        % Saturating subtraction (m is the max so new_alpha - m <= 0; the
        % only saturation concern is if MIN_SENT survives and m is large
        % positive — handled inside sat_sub).
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
            t_idx = outof_state{s};  % exactly 2 transition indices
            cand1 = sat_add(betas(to_state(t_idx(1)), k+1), ...
                            gammas(t_idx(1), k+1), ab_min, ab_max);
            cand2 = sat_add(betas(to_state(t_idx(2)), k+1), ...
                            gammas(t_idx(2), k+1), ab_min, ab_max);
            new_beta(s) = max(cand1, cand2);
        end
        m = max(new_beta);
        for s = 1:STATES
            betas(s, k) = sat_sub(new_beta(s), m, ab_min, ab_max);
        end
    end

    % --- 5. Per-transition delta and 6. extrinsic.
    %     delta(t,k) = alpha(from(t), k) + beta(to(t), k) + gamma_z(t, k)
    %     The HDL must do this as two saturating adds in a fixed order.
    x_e_q = zeros(1, N);
    for k = 1:N
        deltas_k = zeros(TRANS, 1);
        for t = 1:TRANS
            ab_sum = sat_add(alphas(from_state(t), k), ...
                             betas (to_state  (t), k), ...
                             de_min, de_max);
            deltas_k(t) = sat_add(ab_sum, gammas_z(t, k), de_min, de_max);
        end

        % 8-way max over the x=0 transitions and over the x=1 transitions.
        % max is exact + associative in fixed-point => any reduction tree;
        % the HDL/reference share the same set membership, which is the
        % only thing that matters.
        log_p0 = max(deltas_k(x_bit == 0));
        log_p1 = max(deltas_k(x_bit == 1));

        x_e_q(k) = sat_sub(log_p0, log_p1, xe_min, xe_max);
    end

    % --- Scale back to real LLR space (= integer code * 2^-F_in).
    x_e = double(x_e_q) * lsb;
end

% --------------------------------------------------------------------- %
% Helpers — kept local so the file is fully self-contained for review.   %
% --------------------------------------------------------------------- %

function p = default_params()
    % Pinned widths per design.md §4 (post-task-1.2). The first-cut table
    % used F=3 which left the low-SNR cell of the equivalence band on the
    % wrong side of "tight". Bumping F to 4 (and W_in to 9 to preserve
    % range) cut max|err| roughly in half across the grid and pushed all
    % cells inside the band. W_ab/W_delta/W_xe grow symmetrically by 1 to
    % keep the design table's headroom rule consistent (still generous;
    % M3 tightens later).
    p = struct( ...
        'W_in',   9, ...    % signed Q(4).(4) input LLRs
        'F_in',   4, ...    %   => LSB = 2^-4 = 0.0625, range ~[-16, +16)
        'W_gamma',10, ...   % |gamma| <= |x_a| + |z_a| <= 2^W_in
        'W_ab',   15, ...   % post-norm alpha/beta width
        'W_delta',17, ...   % alpha + beta + gamma_z (two saturating adds)
        'W_xe',   18);      % max(delta|x=0) - max(delta|x=1)
end

function y = sat_round(x, lo, hi)
    % Round to nearest integer (half away from zero) then saturate.
    r = sign(x) .* floor(abs(x) + 0.5);
    y = max(lo, min(hi, r));
end

function y = sat_add(a, b, lo, hi)
    % Two-operand saturating signed add. Operates on scalars (the HDL
    % will likewise do scalar saturating adds in a tree).
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
