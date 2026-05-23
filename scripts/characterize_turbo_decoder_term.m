% CHARACTERIZE_TURBO_DECODER_TERM  Outer bounded check for the P3 turbo
% decoder extensions (openspec/changes/add-fpga-turbo-decoder-termination,
% task 1.5): the fixed-point reference scripts/fixedpoint_turbo_decoder_term.m
% (+ scripts/fixedpoint_turbo_harq_accumulate.m) vs the float oracles
% turbo_decoder.m / turbo_decoding_chain.m, over a bounded grid.
%
% This EXTENDS the P2 outer oracle (characterize_turbo_decoder.m, which
% remains the BER-vs-SNR implementation-loss gate and is UNCHANGED) with the
% three P3 behaviours. It is intentionally bounded (few SNR points, modest
% frames, shallow target BER) — a trend/margin check, not a deep waterfall.
%
% It reports, and gates on, four things:
%
%   (A) BER-vs-SNR implementation loss, fp(early-term ON) vs float
%       turbo_decoder.m(early-term ON): the fp curve must sit within a
%       documented dB band of the float curve at a shallow target BER. (The
%       same gate-discipline as P2; here BOTH decoders run CRC early-term so
%       the comparison is apples-to-apples.)
%
%   (B) Early-stop iterations_performed DISTRIBUTION: average iterations
%       performed must DROP monotonically (within a tolerance) as SNR rises
%       (most blocks converge in 1-3 iterations at good SNR; low SNR runs to
%       max_iter). Reported per (K, SNR) for both float and fp; gated on the
%       fp average iters tracking the float average within a band AND on the
%       high-SNR average being well below max_iter (the latency win exists).
%
%   (C) CRC-pass RATE: fraction of blocks whose returned hard decision has a
%       passing CRC (iterations_performed < max_iterations). Must rise toward
%       1.0 at high SNR for both decoders, and the fp rate must track the
%       float rate within a band.
%
%   (D) HARQ improvement: at a per-transmission SNR too low to decode in one
%       shot, the cumulative BER after N_retx_max soft-combined transmissions
%       must be STRICTLY LOWER than after the first transmission alone, for
%       both the float chain and the fp reference. (Trend, not a margin.)
%
% Bounded by design: K in {40, 512}; a handful of SNR points; modest frames;
% target BER ~1e-2; max_iter = 8 (H = 16). N_retx_max = 4.
%
% Outputs: per-cell tables for (A)-(C), a HARQ summary for (D), and an overall
% pass/fail. Optionally writes results/characterize_turbo_decoder_term.txt
% (silent no-op if results/ absent).

1;  % script (script-local functions defined before use, per Octave scoping).

function s = crossing_snr(snr, ber, target)
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
    if isnan(v); str = '--'; else; str = sprintf('%.3f', v); end
end

function s = tern(b)
    if b; s = 'PASS'; else; s = 'FAIL'; end
end

repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_root);
addpath(fullfile(repo_root, 'scripts'));

% --- Bounded grid. ---
K_values   = [40, 512];
snr_db_set = [-2.5, -2.0, -1.5, -1.0, -0.5];

frames_for_K = containers.Map('KeyType', 'double', 'ValueType', 'double');
frames_for_K(40)  = 120;
frames_for_K(512) = 10;

max_iter = 8;             % H = 16 half-iterations (confirmed default).
target_ber = 1e-2;

% --- Pinned acceptance bands (PINNED in design.md). ---
band_impl_loss_db = 1.0;  % (A) fp BER no more than 1.0 dB right of float @1e-2
band_iters_tol    = 1.5;  % (B) |avg fp iters - avg float iters| <= 1.5 (half-iters)
high_snr_iter_max = 6.0;  % (B) at the top SNR the avg iters must be < this
                          %     (well below max_iter=8 => latency win exists)
band_crcrate_tol  = 0.20; % (C) |fp CRC-pass rate - float CRC-pass rate| <= 0.20

% HARQ (D): N_retx_max=4 at a low per-tx SNR; cumulative BER must drop.
N_retx_max  = 4;
harq_snr_db = -6.0;       % per-transmission SNR (decodes only after combine)
harq_K      = 40;
harq_frames = 40;

% Reproducibility.
rand('state',  20260522);
randn('state', 20260522);

global approx_star;
approx_star = true;       % float decoder runs Max-Log-MAP (matches fp algo).

% CRC generator (CRC24B code-block CRC; C>1 case — the standard per-CB CRC).
G_max = get_crc_generator_matrix(6144, get_3gpp_crc_polynomial('CRC24B'));
L_crc = 24;

n_K = numel(K_values); n_snr = numel(snr_db_set);
ber_fl  = zeros(n_K, n_snr); ber_fp  = zeros(n_K, n_snr);
it_fl   = zeros(n_K, n_snr); it_fp   = zeros(n_K, n_snr);   % avg iters
crc_fl  = zeros(n_K, n_snr); crc_fp  = zeros(n_K, n_snr);   % CRC-pass rate

rows = {};
rows{end+1} = sprintf('%-6s %-8s %-7s %-11s %-11s %-9s %-9s %-9s %-9s', ...
    'K','SNR_dB','frames','float_BER','fp_BER','flIters','fpIters','flCRC%','fpCRC%');

for ki = 1:n_K
    K = K_values(ki);
    pii = internal_interleaver(0:K-1);
    frames_per_cell = frames_for_K(K);

    for si = 1:n_snr
        snr_db = snr_db_set(si);
        sigma2 = 10 ^ (-snr_db / 10);
        sigma  = sqrt(sigma2);

        err_fl=0; err_fp=0; nb=0;
        sit_fl=0; sit_fp=0; ncrc_fl=0; ncrc_fp=0;
        for f = 1:frames_per_cell
            % Build a block whose last L_crc info bits ARE a valid CRC24B so
            % that a correct decode yields a passing CRC (early-term fires).
            a  = double(rand(1, K - L_crc) < 0.5);
            pp = calculate_crc_bits(a, G_max);
            c  = [a, pp];

            d = turbo_encoder(c, pii);
            y = (1 - 2 * d) + sigma * randn(size(d));
            d_llr = 2 * y / sigma2;

            approx_star = true;
            [c_fl, itf] = turbo_decoder(d_llr, pii, max_iter, G_max);
            [c_fp, itp] = fixedpoint_turbo_decoder_term(d_llr, pii, max_iter, ...
                                struct('G_max', G_max));

            err_fl = err_fl + sum(c_fl ~= c);
            err_fp = err_fp + sum(c_fp ~= c);
            sit_fl = sit_fl + itf;  sit_fp = sit_fp + itp;
            ncrc_fl = ncrc_fl + (itf < max_iter);
            ncrc_fp = ncrc_fp + (itp < max_iter);
            nb = nb + K;
        end

        ber_fl(ki,si) = err_fl / nb;   ber_fp(ki,si) = err_fp / nb;
        it_fl(ki,si)  = sit_fl / frames_per_cell;
        it_fp(ki,si)  = sit_fp / frames_per_cell;
        crc_fl(ki,si) = 100 * ncrc_fl / frames_per_cell;
        crc_fp(ki,si) = 100 * ncrc_fp / frames_per_cell;

        rows{end+1} = sprintf('%-6d %-8.2f %-7d %-11.4e %-11.4e %-9.3f %-9.3f %-9.1f %-9.1f', ...
            K, snr_db, frames_per_cell, ber_fl(ki,si), ber_fp(ki,si), ...
            it_fl(ki,si), it_fp(ki,si), crc_fl(ki,si), crc_fp(ki,si));
    end
end

% =================== (A) BER implementation loss ===================
worst_loss = -Inf; loss_rows = {};
loss_rows{end+1} = sprintf('%-6s %-14s %-14s %-12s','K','float_SNR@tgt','fp_SNR@tgt','loss_dB');
for ki = 1:n_K
    s_fl = crossing_snr(snr_db_set, ber_fl(ki,:), target_ber);
    s_fp = crossing_snr(snr_db_set, ber_fp(ki,:), target_ber);
    if isnan(s_fl) || isnan(s_fp)
        loss_rows{end+1} = sprintf('%-6d %-14s %-14s %-12s', ...
            K_values(ki), fmt_snr(s_fl), fmt_snr(s_fp), 'N/A (grid)');
    else
        loss = s_fp - s_fl; worst_loss = max(worst_loss, loss);
        loss_rows{end+1} = sprintf('%-6d %-14.3f %-14.3f %-12.3f', ...
            K_values(ki), s_fl, s_fp, loss);
    end
end
passA = isfinite(worst_loss) && (worst_loss <= band_impl_loss_db);

% =================== (B) early-stop iters distribution ===================
% fp avg iters must track float within band; both must drop with SNR; the
% top-SNR avg must be below high_snr_iter_max (latency win exists).
worst_iter_dev = 0; passB_drop = true; passB_top = true;
for ki = 1:n_K
    worst_iter_dev = max(worst_iter_dev, max(abs(it_fp(ki,:) - it_fl(ki,:))));
    % monotone-ish drop: top-SNR avg < bottom-SNR avg for both.
    passB_drop = passB_drop && (it_fp(ki,end) < it_fp(ki,1)) ...
                            && (it_fl(ki,end) < it_fl(ki,1));
    passB_top  = passB_top  && (it_fp(ki,end) < high_snr_iter_max);
end
passB = (worst_iter_dev <= band_iters_tol) && passB_drop && passB_top;

% =================== (C) CRC-pass rate tracking ===================
worst_crc_dev = 0;
for ki = 1:n_K
    worst_crc_dev = max(worst_crc_dev, max(abs(crc_fp(ki,:) - crc_fl(ki,:)))/100);
end
passC = worst_crc_dev <= band_crcrate_tol;

% =================== (D) HARQ improvement ===================
pii_h = internal_interleaver(0:harq_K-1);
sig_h = sqrt(10 ^ (-harq_snr_db / 10));
err_fp_tx1 = 0; err_fp_txN = 0; err_fl_tx1 = 0; err_fl_txN = 0; nb_h = 0;
for f = 1:harq_frames
    a  = double(rand(1, harq_K - L_crc) < 0.5);
    pp = calculate_crc_bits(a, G_max);
    c  = [a, pp];
    d  = turbo_encoder(c, pii_h);

    buf_fp = []; buf_fl = zeros(3, harq_K + 4);
    c_fp_1 = []; c_fl_1 = [];
    for tx = 1:N_retx_max
        y = (1 - 2 * d) + sig_h * randn(size(d));
        d_llr = 2 * y / sig_h^2;

        % fp soft-combine then decode.
        [buf_fp, d_comb] = fixedpoint_turbo_harq_accumulate(buf_fp, d_llr);
        c_fp = fixedpoint_turbo_decoder_term(d_comb, pii_h, max_iter, ...
                            struct('G_max', G_max));
        % float chain-style accumulate (obj.buffers + d) then decode.
        buf_fl = buf_fl + d_llr;
        c_fl = turbo_decoder(buf_fl, pii_h, max_iter, G_max);

        if tx == 1
            c_fp_1 = c_fp; c_fl_1 = c_fl;
        end
    end
    err_fp_tx1 = err_fp_tx1 + sum(c_fp_1 ~= c);
    err_fp_txN = err_fp_txN + sum(c_fp ~= c);
    err_fl_tx1 = err_fl_tx1 + sum(c_fl_1 ~= c);
    err_fl_txN = err_fl_txN + sum(c_fl ~= c);
    nb_h = nb_h + harq_K;
end
ber_fp_tx1 = err_fp_tx1 / nb_h; ber_fp_txN = err_fp_txN / nb_h;
ber_fl_tx1 = err_fl_tx1 / nb_h; ber_fl_txN = err_fl_txN / nb_h;
passD = (ber_fp_txN < ber_fp_tx1) && (ber_fl_txN < ber_fl_tx1);

overall_pass = passA && passB && passC && passD;

% =================== Print + persist ===================
header = sprintf('\n%s\n%s\n', ...
  'characterize_turbo_decoder_term — P3 outer bounded check (early-term + HARQ + filler)', ...
  repmat('-',1,90));
header = [header, sprintf('max_iter=%d (H=%d)  target BER=%.0e  CRC=CRC24B  N_retx_max=%d\n\n', ...
  max_iter, 2*max_iter, target_ber, N_retx_max)];

footer = sprintf('\n(A) BER implementation loss (horizontal dB at BER=%.0e), early-term ON both:\n', target_ber);
for ii=1:numel(loss_rows); footer=[footer,sprintf('  %s\n',loss_rows{ii})]; end
footer = [footer, sprintf('    band <= %.2f dB ; worst observed = %s ; %s\n', ...
  band_impl_loss_db, fmt_snr(worst_loss), tern(passA))];

footer = [footer, sprintf('\n(B) Early-stop avg iterations_performed (see flIters/fpIters columns):\n')];
footer = [footer, sprintf('    fp-vs-float worst avg-iter deviation = %.3f (band <= %.2f half-iters)\n', ...
  worst_iter_dev, band_iters_tol)];
footer = [footer, sprintf('    avg iters drops with SNR for both: %d ; top-SNR avg < %.1f: %d ; %s\n', ...
  passB_drop, high_snr_iter_max, passB_top, tern(passB))];

footer = [footer, sprintf('\n(C) CRC-pass rate (see flCRC%%/fpCRC%% columns):\n')];
footer = [footer, sprintf('    fp-vs-float worst CRC-pass-rate deviation = %.3f (band <= %.2f) ; %s\n', ...
  worst_crc_dev, band_crcrate_tol, tern(passC))];

footer = [footer, sprintf('\n(D) HARQ improvement @ per-tx SNR=%.1f dB, K=%d, %d frames, N_retx_max=%d:\n', ...
  harq_snr_db, harq_K, harq_frames, N_retx_max)];
footer = [footer, sprintf('    fp   BER: tx1=%.4e -> txN=%.4e (improves: %d)\n', ber_fp_tx1, ber_fp_txN, ber_fp_txN<ber_fp_tx1)];
footer = [footer, sprintf('    float BER: tx1=%.4e -> txN=%.4e (improves: %d) ; %s\n', ber_fl_tx1, ber_fl_txN, ber_fl_txN<ber_fl_tx1, tern(passD))];

footer = [footer, sprintf('\nOVERALL: %s\n', tern(overall_pass))];

fprintf('%s', header);
for ii=1:numel(rows); fprintf('%s\n', rows{ii}); end
fprintf('%s', footer);

results_dir = fullfile(repo_root, 'results');
if exist(results_dir, 'dir')
    out_path = fullfile(results_dir, 'characterize_turbo_decoder_term.txt');
    fid = fopen(out_path, 'w');
    if fid >= 0
        fprintf(fid, '%s', header);
        for ii=1:numel(rows); fprintf(fid, '%s\n', rows{ii}); end
        fprintf(fid, '%s', footer);
        fclose(fid);
        fprintf('\nWrote %s\n', out_path);
    end
end

if ~overall_pass
    error('characterize_turbo_decoder_term:BandViolated', ...
          'P3 outer check failed — see table above (A/B/C/D).');
end
