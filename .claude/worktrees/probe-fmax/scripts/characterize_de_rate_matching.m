% CHARACTERIZE_DE_RATE_MATCHING  Inner fixed-vs-float EQUIVALENCE check
% (P4 task 1.3) for the fixed-point de-rate-match reference
% (scripts/fixedpoint_de_rate_matching.m) against the INLINE float
% de-rate-match in turbo_decoding_chain.m (lines 86-93), on IDENTICAL
% quantized channel-LLR frames.
%
% UNLIKE the outer end-to-end BER harness (characterize_rx_chain.m, P4 task
% 5.2), this is a de-rate-match-ALONE numerical equivalence gate — the
% deterministic soft inverse permute + saturating soft-combine, NOT BER. The
% permutation/accumulate is integer-exact (it reuses the SAME
% rate_matching.m permutation the TX gather used), so the recovered d_a must
% match the float d position-for-position: finite values agree exactly modulo
% the W_LLR/W_DRM/W_EXT quantization, filler (+inf) and erasure (0) land at
% the same positions, and signs agree.
%
% The float oracle is REPLICATED here (the lines-86-93 scatter-accumulate +
% reshape + filler-NaN), NOT by calling turbo_decoding_chain (which is left
% UNMODIFIED). The two paths see the SAME quantized LLR vector e_q so the only
% difference is the fixed-point saturating arithmetic.
%
% Grid (bounded, representative — a few cases exercising every behaviour):
%   - a baseline E ~ N_cb no-wrap case,
%   - an E > N_cb WRAP case (a w-position genuinely accumulates >= 2 LLRs —
%     soft-combine),
%   - an E < N_cb ERASURE case (untransmitted w-positions -> 0),
%   - a FILLER case (F_r > 0; first F_r systematic + upper-parity -> +inf),
%   - an rv_idx ~= 0 case (different k_0).
%
% For each case: random block -> turbo_encoder -> rate_matching (TX) ->
% BPSK + AWGN -> channel LLRs -> quantize to W_LLR -> run BOTH the inline
% float de-rate-match and the fixed-point reference on the identical e_q ->
% report soft-d_a agreement: max-abs / RMS LLR error over finite positions,
% sign-agreement %, and filler/erasure-position agreement.
%
% Pass/fail band (PINNED below, the P1-style >=1.5x discipline): the
% fixed-point error is purely the W_LLR input quantize + the (non-wrapping)
% W_DRM/W_EXT saturate, so finite-position max|err| is bounded by one W_EXT
% LSB times the max number of LLRs combined onto a position. The band is set
% generously above that; sign agreement must be 100% and filler/erasure
% positions must match exactly (those are integer-exact, not quantization).
%
% Outputs: a per-case agreement table + an overall pass/fail. Optionally
% writes results/characterize_de_rate_matching.txt (no-op if results/ absent).

1;  % Mark as a script (not a function file). NOTE: Octave only resolves
    % script-local functions DEFINED BEFORE they are called in the script
    % body, so the helpers are defined here (top), not at the bottom.

function y = sat_round_local(x, lo, hi)
    r = sign(x) .* floor(abs(x) + 0.5);
    y = max(lo, min(hi, r));
end

function s = sign_band(v, eps)
    % Sign with a dead-band: values with |v| < eps map to 0 (so a +0/-0
    % rounding split is not a spurious sign mismatch).
    s = sign(v);
    s(abs(v) < eps) = 0;
end

function str = tf(b)
    if b
        str = 'yes';
    else
        str = 'NO';
    end
end

repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_root);
addpath(fullfile(repo_root, 'scripts'));
% The chain classdefs declare `< matlab.System`; under GNU Octave that base
% class is provided by the octave_shims/ shim (added to the path here, exactly
% as the HDL/Octave runners do). MATLAB users have the built-in and ignore it.
if exist(fullfile(repo_root, 'octave_shims'), 'dir')
    addpath(fullfile(repo_root, 'octave_shims'));
end

% --- Fixed-point pins (mirror fixedpoint_de_rate_matching default_params). ---
W_LLR = 8;   F_in = 4;   W_DRM = 16;   W_EXT = 12;
lsb     = 2^(-F_in);
llr_min = -2^(W_LLR - 1);   llr_max = 2^(W_LLR - 1) - 1;
ext_lsb = lsb;                              % one W_EXT LSB (output grid step)

% --- Pinned acceptance band. ---
% Finite-position max|err| is the input-quantize error (<= 0.5 LSB per LLR)
% combined over up to a few wrap visits, plus the W_EXT output saturate. With
% the moderate SNR / W_LLR=8 grid below, LLRs stay well inside the W_EXT
% range, so the only error is the W_LLR input rounding (<= 0.5*lsb per LLR)
% accumulated over the visits to a position. We pin the band at a few LSBs —
% generous, P1-style. Sign agreement and filler/erasure positions are
% integer-exact (must be perfect).
band_maxabs_llr   = 4 * lsb;    % <= 4 W_EXT LSBs of finite-position error
band_sign_agree   = 100.0;      % signs must agree exactly (%)

% Reproducibility.
rand('state',  20260524);
randn('state', 20260524);

% --- Bounded case grid. Columns: A (info-block length => B=A+24, segmented
%     to a single C=1 block of length K_r >= B with F_r = sum(K_r)-B_prime
%     filler bits), G (=> E via the 3GPP encoded-segment-length math),
%     rv_idx, SNR_dB, label. N_IR=inf (I_LBRM=0) so N_cb = K_w = 3*K_Pi; E vs
%     N_cb selects wrap / no-wrap / erasure (the actual per-position visit
%     count is measured exactly below). A is chosen so each row exercises a
%     distinct behaviour (the filler row uses A=20 -> K_r=48, F_r=4). ---
cases = { ...
  % A     G       rv  SNR   label
    16,   132,    0,   1.0, 'baseline  (E~N_cb, no wrap)'; ...
    16,   400,    0,   1.0, 'wrap      (E>N_cb -> soft-combine)'; ...
    16,    72,    0,   1.0, 'erasure   (E<N_cb -> 0 positions)'; ...
    20,   400,    0,   1.0, 'filler    (F_r>0 -> +inf rows 1:2)'; ...
    16,   200,    2,   1.0, 'rv_idx=2  (different k_0)' ...
};
n_cases = size(cases, 1);

rows = {};
rows{end+1} = sprintf('%-34s %-5s %-6s %-6s %-7s %-9s %-9s %-9s %-8s %-7s', ...
    'case', 'K', 'E', 'N_cb', 'maxhit', 'maxabsLLR', 'rmsLLR', 'sign%', ...
    'fillOK', 'erasOK');

worst_maxabs = 0;
worst_sign   = 100;
all_fill_ok  = true;
all_eras_ok  = true;
overall_pass = true;

for ci = 1:n_cases
    A      = cases{ci, 1};
    G      = cases{ci, 2};
    rv_idx = cases{ci, 3};
    snr_db = cases{ci, 4};
    label  = cases{ci, 5};

    % --- Build a single-block coding chain to source the EXACT TX params
    %     (E, F_r, N_ref, I_LBRM, rv_idx, the internal interleaver, and the
    %     rate_matching_patterns the float de-rate-match uses). ---
    enc = turbo_encoding_chain('A', A, 'G', G, 'rv_idx', rv_idx);
    step(enc, zeros(1, A));              % first step runs setupImpl, which
                                         % populates the hidden patterns/params

    if enc.C ~= 1
        error('characterize_de_rate_matching:multiblock', ...
              'case %d gave C=%d (need C=1; pick A so B<=6144)', ci, enc.C);
    end

    K_r   = enc.K_r(1);
    F_r   = enc.F_r(1);
    D_r   = enc.D_r(1);
    E     = enc.E_r(1);
    N_ref = enc.N_ref;
    I_LBRM= enc.I_LBRM;
    pii_rm = enc.rate_matching_patterns{1};   % length-E permutation (0-based)
    pii_il = enc.internal_interleaver_patterns{1};

    % N_cb for the diagnostic (I_LBRM=0 => N_cb = K_w = 3*K_Pi). K_Pi is the
    % subblock-interleaver row-padded length; recover it from the pattern span.
    K_w = 3 * D_r;                       % mother-code grid (upper bound on N_cb)
    % (We only print N_cb as a no-wrap/wrap sanity column; the actual wrap is
    % detected exactly by the max hit count below.)
    N_cb_diag = K_w;

    % --- Random block -> turbo encode -> TX rate-match -> BPSK+AWGN -> LLR. ---
    c = double(rand(1, K_r) < 0.5);
    c(1:F_r) = 0;                        % filler bits are 0 by convention
    d = turbo_encoder(c, pii_il);        % 3x(K_r+4); filler rows 1:2 are NaN
    d_vec = reshape(d, 1, numel(d));
    e_tx  = d_vec(pii_rm + 1);           % TX gather (the rate_matching read)

    % e_tx may contain NaN at filler positions that were selected; the TX
    % chain maps filler bits to a known value before the channel. The float
    % oracle's e is the RECEIVED LLR, so model the transmitted bit: filler
    % (NaN) -> bit 0 (the convention), parity NaN cannot occur for row 3.
    tx_bits = e_tx;
    tx_bits(isnan(tx_bits)) = 0;         % filler -> 0 bit (known)

    sigma2 = 10 ^ (-snr_db / 10);        % Es=1 BPSK => sigma^2 = 10^(-SNR/10)
    sigma  = sqrt(sigma2);
    y      = (1 - 2 * tx_bits) + sigma * randn(1, E);   % BPSK + AWGN
    e_llr  = 2 * y / sigma2;             % channel LLRs (length E)

    % --- Quantize the channel LLRs to the W_LLR grid ONCE; BOTH paths use the
    %     SAME quantized vector (the only difference is the fixed-point
    %     saturating arithmetic downstream). ---
    e_q_codes = sat_round_local(e_llr / lsb, llr_min, llr_max);
    e_q       = double(e_q_codes) * lsb; % real-space quantized LLRs

    % ============== FLOAT oracle: turbo_decoding_chain.m lines 86-93 ========
    % (replicated here on e_q; turbo_decoding_chain itself is UNMODIFIED.)
    d_vec_f = zeros(1, 3 * D_r);
    for k = 0:length(pii_rm) - 1
        d_vec_f(pii_rm(k+1) + 1) = d_vec_f(pii_rm(k+1) + 1) + e_q(k+1);
    end
    d_float = reshape(d_vec_f, 3, D_r);
    d_float(1:2, 1:F_r) = NaN;           % filler -> NaN (decoder maps to +inf)

    % ============== FIXED-POINT reference ====================================
    d_fp = fixedpoint_de_rate_matching(e_q, K_r, F_r, N_ref, I_LBRM, rv_idx, E);

    % --- Max hit count (how many LLRs were soft-combined onto the busiest
    %     w-position) — proves the wrap case genuinely accumulates >= 2. ---
    hit = zeros(1, 3 * D_r);
    for k = 0:length(pii_rm) - 1
        hit(pii_rm(k+1) + 1) = hit(pii_rm(k+1) + 1) + 1;
    end
    max_hit = max(hit);

    % --- Compare. Classify each (row,col) position. ---
    fin_f = isfinite(d_float);           % finite float positions
    fill_f = isnan(d_float);             % float filler (NaN)
    fill_p = isinf(d_fp) & (d_fp > 0);   % fp filler (+inf)

    % Filler positions must coincide exactly (integer-exact, not quantization).
    fill_ok = isequal(fill_f, fill_p);

    % Erasure check: positions that received NO LLR are 0 in both (and finite).
    % Build the erasure mask from the hit count, reshaped to 3xD_r.
    hit_mat   = reshape(hit, 3, D_r);
    eras_mask = (hit_mat == 0);
    eras_mask(1:2, 1:F_r) = false;       % filler rows are not "erasure" here
    eras_f_zero = all(d_float(eras_mask) == 0);
    eras_p_zero = all(d_fp(eras_mask)    == 0);
    eras_ok = eras_f_zero && eras_p_zero;

    % Finite-position numeric error (exclude filler).
    cmp_mask = fin_f & ~fill_p;          % finite in float and not fp-filler
    ef = d_float(cmp_mask);
    ep = d_fp(cmp_mask);
    err = ep - ef;
    if isempty(err)
        max_abs = 0; rms = 0;
    else
        max_abs = max(abs(err));
        rms     = sqrt(mean(err .^ 2));
    end

    % Sign agreement over finite positions (treat |v| < 0.5 LSB as the same
    % "zero" sign so a +0/-0 rounding split is not a spurious mismatch).
    sgn_f = sign_band(ef, 0.5 * lsb);
    sgn_p = sign_band(ep, 0.5 * lsb);
    n_sign = numel(sgn_f);
    if n_sign == 0
        sign_pct = 100;
    else
        sign_pct = 100 * sum(sgn_f == sgn_p) / n_sign;
    end

    worst_maxabs = max(worst_maxabs, max_abs);
    worst_sign   = min(worst_sign, sign_pct);
    all_fill_ok  = all_fill_ok && fill_ok;
    all_eras_ok  = all_eras_ok && eras_ok;

    case_pass = (max_abs <= band_maxabs_llr) && (sign_pct >= band_sign_agree) ...
                && fill_ok && eras_ok;
    overall_pass = overall_pass && case_pass;

    rows{end+1} = sprintf('%-34s %-5d %-6d %-6d %-7d %-9.4f %-9.4f %-9.3f %-8s %-7s', ...
        label, K_r, E, N_cb_diag, max_hit, max_abs, rms, sign_pct, ...
        tf(fill_ok), tf(eras_ok));
end

% --- Print + persist. ---
header = sprintf('\n%s\n%s\n', ...
    'characterize_de_rate_matching — inner fixed-vs-float EQUIVALENCE (P4; de-rate-match alone)', ...
    repmat('-', 1, 96));
header = [header, sprintf('W_LLR=%d (Q3.4)  W_DRM=%d (Q11.4)  W_EXT=%d (Q7.4)  F_in=%d  lsb=%.4f\n\n', ...
    W_LLR, W_DRM, W_EXT, F_in, lsb)];

footer = sprintf('\nPinned band: finite-position max|err| <= %.4f LLR (%g W_EXT LSBs); sign agreement = %.1f%%;\n', ...
    band_maxabs_llr, band_maxabs_llr / ext_lsb, band_sign_agree);
footer = [footer, sprintf('             filler (+inf) and erasure (0) positions integer-exact (must match).\n')];
footer = [footer, sprintf('Worst observed: max|err| = %.4f LLR, min sign agreement = %.3f%%, fillerOK(all)=%s, erasureOK(all)=%s\n', ...
    worst_maxabs, worst_sign, tf(all_fill_ok), tf(all_eras_ok))];
if overall_pass
    footer = [footer, sprintf('OVERALL: PASS (within band)\n')];
else
    footer = [footer, sprintf('OVERALL: FAIL (band violated — see table above)\n')];
end

fprintf('%s', header);
for ii = 1:numel(rows)
    fprintf('%s\n', rows{ii});
end
fprintf('%s', footer);

results_dir = fullfile(repo_root, 'results');
if exist(results_dir, 'dir')
    out_path = fullfile(results_dir, 'characterize_de_rate_matching.txt');
    fid = fopen(out_path, 'w');
    if fid >= 0
        fprintf(fid, '%s', header);
        for ii = 1:numel(rows)
            fprintf(fid, '%s\n', rows{ii});
        end
        fprintf(fid, '%s', footer);
        fclose(fid);
        fprintf('\nWrote %s\n', out_path);
    end
end

if ~overall_pass
    error('characterize_de_rate_matching:BandViolated', ...
          'fixed-vs-float equivalence band not met — see table above.');
end

% (Helper functions sat_round_local / sign_band / tf are defined near the top
%  of this script, before the body that calls them — required by Octave's
%  script-local function scoping.)
