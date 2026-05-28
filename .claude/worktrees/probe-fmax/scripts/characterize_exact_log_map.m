% CHARACTERIZE_EXACT_LOG_MAP  Outer BER-vs-SNR check (M1 task 1.3):
% quantify the dB recovered by fixed-point EXACT Log-MAP over fixed-point
% Max-Log-MAP, with float exact Log-MAP as the upper bound. Over a bounded
% {K, SNR} grid, the SAME AWGN frames are decoded three ways:
%
%   (a) fixed-point Max-Log-MAP  : scripts/fixedpoint_turbo_decoder.m
%                                  (the merged P2 reference, UNMODIFIED).
%   (b) fixed-point exact Log-MAP: the SAME loop algebra with the inner
%                                  constituent core swapped to
%                                  scripts/fixedpoint_constituent_decoder_logmap.m
%                                  (EXACT_LOGMAP=true). The loop wrapper is
%                                  kept LOCAL to this script
%                                  (logmap_turbo_loop below) so neither
%                                  merged reference is modified.
%   (c) float exact Log-MAP      : turbo_decoder.m with global
%                                  approx_star=false (the algorithmic
%                                  upper bound).
%
% Gate / deliverable (design.md §7 outer BER):
%   - fixed-point exact (b) sits AT or ABOVE fixed-point Max-Log-MAP (a):
%     i.e. (b)'s BER curve is at or left of (a)'s — a real (if small) dB
%     GAIN at the shallow target BER. Quantify the dB recovered.
%   - (b) sits WITHIN a documented margin of float exact (c).
%   - Sanity tie-back: (b) with EXACT_LOGMAP forced false reproduces (a)
%     exactly (the superset; checked separately by
%     scripts/selftest_logmap_reference.m). Here we report the curves.
%
% Bounded by design (Octave tractability): few K, a handful of SNR points,
% modest frames, shallow target BER (~1e-2..1e-3) — a trend/margin check,
% not a deep waterfall.

1;  % script (not a function file); helpers below, defined before use.

function s = crossing_snr(snr, ber, target)
    % SNR (linear-interpolated in log10(BER) vs SNR) where BER crosses
    % `target`. Returns NaN if `target` is not bracketed by the grid.
    s = NaN;
    lb = log10(max(ber, 1e-12));
    lt = log10(target);
    for i = 1:numel(snr)-1
        a = lb(i); b = lb(i+1);
        if (a >= lt && b <= lt) || (a <= lt && b >= lt)
            if a == b
                s = snr(i);
            else
                frac = (lt - a) / (b - a);
                s = snr(i) + frac * (snr(i+1) - snr(i));
            end
            return;
        end
    end
end

function str = fmt_snr(v)
    if isnan(v)
        str = '--';
    else
        str = sprintf('%.3f', v);
    end
end

function c = logmap_turbo_loop(d_a, pii, max_iterations, exact)
    % LOCAL fixed-point iterative turbo loop, identical to
    % scripts/fixedpoint_turbo_decoder.m's loop algebra and Q-format, but
    % with the inner constituent core swapped to the exact-Log-MAP
    % reference (scripts/fixedpoint_constituent_decoder_logmap.m). `exact`
    % toggles EXACT_LOGMAP: with exact=false this is byte-identical to the
    % merged Max-Log-MAP loop (the superset tie-back). Kept local so the
    % merged references are untouched.
    %
    % Pinned widths (inherited from the merged references; do not re-derive).
    W_in=9; F_in=4; W_gamma=10; W_ab=15; W_delta=17; W_xe=18;
    W_ext=12; W_acc=14;

    in_min  = -2^(W_in -1); in_max  = 2^(W_in -1)-1;
    ext_min = -2^(W_ext-1); ext_max = 2^(W_ext-1)-1;
    acc_min = -2^(W_acc-1); acc_max = 2^(W_acc-1)-1;
    lsb = 2^(-F_in);

    core_p = struct('W_in',W_in,'F_in',F_in,'W_gamma',W_gamma, ...
                    'W_ab',W_ab,'W_delta',W_delta,'W_xe',W_xe, ...
                    'EXACT_LOGMAP', exact, 'LUT_D', 56);

    K = size(d_a,2) - 4;

    z_a = zeros(1,K+3); z_prime_a = zeros(1,K+3);
    x_a = zeros(1,K+3); x_prime_a = zeros(1,K+3);
    z_a(1:K)       = d_a(2,1:K);
    z_prime_a(1:K) = d_a(3,1:K);
    ch_sys         = d_a(1,1:K);
    x_a(K+1)=d_a(1,K+1); z_a(K+1)=d_a(2,K+1);
    x_a(K+2)=d_a(3,K+1); z_a(K+2)=d_a(1,K+2);
    x_a(K+3)=d_a(2,K+2); z_a(K+3)=d_a(3,K+2);
    x_prime_a(K+1)=d_a(1,K+3); z_prime_a(K+1)=d_a(2,K+3);
    x_prime_a(K+2)=d_a(3,K+3); z_prime_a(K+2)=d_a(1,K+4);
    x_prime_a(K+3)=d_a(2,K+4); z_prime_a(K+3)=d_a(3,K+4);

    ch_sys_q = sat_round(ch_sys / lsb, ext_min, ext_max);
    za_core  = sat_round(z_a       / lsb, in_min, in_max);
    zpa_core = sat_round(z_prime_a / lsb, in_min, in_max);
    xa_term  = sat_round(x_a(K+1:K+3)       / lsb, in_min, in_max);
    xpa_term = sat_round(x_prime_a(K+1:K+3) / lsb, in_min, in_max);

    c_a_q = zeros(1,K);
    c_e_q = zeros(1,K);
    H = round(2 * max_iterations);

    for h = 0:H-1
        if mod(h,2) == 0
            xa_body_core = zeros(1,K);
            for k = 1:K
                acc = sat_add(c_a_q(k), ch_sys_q(k), acc_min, acc_max);
                xa_body_core(k) = sat_clip(acc, in_min, in_max);
            end
            xa_core = [xa_body_core, xa_term];
            [~, x_e_q] = fixedpoint_constituent_decoder_logmap( ...
                double(xa_core)*lsb, double(za_core)*lsb, core_p);
            for k = 1:K
                acc = sat_add(x_e_q(k), ch_sys_q(k), acc_min, acc_max);
                c_e_q(k) = sat_clip(acc, ext_min, ext_max);
            end
        else
            xpa_body_core = zeros(1,K);
            ce_perm = c_e_q(pii + 1);
            for k = 1:K
                xpa_body_core(k) = sat_clip(ce_perm(k), in_min, in_max);
            end
            xpa_core = [xpa_body_core, xpa_term];
            [~, xp_e_q] = fixedpoint_constituent_decoder_logmap( ...
                double(xpa_core)*lsb, double(zpa_core)*lsb, core_p);
            scatter = zeros(1,K);
            for k = 1:K
                scatter(k) = sat_clip(xp_e_q(k), ext_min, ext_max);
            end
            c_a_q(pii + 1) = scatter;
        end
    end

    c = zeros(1,K);
    for k = 1:K
        acc = sat_add(c_a_q(k), c_e_q(k), acc_min, acc_max);
        c(k) = double(acc < 0);
    end
end

function y = sat_round(x, lo, hi)
    r = sign(x) .* floor(abs(x) + 0.5);
    y = max(lo, min(hi, r));
end
function y = sat_clip(x, lo, hi)
    if x > hi, y = hi; elseif x < lo, y = lo; else, y = x; end
end
function y = sat_add(a, b, lo, hi)
    s = a + b;
    if s > hi, y = hi; elseif s < lo, y = lo; else, y = s; end
end

% ===================== main body =====================
repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_root);
addpath(fullfile(repo_root, 'scripts'));

% --- Bounded grid (small + fast; the point is to SHOW the gain). ---
K_values   = [40, 512];
% SNR grid (Es/N0 dB) spanning the rate-1/3 turbo waterfall (matches the
% merged characterize_turbo_decoder.m grid so the curves are comparable).
snr_db_set = [-2.5, -2.0, -1.5, -1.0, -0.5];

% Frames per cell, K-dependent (~5k bits/cell for a stable ~1e-2 estimate
% while staying tractable: this script runs THREE decoders per frame).
frames_for_K = containers.Map('KeyType','double','ValueType','double');
frames_for_K(40)  = 80;    % 40*80  = 3200 bits/cell
frames_for_K(512) = 6;     % 512*6  = 3072 bits/cell (3 decoders/frame)

max_iter   = 8;            % H = 16 half-iterations (confirmed default).
target_ber = 1e-2;

% --- Pinned acceptance band (design.md §7). ---
% (1) fp-exact must NOT be worse than fp-MaxLogMAP at target BER (gain >= 0,
%     allowing a tiny grid-interpolation tolerance).
% (2) fp-exact must be WITHIN this margin of float-exact at target BER.
gain_tol_db    = 0.10;   % fp-exact may sit up to 0.10 dB right of fp-MaxLogMAP
                         % (grid-interpolation slack); expect a LEFT shift.
band_vs_float  = 0.75;   % fp-exact within 0.75 dB of float-exact at target BER.

rand('state',  20260525);
randn('state', 20260525);

global approx_star;

n_K   = numel(K_values);
n_snr = numel(snr_db_set);
ber_a = zeros(n_K, n_snr);   % (a) fixed-point Max-Log-MAP
ber_b = zeros(n_K, n_snr);   % (b) fixed-point exact Log-MAP
ber_c = zeros(n_K, n_snr);   % (c) float exact Log-MAP

rows = {};
rows{end+1} = sprintf('%-6s %-8s %-7s %-13s %-13s %-13s', ...
    'K', 'SNR_dB', 'frames', 'fpMaxLog_BER', 'fpExact_BER', 'flExact_BER');

for ki = 1:n_K
    K = K_values(ki);
    pii = internal_interleaver(0:K-1);
    frames_per_cell = frames_for_K(K);

    for si = 1:n_snr
        snr_db = snr_db_set(si);
        sigma2 = 10 ^ (-snr_db / 10);
        sigma  = sqrt(sigma2);

        err_a = 0; err_b = 0; err_c = 0; nb = 0;
        for f = 1:frames_per_cell
            c = double(rand(1, K) < 0.5);
            d = turbo_encoder(c, pii);
            y = (1 - 2*d) + sigma * randn(size(d));
            d_llr = 2 * y / sigma2;

            % (a) fixed-point Max-Log-MAP (merged reference, unmodified).
            c_a = fixedpoint_turbo_decoder(d_llr, pii, max_iter);
            % (b) fixed-point exact Log-MAP (local loop, exact core).
            c_b = logmap_turbo_loop(d_llr, pii, max_iter, true);
            % (c) float exact Log-MAP.
            approx_star = false;
            c_c = turbo_decoder(d_llr, pii, max_iter);

            err_a = err_a + sum(c_a ~= c);
            err_b = err_b + sum(c_b ~= c);
            err_c = err_c + sum(c_c ~= c);
            nb    = nb + K;
        end

        ber_a(ki, si) = err_a / nb;
        ber_b(ki, si) = err_b / nb;
        ber_c(ki, si) = err_c / nb;

        rows{end+1} = sprintf('%-6d %-8.2f %-7d %-13.4e %-13.4e %-13.4e', ...
            K, snr_db, frames_per_cell, ...
            ber_a(ki, si), ber_b(ki, si), ber_c(ki, si));
    end
end

% --- dB recovered: horizontal shift at target_ber, per K. ---
% gain_db = SNR_fpMaxLog(tgt) - SNR_fpExact(tgt)  (positive => exact is better,
% i.e. needs LESS SNR). gap_vs_float = SNR_fpExact(tgt) - SNR_flExact(tgt).
worst_gain = Inf;     % smallest (worst) gain across K
worst_gap  = -Inf;    % largest (worst) gap to float across K
loss_rows = {};
loss_rows{end+1} = sprintf('%-6s %-12s %-12s %-12s %-12s %-12s', ...
    'K', 'fpMaxLog@t', 'fpExact@t', 'flExact@t', 'gain_dB', 'gapFloat_dB');

any_unbracketed = false;
for ki = 1:n_K
    s_a = crossing_snr(snr_db_set, ber_a(ki,:), target_ber);
    s_b = crossing_snr(snr_db_set, ber_b(ki,:), target_ber);
    s_c = crossing_snr(snr_db_set, ber_c(ki,:), target_ber);
    if isnan(s_a) || isnan(s_b) || isnan(s_c)
        any_unbracketed = true;
        loss_rows{end+1} = sprintf('%-6d %-12s %-12s %-12s %-12s %-12s', ...
            K_values(ki), fmt_snr(s_a), fmt_snr(s_b), fmt_snr(s_c), ...
            'N/A', 'N/A');
    else
        gain = s_a - s_b;          % >0 => exact recovers SNR vs Max-Log-MAP
        gap  = s_b - s_c;          % distance from exact to float upper bound
        worst_gain = min(worst_gain, gain);
        worst_gap  = max(worst_gap,  abs(gap));
        loss_rows{end+1} = sprintf('%-6d %-12.3f %-12.3f %-12.3f %-12.3f %-12.3f', ...
            K_values(ki), s_a, s_b, s_c, gain, gap);
    end
end

% Unbracketed cells (short block not reaching the shallow target BER on this
% grid) are informational N/A, NOT a failure — same precedent as the
% de-rate-match characterization. The gain is judged on cells that DO bracket
% the target (requiring at least one, i.e. worst_gain became finite).
overall_pass = isfinite(worst_gain) && ...
               (worst_gain >= -gain_tol_db) && ...
               (worst_gap  <= band_vs_float);

% --- Print + persist. ---
header = sprintf('\n%s\n%s\n', ...
    'characterize_exact_log_map — fixed-point exact vs Max-Log-MAP vs float exact', ...
    repmat('-', 1, 78));
header = [header, sprintf('max_iter = %d (H = %d half-iters)   target BER = %.0e\n\n', ...
    max_iter, 2*max_iter, target_ber)];

footer = sprintf('\ndB recovered by fixed-point exact Log-MAP (horizontal at BER = %.0e):\n', target_ber);
for ii = 1:numel(loss_rows)
    footer = [footer, sprintf('  %s\n', loss_rows{ii})];
end
footer = [footer, sprintf('\n  gain_dB     = SNR_fpMaxLog(tgt) - SNR_fpExact(tgt)  (>0 => exact recovers SNR)\n')];
footer = [footer, sprintf('  gapFloat_dB = SNR_fpExact(tgt) - SNR_flExact(tgt)   (distance to float upper bound)\n')];
footer = [footer, sprintf('\nPinned band (design.md §7):\n')];
footer = [footer, sprintf('  fp-exact gain over fp-MaxLogMAP >= %.2f dB (>=0; tol for grid interp)\n', -gain_tol_db)];
footer = [footer, sprintf('  fp-exact within %.2f dB of float-exact at target BER\n', band_vs_float)];
if isfinite(worst_gain)
    footer = [footer, sprintf('Worst gain over Max-Log-MAP: %.3f dB   Worst gap to float-exact: %.3f dB\n', ...
        worst_gain, worst_gap)];
else
    footer = [footer, sprintf('Worst gain/gap: (target BER not bracketed on grid for some K)\n')];
end
if overall_pass
    footer = [footer, sprintf('OVERALL: PASS (exact >= Max-Log-MAP and within band of float)\n')];
else
    footer = [footer, sprintf('OVERALL: FAIL (band violated or target BER unbracketed — see above)\n')];
end

fprintf('%s', header);
for ii = 1:numel(rows)
    fprintf('%s\n', rows{ii});
end
fprintf('%s', footer);

results_dir = fullfile(repo_root, 'results');
if exist(results_dir, 'dir')
    out_path = fullfile(results_dir, 'characterize_exact_log_map.txt');
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
    error('characterize_exact_log_map:BandViolated', ...
          'exact-Log-MAP BER band not met — see table above.');
end
