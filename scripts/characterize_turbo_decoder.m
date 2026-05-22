% CHARACTERIZE_TURBO_DECODER  Outer BER-vs-SNR check (P2 task 1.3):
% fixed-point iterative turbo decoder (scripts/fixedpoint_turbo_decoder.m)
% vs the float oracle turbo_decoder.m, over a bounded {K, SNR} grid.
%
% UNLIKE P1 (characterize_constituent_decoder.m, which checked numerical
% extrinsic-LLR EQUIVALENCE on identical inputs because a lone constituent
% decoder's BER is meaningless), at P2 the loop iterates and BER IS the
% meaningful oracle — this is where the Max-Log-MAP + fixed-point
% implementation loss is actually measured (roadmap §1, design.md §9). The
% gate is therefore a bounded BER-vs-SNR margin, not LLR equivalence.
%
% For each (K, SNR, frame) cell:
%   - Random uncoded block c (K bits, uniform).
%   - Turbo-encoded with the existing turbo_encoder.m -> d (3x(K+4) bits).
%   - BPSK + AWGN at the given Es/N0 (symbols +/-1, bit 0 -> +1, bit 1 -> -1).
%   - Channel LLRs L = 2*y/sigma^2 (standard AWGN BPSK LLR).
%   - Decode with float turbo_decoder.m (Max-Log-MAP via approx_star=true,
%     so we isolate the fixed-point quantization loss, not the algorithm).
%   - Decode with scripts/fixedpoint_turbo_decoder.m on the same LLRs.
%   - Both at max_iter = 8 (H = 16 half-iterations) — the confirmed default.
%   - Aggregate per (K,SNR): float BER, fp BER, and the hard-decision
%     agreement between the two decoders (secondary diagnostic).
%
% The pass/fail gate is the IMPLEMENTATION LOSS: the horizontal dB shift
% between the fp and float BER curves at a shallow target BER (~1e-2). This
% is interpolated per K from the swept curves. A documented dB band is
% pinned ~1.5x above the worst observed loss (the same discipline P1 used
% for its equivalence band). If the band is not met, widen the
% extrinsic-exchange Q-format (W_ext / W_acc in fixedpoint_turbo_decoder.m's
% default_params) — NOT the iteration count.
%
% Bounded by design (Octave tractability): few K, a handful of SNR points
% across the waterfall, modest frame counts, shallow target BER ~1e-2..1e-3
% — a trend/margin check, not a deep waterfall.
%
% Outputs: a per-cell BER table + per-K implementation-loss summary + an
% overall pass/fail. Optionally writes
% results/characterize_turbo_decoder.txt (silent no-op if results/ absent).

1;  % Mark this file as a script (not a function file). NOTE: Octave only
    % resolves script-local functions that are DEFINED BEFORE they are
    % called in the script body, so crossing_snr/fmt_snr are defined here
    % (top), not at the bottom. (Helpers below.)

function s = crossing_snr(snr, ber, target)
    % SNR (linear-interpolated in log10(BER) vs SNR) at which the BER curve
    % crosses `target`. Returns NaN if `target` is not bracketed by the grid.
    % BER is monotonically decreasing in SNR; find the bracketing pair.
    s = NaN;
    lb = log10(max(ber, 1e-12));      % floor zeros for the log.
    lt = log10(target);
    for i = 1:numel(snr)-1
        a = lb(i); b = lb(i+1);       % a >= b (decreasing).
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

repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_root);
addpath(fullfile(repo_root, 'scripts'));

% --- Bounded grid. ---
% K: one short and one medium block. Large K (6144) is intentionally NOT in
% the BER grid (cycle budget ~4*H*K; design.md §10) — large K is reserved
% for a FEW golden vectors (task 2.2), not a BER sweep.
K_values = [40, 512];

% SNR grid (Es/N0 dB) spanning the rate-1/3 turbo waterfall. Chosen from a
% pilot sweep so both curves move from ~1e-1 down through ~1e-2..1e-3.
snr_db_set = [-2.5, -2.0, -1.5, -1.0, -0.5];

% Frames per cell, K-dependent so each cell has a comparable number of bits
% (~1e4) for a stable ~1e-2 BER estimate while keeping the larger K tractable
% in interpreted Octave (float turbo_decoder.m dominates the runtime at K=512).
frames_for_K = containers.Map('KeyType', 'double', 'ValueType', 'double');
frames_for_K(40)  = 120;   % 40*120  = 4800 bits/cell
frames_for_K(512) = 10;    % 512*10  = 5120 bits/cell (kept modest: the
                           % fixed-point scalar-loop decoder at K=512 dominates
                           % the interpreted-Octave runtime; 5k bits still gives
                           % a stable ~1e-2 estimate for a margin/trend check).

max_iter = 8;             % H = 16 half-iterations (CONFIRMED default).

% Target BER at which the horizontal implementation loss is measured.
target_ber = 1e-2;

% --- Pinned acceptance band (PINNED in design.md). ---
% Implementation loss = horizontal dB(fp) - dB(float) at target_ber, per K.
% Set ~1.5x above the worst observed loss across the grid so it is a band,
% not a brittle equality (the P1 discipline). Max-Log-MAP + W_in=9 fixed
% point typically costs a few tenths of a dB; this band is generous because
% the W_in=9 core is intentionally NOT yet width-tightened (that is M3).
band_impl_loss_db = 1.0;  % fp curve no more than 1.0 dB right of float @1e-2

% Reproducibility.
rand('state',  20260521);
randn('state', 20260521);

global approx_star;
approx_star = true;       % float decoder runs Max-Log-MAP (matches fp algo).

n_K   = numel(K_values);
n_snr = numel(snr_db_set);
ber_fl = zeros(n_K, n_snr);
ber_fp = zeros(n_K, n_snr);
hd_agree = zeros(n_K, n_snr);   % fp-vs-float hard-decision agreement (%)

rows = {};
rows{end+1} = sprintf('%-6s %-8s %-7s %-12s %-12s %-9s', ...
    'K', 'SNR_dB', 'frames', 'float_BER', 'fp_BER', 'agree%');

for ki = 1:n_K
    K = K_values(ki);
    pii = internal_interleaver(0:K-1);     % QPP pattern (c_prime = c(pi+1)).
    frames_per_cell = frames_for_K(K);

    for si = 1:n_snr
        snr_db = snr_db_set(si);
        sigma2 = 10 ^ (-snr_db / 10);      % Es=1 BPSK => sigma^2 = 10^(-SNR/10).
        sigma  = sqrt(sigma2);

        err_fl = 0; err_fp = 0; agree = 0; nb = 0;
        for f = 1:frames_per_cell
            c = double(rand(1, K) < 0.5);
            d = turbo_encoder(c, pii);                 % 3x(K+4) coded bits
            y = (1 - 2 * d) + sigma * randn(size(d));  % BPSK + AWGN
            d_llr = 2 * y / sigma2;                    % channel LLRs

            approx_star = true;
            c_fl = turbo_decoder(d_llr, pii, max_iter);
            c_fp = fixedpoint_turbo_decoder(d_llr, pii, max_iter);

            err_fl = err_fl + sum(c_fl ~= c);
            err_fp = err_fp + sum(c_fp ~= c);
            agree  = agree  + sum(c_fl == c_fp);
            nb     = nb + K;
        end

        ber_fl(ki, si)   = err_fl / nb;
        ber_fp(ki, si)   = err_fp / nb;
        hd_agree(ki, si) = 100 * agree / nb;

        rows{end+1} = sprintf('%-6d %-8.2f %-7d %-12.4e %-12.4e %-9.3f', ...
            K, snr_db, frames_per_cell, ...
            ber_fl(ki, si), ber_fp(ki, si), hd_agree(ki, si));
    end
end

% --- Implementation loss: horizontal dB shift at target_ber, per K. ---
% Interpolate (in log10-BER vs SNR) the SNR at which each curve crosses
% target_ber. Loss = SNR_fp(target) - SNR_fl(target). A positive loss means
% the fixed-point decoder needs more SNR to reach the same BER (expected).
worst_loss = -Inf;
loss_rows = {};
loss_rows{end+1} = sprintf('%-6s %-14s %-14s %-12s', ...
    'K', 'float_SNR@tgt', 'fp_SNR@tgt', 'loss_dB');

for ki = 1:n_K
    snr_fl = crossing_snr(snr_db_set, ber_fl(ki, :), target_ber);
    snr_fp = crossing_snr(snr_db_set, ber_fp(ki, :), target_ber);
    if isnan(snr_fl) || isnan(snr_fp)
        loss = NaN;
        loss_rows{end+1} = sprintf('%-6d %-14s %-14s %-12s', ...
            K_values(ki), fmt_snr(snr_fl), fmt_snr(snr_fp), 'N/A (grid)');
    else
        loss = snr_fp - snr_fl;
        worst_loss = max(worst_loss, loss);
        loss_rows{end+1} = sprintf('%-6d %-14.3f %-14.3f %-12.3f', ...
            K_values(ki), snr_fl, snr_fp, loss);
    end
end

overall_pass = isfinite(worst_loss) && (worst_loss <= band_impl_loss_db);

% --- Print + persist. ---
header = sprintf('\n%s\n%s\n', ...
    'characterize_turbo_decoder — outer BER-vs-SNR (P2; loop iterates, BER is the oracle)', ...
    repmat('-', 1, 78));
header = [header, sprintf('max_iter = %d  (H = %d half-iterations)   target BER = %.0e\n\n', ...
    max_iter, 2*max_iter, target_ber)];

footer = sprintf('\nImplementation loss (horizontal dB at BER = %.0e):\n', target_ber);
for ii = 1:numel(loss_rows)
    footer = [footer, sprintf('  %s\n', loss_rows{ii})];
end
footer = [footer, sprintf('\nPinned band: fp implementation loss <= %.2f dB at target BER\n', ...
    band_impl_loss_db)];
if isfinite(worst_loss)
    footer = [footer, sprintf('Worst observed loss: %.3f dB\n', worst_loss)];
else
    footer = [footer, sprintf('Worst observed loss: (target BER not bracketed on grid for some K)\n')];
end
footer = [footer, sprintf('Secondary: per-cell fp-vs-float hard-decision agreement in the table above.\n')];
if overall_pass
    footer = [footer, sprintf('OVERALL: PASS (within band)\n')];
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
    out_path = fullfile(results_dir, 'characterize_turbo_decoder.txt');
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
    error('characterize_turbo_decoder:BandViolated', ...
          'BER implementation-loss band not met — see table above.');
end

% (Helper functions crossing_snr / fmt_snr are defined near the top of this
%  script, before the body that calls them — required by Octave's script-
%  local function scoping.)
