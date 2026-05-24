% CHARACTERIZE_RX_CHAIN  Outer END-TO-END BER-vs-SNR check (P4 task 5.2): the
% FULL TX -> channel -> RX loop. For each (K, SNR, frame):
%   - random uncoded block c (K bits; first F_r filler bits forced 0),
%   - turbo-encode (turbo_encoder.m) -> d (3x(K+4) coded bits),
%   - TX rate-match GATHER e = d_vec(pi+1) (the SAME length-E permutation the
%     RX de-rate-match inverts; filler NaN -> known 0 transmitted bit),
%   - BPSK + AWGN at the given Es/N0 -> received y,
%   - channel LLRs L = 2*y/sigma^2,
%   - decode by BOTH RX paths on the SAME channel LLRs:
%       (a) FIXED-POINT RX chain: quantize L to W_LLR ->
%             d_a = fixedpoint_de_rate_matching(e_q, ...)   (stage-4 reference)
%             c   = fixedpoint_turbo_decoder(d_a, pi, H)    (P2 reference)
%           -- the exact arithmetic the HDL rx_chain_top does;
%       (b) FLOAT reference: the inline float de-rate-match (turbo_decoding_chain
%           lines 86-93, REPLICATED here so the source stays UNMODIFIED) on the
%           full-precision L -> float turbo_decoder(d, pi, H) (Max-Log-MAP),
%   - aggregate per (K,SNR): float BER, fixed-point BER, fp-vs-float hard-bit
%     agreement.
%
% This proves the loop CLOSES: TX -> channel -> RX recovers the block, and the
% fixed-point RX (the HDL's arithmetic) tracks the float RX within a documented
% dB band. The de-rate-match itself is information-preserving (it adds no BER
% loss of its own beyond the W_LLR/W_DRM quantization -- the stage-1
% characterize_de_rate_matching equivalence is EXACT); the implementation loss
% measured here is essentially the decoder's W_in=9 / W_ext=12 fixed-point loss
% (the P2 band) plus the shared W_LLR=8 channel-LLR input quantization.
%
% UNLIKE the inner bit-exact gates (the de_rate_matching_top / rx_chain_top
% cocotb lanes, which assert HDL == reference bit-for-bit on fixed frames), this
% is a STATISTICAL trend/margin check vs the float path -- the roadmap S1 outer
% tier, here over the WHOLE chain (the P4-specific end-to-end proof).
%
% The gate is the IMPLEMENTATION LOSS: the horizontal dB shift between the fp
% and float BER curves at a shallow target BER (~1e-2), interpolated per K. The
% pinned band is the same P2/P3 decoder band (<= ~1.0 dB; the de-rate-match adds
% no loss beyond W_LLR/W_DRM quantization).
%
% Bounded by design (Octave tractability, the P2/P3 discipline): few K, a
% handful of SNR points across the waterfall, modest frame counts, shallow
% target BER. NOT a deep waterfall -- a margin check.
%
% Outputs: a per-cell BER table + per-K implementation-loss summary + an overall
% pass/fail. Optionally writes results/characterize_rx_chain.txt (silent no-op
% if results/ absent). Uses only existing helpers (turbo_encoding_chain,
% turbo_encoder, rate_matching, internal_interleaver, turbo_decoder) + the
% stage-1 + P2 references; no existing .m source modified.

1;  % Mark as a script. NOTE: Octave only resolves script-local functions
    % DEFINED BEFORE they are called, so the helpers are defined here (top).

function s = crossing_snr(snr, ber, target)
    % SNR (linear-interpolated in log10(BER) vs SNR) at which the BER curve
    % crosses `target`. Returns NaN if `target` is not bracketed by the grid.
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

repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_root);
addpath(fullfile(repo_root, 'scripts'));
if exist(fullfile(repo_root, 'octave_shims'), 'dir')
    addpath(fullfile(repo_root, 'octave_shims'));
end

% --- Bounded end-to-end grid. Each K is a realistic 3GPP single code block
% (C = 1) whose K_r / F_r / E / QPP come from the segment math via
% turbo_encoding_chain (A, G, rv). Large K (6144) is intentionally NOT in the
% BER grid (cycle budget ~4*H*K; the few-large-K rule); it is exercised only by
% the golden vectors. ---
%   A    G     rv   label
cases = { ...
    16,   132,  0,  'K40  (E~N_cb, no wrap)'; ...
    488,  1200, 0,  'K512 (E<N_cb-ish, realistic rate)' ...
};
n_K = size(cases, 1);

% SNR grid (Es/N0 dB) spanning the turbo waterfall down THROUGH the target BER.
% Extends higher than the P2 characterize_turbo_decoder grid because the
% rate-matched effective rate here (E/(3*(K+4)) ~ 0.3-0.43) sits a little right
% of the rate-1/3 mother code, so the 1e-2 crossing is at a higher SNR; the grid
% must bracket it for the horizontal dB-loss interpolation.
snr_db_set = [-2.0, -1.0, 0.0, 1.0, 2.0, 3.0];

% Frames per cell, K-dependent so each cell has ~5e3 bits for a stable ~1e-2
% estimate while keeping the larger K tractable (the fixed-point scalar-loop
% decoder at K=512 dominates the interpreted-Octave runtime).
frames_for_K = containers.Map('KeyType', 'double', 'ValueType', 'double');
frames_for_K(40)  = 120;   % ~4800 bits/cell
frames_for_K(512) = 10;    % ~5120 bits/cell

max_iter = 8;              % H = 16 half-iterations (the rx_chain_top default).
target_ber = 1e-2;

% --- Pinned acceptance band (the P2/P3 decoder band; the de-rate-match adds no
% loss of its own). ---
band_impl_loss_db = 1.0;

% --- Pinned W_LLR channel grid (design.md Decision 3) for the fixed-point RX
% input quantize. ---
W_LLR = 8; F_in = 4;
lsb     = 2^(-F_in);
llr_min = -2^(W_LLR-1);   llr_max = 2^(W_LLR-1) - 1;

% Reproducibility.
rand('state',  20260525);
randn('state', 20260525);

global approx_star;
approx_star = true;        % float decoder runs Max-Log-MAP (matches fp algo).

n_snr  = numel(snr_db_set);
ber_fl = zeros(n_K, n_snr);
ber_fp = zeros(n_K, n_snr);
hd_agree = zeros(n_K, n_snr);
K_list = zeros(1, n_K);

rows = {};
rows{end+1} = sprintf('%-6s %-8s %-7s %-12s %-12s %-9s', ...
    'K', 'SNR_dB', 'frames', 'float_BER', 'fp_BER', 'agree%');

for ki = 1:n_K
    A      = cases{ki, 1};
    G      = cases{ki, 2};
    rv_idx = cases{ki, 3};

    % --- Realistic single code block: segment math -> K_r / F_r / E / QPP. ---
    enc = turbo_encoding_chain('A', A, 'G', G, 'rv_idx', rv_idx);
    step(enc, zeros(1, A));
    if enc.C ~= 1
        error('characterize_rx_chain:multiblock', ...
              'case %d (A=%d,G=%d) gave C=%d (need C=1)', ki, A, G, enc.C);
    end
    K      = enc.K_r(1);
    F_r    = enc.F_r(1);
    E      = enc.E_r(1);
    N_ref  = 0; I_LBRM = 0;
    pii    = enc.internal_interleaver_patterns{1};
    D      = K + 4;
    K_list(ki) = K;

    % Length-E rate-match permutation (the TX gather / RX scatter pi), built on
    % the index template exactly as turbo_coding_chain / the references do.
    d_idx = reshape(0:3*D-1, 3, D);
    d_idx(1:2, 1:F_r) = NaN;
    pii_rm = rate_matching(d_idx, N_ref, I_LBRM, rv_idx, E);   % length-E 0-based

    if isKey(frames_for_K, K)
        frames_per_cell = frames_for_K(K);
    else
        frames_per_cell = 10;
    end

    for si = 1:n_snr
        snr_db = snr_db_set(si);
        sigma2 = 10 ^ (-snr_db / 10);
        sigma  = sqrt(sigma2);

        err_fl = 0; err_fp = 0; agree = 0; nb = 0;
        for f = 1:frames_per_cell
            c = double(rand(1, K) < 0.5);
            if F_r > 0
                c(1:F_r) = 0;
            end
            d = turbo_encoder(c, pii);            % 3x(K+4) coded bits (NaN fill)

            % --- TX rate-match gather (filler NaN -> known 0 transmitted). ---
            d_vec   = reshape(d, 1, numel(d));
            e_tx    = d_vec(pii_rm + 1);
            tx_bits = e_tx;
            tx_bits(isnan(tx_bits)) = 0;

            % --- BPSK + AWGN -> channel LLRs (length E). ---
            y     = (1 - 2 * tx_bits) + sigma * randn(1, E);
            e_llr = 2 * y / sigma2;

            % --- (b) FLOAT RX: inline float de-rate-match (lines 86-93,
            %         REPLICATED) on full-precision LLRs -> float decoder. ---
            d_vec_fl = zeros(1, 3 * D);
            for k = 1:E
                idx = pii_rm(k) + 1;
                d_vec_fl(idx) = d_vec_fl(idx) + e_llr(k);
            end
            d_fl = reshape(d_vec_fl, 3, D);
            d_fl(1:2, 1:F_r) = NaN;               % filler -> +inf in decoder
            approx_star = true;
            c_fl = turbo_decoder(d_fl, pii, max_iter);

            % --- (a) FIXED-POINT RX: quantize LLRs to W_LLR, run the reference
            %         chain (= the HDL rx_chain_top arithmetic). ---
            r      = e_llr / lsb;
            e_soft = max(llr_min, min(llr_max, sign(r) .* floor(abs(r) + 0.5)));
            e_q    = double(e_soft) * lsb;
            d_a_fp = fixedpoint_de_rate_matching(e_q, K, F_r, N_ref, ...
                                                 I_LBRM, rv_idx, E);
            c_fp   = fixedpoint_turbo_decoder(d_a_fp, pii, max_iter);

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
worst_loss = -Inf;
loss_rows = {};
loss_rows{end+1} = sprintf('%-6s %-14s %-14s %-12s', ...
    'K', 'float_SNR@tgt', 'fp_SNR@tgt', 'loss_dB');

for ki = 1:n_K
    snr_fl = crossing_snr(snr_db_set, ber_fl(ki, :), target_ber);
    snr_fp = crossing_snr(snr_db_set, ber_fp(ki, :), target_ber);
    if isnan(snr_fl) || isnan(snr_fp)
        loss_rows{end+1} = sprintf('%-6d %-14s %-14s %-12s', ...
            K_list(ki), fmt_snr(snr_fl), fmt_snr(snr_fp), 'N/A (grid)');
    else
        loss = snr_fp - snr_fl;
        worst_loss = max(worst_loss, loss);
        loss_rows{end+1} = sprintf('%-6d %-14.3f %-14.3f %-12.3f', ...
            K_list(ki), snr_fl, snr_fp, loss);
    end
end

overall_pass = isfinite(worst_loss) && (worst_loss <= band_impl_loss_db);

% --- Print + persist. ---
header = sprintf('\n%s\n%s\n', ...
    'characterize_rx_chain - end-to-end TX->channel->RX BER (P4; the full-loop proof)', ...
    repmat('-', 1, 78));
header = [header, sprintf(['max_iter = %d  (H = %d half-iterations)   ', ...
    'W_LLR = %d (Q3.4)   target BER = %.0e\n\n'], ...
    max_iter, 2*max_iter, W_LLR, target_ber)];

footer = sprintf('\nImplementation loss (horizontal dB at BER = %.0e):\n', target_ber);
for ii = 1:numel(loss_rows)
    footer = [footer, sprintf('  %s\n', loss_rows{ii})];
end
footer = [footer, sprintf(['\nPinned band: fixed-point RX implementation loss ', ...
    '<= %.2f dB at target BER\n'], band_impl_loss_db)];
if isfinite(worst_loss)
    footer = [footer, sprintf('Worst observed loss: %.3f dB\n', worst_loss)];
else
    footer = [footer, sprintf(['Worst observed loss: (target BER not bracketed ', ...
        'on grid for some K)\n'])];
end
footer = [footer, sprintf(['Note: the de-rate-match is information-preserving ', ...
    '(stage-1 equivalence EXACT);\n      the loss above is the decoder W_in/W_ext ', ...
    'fixed-point + shared W_LLR input quantization.\n'])];
if overall_pass
    footer = [footer, sprintf('OVERALL: PASS (within band)\n')];
else
    footer = [footer, sprintf(['OVERALL: FAIL (band violated or target BER ', ...
        'unbracketed - see above)\n'])];
end

fprintf('%s', header);
for ii = 1:numel(rows)
    fprintf('%s\n', rows{ii});
end
fprintf('%s', footer);

results_dir = fullfile(repo_root, 'results');
if exist(results_dir, 'dir')
    out_path = fullfile(results_dir, 'characterize_rx_chain.txt');
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
    error('characterize_rx_chain:BandViolated', ...
          'End-to-end BER implementation-loss band not met - see table above.');
end
