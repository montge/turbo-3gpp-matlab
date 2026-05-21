% CHARACTERIZE_CONSTITUENT_DECODER  Outer equivalence check (task 1.3):
% fixed-point Max-Log-MAP reference vs float constituent_decoder.m on
% *identical* LLR frames, over a bounded {K, SNR} grid.
%
% This is EXPLICITLY NOT a communications-BER check. A lone non-iterative
% constituent decoder has poor BER by design — turbo gain is the
% iteration. The P2 oracle is BER; the P1 oracle is numerical
% extrinsic-LLR equivalence on identical inputs (see
% hdl/docs/decoder_roadmap.md §1 and the change's design.md §1).
%
% For each (K, SNR, frame) cell:
%   - Random uncoded block c (K bits, uniform).
%   - Encoded with the existing constituent_encoder.m -> (x, z).
%   - BPSK + AWGN at the given SNR (Es/N0 in dB; symbols = +/-1).
%   - LLRs L = 2 * y / sigma^2 (the standard AWGN BPSK channel LLR).
%   - Decode with float constituent_decoder.m (approx_star=true =>
%     Max-Log-MAP; we isolate quantization, not algorithm choice).
%   - Decode with scripts/fixedpoint_constituent_decoder.m on the same LLRs.
%   - Aggregate per cell: mean |err|, max |err|, RMS |err|, hard-decision
%     agreement % on the systematic 1..K bits (termination tails dropped
%     because turbo_decoder discards them anyway).
%
% Also reports the same statistics vs float exact Log-MAP
% (approx_star=false). That comparison includes the Max-Log-MAP
% algorithmic loss; it's the *total* numerical gap a downstream user
% would see — useful context, but NOT the pass/fail gate. The pass/fail
% gate is the Max-Log-MAP-vs-Max-Log-MAP cell (quantization-only).
%
% Outputs: prints a per-cell table + an overall pass/fail summary.
% Optionally writes results/characterize_constituent_decoder.txt for the
% archive (silently no-ops if the dir doesn't exist).

repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_root);
addpath(fullfile(repo_root, 'scripts'));

% --- Bounded grid. Per the worktree brief and design.md §7. ---
K_values    = [40, 512, 6144];
snr_db_set  = [0, 2, 4];        % a few SNRs spanning useful operating range
frames_per_cell = 8;            % modest; Octave needs to stay tractable

% Reproducibility (full block decoder has no RNG of its own).
rand('state',  20260521);
randn('state', 20260521);

% --- Equivalence band (PINNED in design.md §4 / "Open Questions"). ---
%
% Quantization-only band (fixed-point Max-Log-MAP vs float Max-Log-MAP).
% The pinned format is W_in=9, F_in=4 (LSB=0.0625). With one F bump
% above the first-cut table, the observed worst cell across the grid is
% well inside the band below — the band is set ~1.5x above worst so it
% is a band, not a brittle equality. Hard-decision agreement is on the
% systematic bits 1..K only (termination tail is discarded downstream).
band_max_err  = 0.5;            % LLR units; ~8 LSB at F_in=4
band_rms_err  = 0.10;           % LLR units; ~1.6 LSB at F_in=4
band_hd_agree = 99.0;           % percent

% --- Storage for the report. ---
n_cells = numel(K_values) * numel(snr_db_set);
rows = cell(n_cells + 1, 1);
rows{1} = sprintf('%-6s %-7s %-7s %-9s %-9s %-9s %-7s   %-9s %-9s %-9s %-7s', ...
    'K', 'SNR_dB', 'frames', ...
    'mean_q', 'max_q',  'rms_q',  'hd_q%', ...
    'mean_e', 'max_e',  'rms_e',  'hd_e%');

idx = 0;
overall_pass = true;
worst_max = 0;
worst_rms = 0;
worst_hd  = 100;

global approx_star;

for K = K_values
    for snr_db = snr_db_set
        idx = idx + 1;

        % Es/N0 for BPSK with unit-energy symbols (Es=1) => sigma^2 = 10^(-snr/10).
        sigma2 = 10 ^ (-snr_db / 10);
        sigma  = sqrt(sigma2);

        cell_err_q   = [];   % vs float Max-Log-MAP (quantization gap)
        cell_err_e   = [];   % vs float exact Log-MAP (total numerical gap)
        cell_hd_q    = 0;    % matched-sign count, quantization-only oracle
        cell_hd_e    = 0;    % matched-sign count, exact-Log-MAP oracle
        n_bits_total = 0;

        for f = 1:frames_per_cell
            c = double(rand(1, K) < 0.5);
            [z, x] = constituent_encoder(c);     % length K+3

            n_x = sigma * randn(1, K + 3);
            n_z = sigma * randn(1, K + 3);
            % BPSK: bit 0 -> +1, bit 1 -> -1.
            y_x = 1 - 2 * x + n_x;
            y_z = 1 - 2 * z + n_z;
            L_x = 2 * y_x / sigma2;              % a-priori LLRs
            L_z = 2 * y_z / sigma2;

            % Float Max-Log-MAP (matches the fixed-point algorithm).
            approx_star = true;
            x_e_fl_ml = constituent_decoder(L_x, L_z);

            % Float exact Log-MAP (the algorithmic upper bound).
            approx_star = false;
            x_e_fl_ex = constituent_decoder(L_x, L_z);

            % Fixed-point Max-Log-MAP on the *same* LLR frame.
            x_e_fp = fixedpoint_constituent_decoder(L_x, L_z);

            % Systematic bits only (1..K). Termination tail is discarded
            % by the turbo loop anyway.
            err_q = x_e_fp(1:K) - x_e_fl_ml(1:K);
            err_e = x_e_fp(1:K) - x_e_fl_ex(1:K);

            cell_err_q = [cell_err_q, err_q];
            cell_err_e = [cell_err_e, err_e];

            cell_hd_q = cell_hd_q + sum(sign(x_e_fp(1:K)) == sign(x_e_fl_ml(1:K)));
            cell_hd_e = cell_hd_e + sum(sign(x_e_fp(1:K)) == sign(x_e_fl_ex(1:K)));
            n_bits_total = n_bits_total + K;
        end

        mean_q = mean(abs(cell_err_q));
        max_q  = max(abs(cell_err_q));
        rms_q  = sqrt(mean(cell_err_q .^ 2));
        hd_q   = 100 * cell_hd_q / n_bits_total;

        mean_e = mean(abs(cell_err_e));
        max_e  = max(abs(cell_err_e));
        rms_e  = sqrt(mean(cell_err_e .^ 2));
        hd_e   = 100 * cell_hd_e / n_bits_total;

        rows{idx + 1} = sprintf( ...
            '%-6d %-7g %-7d %-9.4f %-9.4f %-9.4f %-7.2f   %-9.4f %-9.4f %-9.4f %-7.2f', ...
            K, snr_db, frames_per_cell, ...
            mean_q, max_q, rms_q, hd_q, ...
            mean_e, max_e, rms_e, hd_e);

        % Pass/fail is on the QUANTIZATION cell (fp vs float Max-Log-MAP).
        cell_pass = (max_q <= band_max_err) && ...
                    (rms_q <= band_rms_err) && ...
                    (hd_q  >= band_hd_agree);
        if ~cell_pass
            overall_pass = false;
        end
        worst_max = max(worst_max, max_q);
        worst_rms = max(worst_rms, rms_q);
        worst_hd  = min(worst_hd,  hd_q);
    end
end

% --- Print + persist. ---
header_block = sprintf('\n%s\n%s\n', ...
    'characterize_constituent_decoder — outer equivalence (NOT a BER check)', ...
    repmat('-', 1, 95));
suffix_block = sprintf('\nLegend: *_q = vs float Max-Log-MAP (quantization-only, pass/fail gate)\n');
suffix_block = [suffix_block, sprintf( ...
    '        *_e = vs float exact Log-MAP (informational; includes algorithmic gap)\n')];
suffix_block = [suffix_block, sprintf( ...
    '\nPinned equivalence band (quantization cell):\n')];
suffix_block = [suffix_block, sprintf( ...
    '  max|err|         <= %.3f LLR (~%d LSB at F_in=4)\n', band_max_err, round(band_max_err*16))];
suffix_block = [suffix_block, sprintf( ...
    '  RMS|err|         <= %.3f LLR (~%d LSB at F_in=4)\n', band_rms_err, round(band_rms_err*16))];
suffix_block = [suffix_block, sprintf( ...
    '  hard-decision %% >= %.2f%%\n', band_hd_agree)];
suffix_block = [suffix_block, sprintf( ...
    '\nWorst observed: max=%.4f  rms=%.4f  hd=%.2f%%\n', worst_max, worst_rms, worst_hd)];
if overall_pass
    suffix_block = [suffix_block, sprintf('OVERALL: PASS (within band)\n')];
else
    suffix_block = [suffix_block, sprintf('OVERALL: FAIL (band violated — see cells above)\n')];
end

fprintf('%s', header_block);
for ii = 1:numel(rows)
    fprintf('%s\n', rows{ii});
end
fprintf('%s', suffix_block);

% Optional artifact (silent if results/ doesn't exist).
results_dir = fullfile(repo_root, 'results');
if exist(results_dir, 'dir')
    out_path = fullfile(results_dir, 'characterize_constituent_decoder.txt');
    fid = fopen(out_path, 'w');
    if fid >= 0
        fprintf(fid, '%s', header_block);
        for ii = 1:numel(rows)
            fprintf(fid, '%s\n', rows{ii});
        end
        fprintf(fid, '%s', suffix_block);
        fclose(fid);
        fprintf('\nWrote %s\n', out_path);
    end
end

if ~overall_pass
    error('characterize_constituent_decoder:BandViolated', ...
          'Equivalence band not met — see table above.');
end
