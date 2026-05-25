function [x_e, x_e_q] = fixedpoint_constituent_decoder_sw(x_a, z_a, params, window_len, acq_len)
% FIXEDPOINT_CONSTITUENT_DECODER_SW  Sliding-window fixed-point Max-Log-MAP
% port of the LTE turbo constituent code (TS36.212 §5.1.3.2). This is the
% M2 bit-exact oracle for the windowed constituent_decoder HDL core in
% openspec/changes/add-fpga-decoder-sliding-window — see that change's
% design.md (§1 windowing scheme, §2 memory, §3 W/L pin, §5 fixed-point
% inheritance, §6 WINDOW_LEN-superset, §7 verification).
%
%   x_e = FIXEDPOINT_CONSTITUENT_DECODER_SW(x_a, z_a) decodes a code block
%         using the SLIDING-WINDOW BCJR with the pinned defaults
%         (window_len = 64, acq_len = 32). x_a / z_a are real-valued
%         a-priori LLRs (length K+3); x_e is the real-LLR extrinsic
%         (= integer code * 2^-F_in), length K+3.
%   [x_e, x_e_q] = ... also returns the raw W_xe-bit signed integer codes
%         for golden-CSV generation (task 2.1).
%   ... = FIXEDPOINT_CONSTITUENT_DECODER_SW(x_a, z_a, params) overrides any
%         field of the parameter struct (see DEFAULT_PARAMS) — the pinned
%         fixed-point widths, INHERITED UNCHANGED from P1.
%   ... = FIXEDPOINT_CONSTITUENT_DECODER_SW(x_a, z_a, params, window_len)
%   ... = FIXEDPOINT_CONSTITUENT_DECODER_SW(x_a, z_a, params, window_len, acq_len)
%         override the window length W and acquisition length L.
%
% ---------------------------------------------------------------------------
% Relationship to the full-block reference (fixedpoint_constituent_decoder.m):
%   The γ / α / β arithmetic — every saturating add/sub, the per-step
%   max-normalization, the ±inf sentinel, the pinned Q-format widths, the
%   delta/extrinsic reduction — is INHERITED VERBATIM from P1 (the local
%   helper functions and trellis below are byte-identical to that file).
%   ONLY the α STORAGE SCHEDULE and the β INITIALIZATION change:
%
%   * α (forward) — its *values* are identical to full-block (the forward
%     recursion always starts from the true initial state and runs
%     left-to-right with no acquisition). To model the HDL's bounded α RAM,
%     α is NOT retained for all K+3 columns; instead the 8-state α column at
%     every window boundary is checkpointed, and each window's α columns are
%     RECOMPUTED from the nearest left checkpoint when that window's β is
%     swept. Recompute reproduces identical α values (same recursion, same
%     start), so this is bit-exact — it is purely a memory-schedule choice.
%
%   * β (backward) — computed PER WINDOW. The trellis [1..N] is cut into
%     ⌈N/W⌉ contiguous windows. For a window covering columns [w0..w1]:
%       - TERMINAL window (w1 == N): β is initialised at column N to the
%         TRUE TERMINATED-STATE init (state 1 = 0, others = MIN_SENT) and
%         recursed back over [w0..N]. Identical to full-block at the end.
%       - INTERIOR window (w1 < N): β is initialised FLAT (all-equal, i.e.
%         0 after max-norm — the "unknown state" prior, distinct from the
%         MIN_SENT terminal init) at the acquisition column
%         acq = min(N, w1 + L), then recursed BACKWARD across the L
%         acquisition steps acq-1 … w1 (warm-up, NOT emitted), after which
%         the in-window β over [w0..w1] is the emit region.
%     The finite-L acquisition is the ONLY source of difference from
%     full-block (the windowing loss); it shrinks monotonically with L and
%     is bit-exact at L = 48 (design.md §3).
%
% ---------------------------------------------------------------------------
% SUPERSET PROPERTY (design.md §6 — asserted in the characterization):
%   window_len >= K+3 collapses the schedule to a SINGLE window whose
%   w1 == N (the terminal window), with no acquisition and the true
%   terminated-state β init. In that mode every γ/α/β/δ/extrinsic operation
%   is performed in the same order on the same values as
%   fixedpoint_constituent_decoder.m, so the windowed reference reproduces
%   the full-block reference BYTE-FOR-BYTE (x_e_q identical). This is the
%   strict-superset cross-check.
%
% Fixed-point format (INHERITED UNCHANGED from P1 — do NOT re-derive):
%   W_in=9 (Q4.4, F_in=4, LSB=2^-4), W_gamma=10, W_ab=15, W_delta=17,
%   W_xe=18; per-step max-norm; saturating adds/subs; ±inf sentinel
%   MIN_SENT = -2^(W_ab-1).
%
% Pinned windowing defaults (design.md §3): window_len = 64, acq_len = 32.
%   acq_len = 48 is the bit-exact-to-full-block escape hatch.
%
% This routine is intentionally written to mirror the HDL's likely structure
% (explicit per-window recompute, flat acquisition init, fixed op order)
% rather than to be Octave-idiomatic; clarity and bit-exactness > vectorization.

    if nargin < 3 || isempty(params)
        params = struct();
    end
    p = default_params();
    fns = fieldnames(params);
    for ii = 1:numel(fns)
        p.(fns{ii}) = params.(fns{ii});
    end

    if length(x_a) ~= length(z_a)
        error('fixedpoint_constituent_decoder_sw:LengthMismatch', ...
              'LLR sequences must have the same length');
    end
    if size(x_a, 1) ~= 1 || size(z_a, 1) ~= 1
        x_a = x_a(:).';
        z_a = z_a(:).';
    end

    N = length(x_a);        % = K + 3 termination symbols included
    STATES = 8;             % memory-3 trellis
    TRANS = 16;             % 2 transitions per from-state

    % --- Windowing parameters (pinned defaults; design.md §3). ---
    if nargin < 4 || isempty(window_len)
        window_len = 64;    % W
    end
    if nargin < 5 || isempty(acq_len)
        acq_len = 32;       % L
    end
    if window_len < 1
        error('fixedpoint_constituent_decoder_sw:BadWindow', ...
              'window_len must be >= 1');
    end
    if acq_len < 0
        error('fixedpoint_constituent_decoder_sw:BadAcq', ...
              'acq_len must be >= 0');
    end

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

    % --- 1. Quantize inputs to Q(W_in-1-F_in).F_in (signed, saturating). ---
    lsb = 2^(-p.F_in);
    x_q = sat_round(x_a / lsb, in_min, in_max);
    z_q = sat_round(z_a / lsb, in_min, in_max);

    % --- 2. Branch metrics per bit position (integer LSB units). ---
    gammas_x = zeros(TRANS, N);
    gammas_x(x_bit == 1, :) = repmat(-x_q, sum(x_bit == 1), 1);

    gammas_z = zeros(TRANS, N);
    gammas_z(z_bit == 1, :) = repmat(-z_q, sum(z_bit == 1), 1);

    gammas = gammas_x + gammas_z;   % values in (-2^W_in, 2^W_in)

    % --- Window boundaries. ---
    % Windows are contiguous, in-order, length W (the last may be shorter):
    %   window j covers columns [w0(j) .. w1(j)], j = 1..n_win.
    n_win = ceil(N / window_len);
    w0 = zeros(1, n_win);
    w1 = zeros(1, n_win);
    for j = 1:n_win
        w0(j) = (j - 1) * window_len + 1;
        w1(j) = min(j * window_len, N);
    end

    % --- 3. Forward α with window-boundary CHECKPOINTS. ---
    % α values are identical to full-block; we retain only the 8-state
    % column at the *start* of each window (the recompute seed) plus the
    % column at N is implicit. To keep the reference exact AND model the
    % per-window recompute, we store a checkpoint = the α column at
    % (w0(j) - 1) for each window j (the column just left of the window).
    % chk(:, j) is the seed from which window j's α columns are recomputed.
    %   - For j = 1 the seed is the true initial α column (k = 1).
    %   - For j > 1 the seed is column w0(j) - 1 = w1(j-1).
    alphas_init = zeros(STATES, 1);
    alphas_init(2:end) = MIN_SENT;  % start state is state 1; others = -inf

    chk = zeros(STATES, n_win);     % checkpoint seed for each window
    % Forward pass purely to populate the boundary checkpoints. This mirrors
    % the HDL's single forward sweep that lays down checkpoints; the actual
    % α columns used by β are RECOMPUTED per window below.
    a_prev = alphas_init;
    chk(:, 1) = a_prev;             % seed for window 1 is the initial column
    next_boundary = 1;              % index into w0 of the next checkpoint
    for k = 2:N
        a_prev = alpha_step(a_prev, gammas(:, k-1), into_state, ...
                            from_state, STATES, ab_min, ab_max, MIN_SENT);
        % If k is the seed column for a later window (k == w0(j)-1), store it.
        % w0(j)-1 == w1(j-1); so checkpoint at every window end except the last.
        for j = 2:n_win
            if k == w0(j) - 1
                chk(:, j) = a_prev;
            end
        end
    end

    % --- 4/5/6. Per-window β (with acquisition) + δ + extrinsic. ---
    x_e_q = zeros(1, N);
    for j = 1:n_win
        wl = w0(j);
        wr = w1(j);

        % (4a) Recompute this window's α columns [wl..wr] from the checkpoint
        %      seed chk(:, j) (which is the α column at wl-1, or the initial
        %      column for j = 1). a_win(:, i) is the α column at (wl-1+i).
        nwc = wr - wl + 1;
        a_win = zeros(STATES, nwc);
        if j == 1
            % chk(:,1) is the column at k = 1 (the initial column itself).
            a_win(:, 1) = chk(:, 1);
            for i = 2:nwc
                kcol = wl - 1 + i;          % absolute column index
                a_win(:, i) = alpha_step(a_win(:, i-1), gammas(:, kcol-1), ...
                    into_state, from_state, STATES, ab_min, ab_max, MIN_SENT);
            end
        else
            % chk(:,j) is the α column at wl-1; step forward into the window.
            a_col = chk(:, j);
            for i = 1:nwc
                kcol = wl - 1 + i;          % absolute column index
                a_col = alpha_step(a_col, gammas(:, kcol-1), ...
                    into_state, from_state, STATES, ab_min, ab_max, MIN_SENT);
                a_win(:, i) = a_col;
            end
        end

        % (4b) β for this window. Determine the β init column and seed:
        %   - If wr+L reaches the block end (acq column >= N), the TRUE block
        %     end is visible, so initialise at N with the TERMINATED-STATE init
        %     (state 1 = 0, others = MIN_SENT) and recurse back — no flat
        %     acquisition error (this subsumes the terminal window wr == N and
        %     any near-terminal window whose acquisition span reaches N).
        %   - Otherwise (interior, acq column < N) initialise FLAT (all-equal,
        %     "unknown state") at acq = wr+L and recurse the L acquisition
        %     steps back to wr (warm-up, NOT emitted).
        acq_start = wr + acq_len;
        b_col = zeros(STATES, 1);
        if acq_start >= N
            acq_start = N;                  % clamp to block end
            b_col(2:end) = MIN_SENT;        % TRUE terminated-state init at N
        else
            % flat init (all-equal => 0 after max-norm) at column acq_start
        end
        % Acquisition warm-up: recurse from acq_start-1 down to wr, producing
        % the β column AT wr (the rightmost emitted column).
        for k = acq_start - 1 : -1 : wr
            b_col = beta_step(b_col, gammas(:, k+1), outof_state, ...
                to_state, STATES, ab_min, ab_max, MIN_SENT);
        end

        % b_col is now the β column at wr. Emit columns wr, wr-1, ..., wl;
        % b_win(:, i) is the β column at (wl-1+i).
        b_win = zeros(STATES, nwc);
        b_win(:, nwc) = b_col;              % column wr
        for i = nwc-1 : -1 : 1
            kcol = wl - 1 + i;              % absolute column index of b_win(:,i)
            b_win(:, i) = beta_step(b_win(:, i+1), gammas(:, kcol+1), ...
                outof_state, to_state, STATES, ab_min, ab_max, MIN_SENT);
        end

        % (5/6) δ + extrinsic for every column in [wl..wr].
        for i = 1:nwc
            kcol = wl - 1 + i;
            a_k = a_win(:, i);
            b_k = b_win(:, i);
            deltas_k = zeros(TRANS, 1);
            for t = 1:TRANS
                ab_sum = sat_add(a_k(from_state(t)), ...
                                 b_k(to_state(t)), de_min, de_max);
                deltas_k(t) = sat_add(ab_sum, gammas_z(t, kcol), de_min, de_max);
            end
            log_p0 = max(deltas_k(x_bit == 0));
            log_p1 = max(deltas_k(x_bit == 1));
            x_e_q(kcol) = sat_sub(log_p0, log_p1, xe_min, xe_max);
        end
    end

    % --- Scale back to real LLR space (= integer code * 2^-F_in). ---
    x_e = double(x_e_q) * lsb;
end

% --------------------------------------------------------------------- %
% Helpers — INHERITED VERBATIM from fixedpoint_constituent_decoder.m so   %
% the arithmetic is byte-identical. alpha_step / beta_step factor the     %
% single-column recursion out (same ops/order) so the per-window recompute %
% and the full-block path share one code path.                           %
% --------------------------------------------------------------------- %

function a_new = alpha_step(a_prev, gamma_col, into_state, from_state, ...
                            STATES, ab_min, ab_max, MIN_SENT) %#ok<INUSD>
    % One forward α trellis step (column k-1 -> column k). Exactly the body
    % of the full-block reference's forward loop: per next-state 2-way max of
    % saturating predecessor sums, then per-step max-normalization.
    new_alpha = zeros(STATES, 1);
    for s = 1:STATES
        t_idx = into_state{s};   % exactly 2 transition indices
        cand1 = sat_add(a_prev(from_state(t_idx(1))), ...
                        gamma_col(t_idx(1)), ab_min, ab_max);
        cand2 = sat_add(a_prev(from_state(t_idx(2))), ...
                        gamma_col(t_idx(2)), ab_min, ab_max);
        new_alpha(s) = max(cand1, cand2);
    end
    m = max(new_alpha);
    a_new = zeros(STATES, 1);
    for s = 1:STATES
        a_new(s) = sat_sub(new_alpha(s), m, ab_min, ab_max);
    end
end

function b_new = beta_step(b_next, gamma_col, outof_state, to_state, ...
                           STATES, ab_min, ab_max, MIN_SENT) %#ok<INUSD>
    % One backward β trellis step (column k+1 -> column k). Exactly the body
    % of the full-block reference's backward loop.
    new_beta = zeros(STATES, 1);
    for s = 1:STATES
        t_idx = outof_state{s};  % exactly 2 transition indices
        cand1 = sat_add(b_next(to_state(t_idx(1))), ...
                        gamma_col(t_idx(1)), ab_min, ab_max);
        cand2 = sat_add(b_next(to_state(t_idx(2))), ...
                        gamma_col(t_idx(2)), ab_min, ab_max);
        new_beta(s) = max(cand1, cand2);
    end
    m = max(new_beta);
    b_new = zeros(STATES, 1);
    for s = 1:STATES
        b_new(s) = sat_sub(new_beta(s), m, ab_min, ab_max);
    end
end

function p = default_params()
    % Pinned widths per design.md §5 — INHERITED UNCHANGED from P1
    % (scripts/fixedpoint_constituent_decoder.m). Windowing changes only the
    % α/β schedule, never these widths.
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
    % Two-operand saturating signed add.
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
