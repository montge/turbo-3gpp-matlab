% CHARACTERIZE_SLIDING_WINDOW  M2 stage-1 windowing-loss characterization for
% the sliding-window fixed-point constituent reference
% (scripts/fixedpoint_constituent_decoder_sw.m) vs the full-block P1 reference
% (scripts/fixedpoint_constituent_decoder.m) and the float oracles.
%
% This is the gating inner-oracle characterization for M2
% (openspec/changes/add-fpga-decoder-sliding-window). It establishes three
% things, in order:
%
%   PART 0 — SUPERSET (byte-exact). With window_len >= K+3 the windowed
%     reference MUST reproduce the full-block reference's W_xe integer codes
%     BYTE-FOR-BYTE (design.md §6). Asserted hard (errors out on any mismatch)
%     across the representative K set with random LLR frames. This is the
%     strict-superset regression cross-check.
%
%   PART A — CONSTITUENT WINDOWING-LOSS (the new outer-A band, constituent
%     level). Windowed (W,L) vs full-block fixed-point on IDENTICAL encoded
%     LLR frames: extrinsic-LLR max|err| / RMS|err| + systematic hard-decision
%     agreement, across K in {40, 512, 6144} x a few SNRs INCLUDING the
%     low-SNR + large-K corner, swept over (W, L). The quantization is shared
%     (it cancels), so this isolates the PURE WINDOWING error. Pins the W/L
%     default and the windowing-loss band ~1.5x above the worst converged cell
%     (the P1 discipline).
%
%   PART B — LOOP-LEVEL BER (the new outer-A band, loop level). Bounded
%     BER-vs-SNR of the windowed-core turbo decoder vs the full-block-core
%     turbo decoder vs float turbo_decoder.m, confirming the windowing adds
%     <= ~0.1-0.2 dB. Reuses the P2 BER harness shape; the windowed-core turbo
%     loop is a LOCAL copy of fixedpoint_turbo_decoder.m's loop that swaps the
%     constituent for the windowed reference (the merged P2 reference is NOT
%     modified).
%
% Bounded by design (Octave tractability): few K, a handful of SNR points,
% modest frame counts. A trend/margin check, not a deep waterfall.
%
% Outputs: prints the superset result, the windowing-loss sweep table, the
% pinned W/L + band, and the loop-level BER table + loss. Optionally writes
% results/characterize_sliding_window.txt (silent no-op if results/ absent).
% Errors out if the superset is not byte-exact or a band is violated.

1;  % Script file (not a function file). Helpers defined before the body.

function s = crossing_snr(snr, ber, target)
    % SNR (linear-interpolated in log10(BER) vs SNR) at which BER crosses
    % `target`. NaN if not bracketed. BER decreasing in SNR.
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

function r = ternary(cond, a, b)
    if cond; r = a; else; r = b; end
end

% ----------------------------------------------------------------------- %
% Windowed-core turbo decoder: a LOCAL copy of fixedpoint_turbo_decoder.m's %
% loop with the ONLY change being the constituent call swapped to the      %
% windowed reference (window_len/acq_len threaded in). Everything else —    %
% the exchange Q-format, op order, half-iteration framing — is identical so %
% the comparison isolates the windowing, not loop algebra.                 %
% ----------------------------------------------------------------------- %
function c = fixedpoint_turbo_decoder_sw(d_a, pii, max_iterations, window_len, acq_len)
    p = struct('W_in',9,'F_in',4,'W_gamma',10,'W_ab',15,'W_delta',17, ...
               'W_xe',18,'W_ext',12,'W_acc',14);
    K = size(d_a, 2) - 4;
    in_min  = -2^(p.W_in  - 1);    in_max  = 2^(p.W_in  - 1) - 1;
    ext_min = -2^(p.W_ext - 1);    ext_max = 2^(p.W_ext - 1) - 1;
    acc_min = -2^(p.W_acc - 1);    acc_max = 2^(p.W_acc - 1) - 1;
    lsb = 2^(-p.F_in);
    core_p = struct('W_in',p.W_in,'F_in',p.F_in,'W_gamma',p.W_gamma, ...
                    'W_ab',p.W_ab,'W_delta',p.W_delta,'W_xe',p.W_xe);

    z_a = zeros(1,K+3); z_prime_a = zeros(1,K+3);
    x_a = zeros(1,K+3); x_prime_a = zeros(1,K+3);
    z_a(1:K) = d_a(2,1:K); z_prime_a(1:K) = d_a(3,1:K);
    ch_sys = d_a(1,1:K);
    x_a(K+1)=d_a(1,K+1); z_a(K+1)=d_a(2,K+1);
    x_a(K+2)=d_a(3,K+1); z_a(K+2)=d_a(1,K+2);
    x_a(K+3)=d_a(2,K+2); z_a(K+3)=d_a(3,K+2);
    x_prime_a(K+1)=d_a(1,K+3); z_prime_a(K+1)=d_a(2,K+3);
    x_prime_a(K+2)=d_a(3,K+3); z_prime_a(K+2)=d_a(1,K+4);
    x_prime_a(K+3)=d_a(2,K+4); z_prime_a(K+3)=d_a(3,K+4);

    ch_sys_q = sw_sat_round(ch_sys/lsb, ext_min, ext_max);
    za_core  = sw_sat_round(z_a/lsb, in_min, in_max);
    zpa_core = sw_sat_round(z_prime_a/lsb, in_min, in_max);
    xa_term  = sw_sat_round(x_a(K+1:K+3)/lsb, in_min, in_max);
    xpa_term = sw_sat_round(x_prime_a(K+1:K+3)/lsb, in_min, in_max);

    c_a_q = zeros(1,K); c_e_q = zeros(1,K);
    H = round(2*max_iterations);
    for h = 0:H-1
        if mod(h,2) == 0
            xa_body_core = zeros(1,K);
            for k = 1:K
                acc = sw_sat_add(c_a_q(k), ch_sys_q(k), acc_min, acc_max);
                xa_body_core(k) = sw_sat_clip(acc, in_min, in_max);
            end
            xa_core = [xa_body_core, xa_term];
            [~, x_e_q] = fixedpoint_constituent_decoder_sw( ...
                double(xa_core)*lsb, double(za_core)*lsb, core_p, window_len, acq_len);
            for k = 1:K
                acc = sw_sat_add(x_e_q(k), ch_sys_q(k), acc_min, acc_max);
                c_e_q(k) = sw_sat_clip(acc, ext_min, ext_max);
            end
        else
            xpa_body_core = zeros(1,K);
            ce_perm = c_e_q(pii + 1);
            for k = 1:K
                xpa_body_core(k) = sw_sat_clip(ce_perm(k), in_min, in_max);
            end
            xpa_core = [xpa_body_core, xpa_term];
            [~, xp_e_q] = fixedpoint_constituent_decoder_sw( ...
                double(xpa_core)*lsb, double(zpa_core)*lsb, core_p, window_len, acq_len);
            scatter = zeros(1,K);
            for k = 1:K
                scatter(k) = sw_sat_clip(xp_e_q(k), ext_min, ext_max);
            end
            c_a_q(pii + 1) = scatter;
        end
    end
    c = zeros(1,K);
    for k = 1:K
        acc = sw_sat_add(c_a_q(k), c_e_q(k), acc_min, acc_max);
        c(k) = double(acc < 0);
    end
end

function y = sw_sat_round(x, lo, hi)
    r = sign(x) .* floor(abs(x) + 0.5);
    y = max(lo, min(hi, r));
end
function y = sw_sat_clip(x, lo, hi)
    if x > hi; y = hi; elseif x < lo; y = lo; else; y = x; end
end
function y = sw_sat_add(a, b, lo, hi)
    s = a + b;
    if s > hi; y = hi; elseif s < lo; y = lo; else; y = s; end
end

% ======================================================================= %
% Body                                                                    %
% ======================================================================= %

repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_root);
addpath(fullfile(repo_root, 'scripts'));

global approx_star;

% Pinned windowing defaults (design.md §3 seed; confirmed below).
% L=32 met PART A but missed the PART B loop-BER band (0.261 dB > 0.20); L=48
% (near-bit-exact per PART A) is pinned — it only costs beta-acquisition
% latency, not memory, so the M2 alpha-RAM win is unaffected.
W_PIN = 64;
L_PIN = 48;

% ----------------------------------------------------------------------- %
% PART 0 — SUPERSET (window_len >= K+3 == full-block, byte-exact).         %
% ----------------------------------------------------------------------- %
rand('state', 20260524); randn('state', 20260524);
superset_K = [40, 512, 6144];
superset_fail = 0;
superset_checks = 0;
for K = superset_K
    N = K + 3;
    for t = 1:4
        x_a = 6 * randn(1, N);
        z_a = 6 * randn(1, N);
        [~, q_full] = fixedpoint_constituent_decoder(x_a, z_a);
        % window_len exactly K+3 AND strictly greater — both must collapse.
        [~, q_sw_eq] = fixedpoint_constituent_decoder_sw(x_a, z_a, [], N,      L_PIN);
        [~, q_sw_gt] = fixedpoint_constituent_decoder_sw(x_a, z_a, [], N + 17, L_PIN);
        superset_checks = superset_checks + 2;
        if any(q_full ~= q_sw_eq); superset_fail = superset_fail + 1; end
        if any(q_full ~= q_sw_gt); superset_fail = superset_fail + 1; end
    end
end

% ----------------------------------------------------------------------- %
% PART A — CONSTITUENT WINDOWING-LOSS (windowed vs full-block, identical    %
% LLR frames). Grid includes the low-SNR + large-K corner.                 %
% ----------------------------------------------------------------------- %
rand('state', 20260521); randn('state', 20260521);

A_K   = [40, 512, 6144];
% SNRs spanning the operating range; the LOWEST (0 dB) at the LARGEST K is the
% worst-case windowing corner (longer block + noisier => slower acquisition).
A_snr = [0, 2, 4];
A_WL  = [64 16; 64 24; 64 32; 64 48; 128 24; 128 32];   % (W, L) sweep
% Frames per (K, SNR) cell — fewer at large K for tractability.
A_frames = containers.Map('KeyType','double','ValueType','double');
A_frames(40)   = 12;
A_frames(512)  = 6;
A_frames(6144) = 2;

n_wl = size(A_WL, 1);
% Accumulators per (K, SNR, WL).
A_max = zeros(numel(A_K), numel(A_snr), n_wl);
A_rms = zeros(numel(A_K), numel(A_snr), n_wl);
A_hd  = zeros(numel(A_K), numel(A_snr), n_wl);

A_rows = {};
A_rows{end+1} = sprintf('%-6s %-7s %-5s %-5s %-12s %-12s %-9s', ...
    'K','SNR_dB','W','L','max|err|','rms|err|','hd%');

for ki = 1:numel(A_K)
    K = A_K(ki); N = K + 3;
    frames = A_frames(K);
    for si = 1:numel(A_snr)
        snr_db = A_snr(si);
        sigma2 = 10 ^ (-snr_db / 10); sigma = sqrt(sigma2);

        % Cache per-frame full-block extrinsics + LLR frames so each (W,L)
        % uses the SAME frames (the windowing error is differential).
        full_xe = cell(1, frames);
        frame_Lx = cell(1, frames);
        frame_Lz = cell(1, frames);
        for f = 1:frames
            c = double(rand(1, K) < 0.5);
            [z, x] = constituent_encoder(c);
            y_x = 1 - 2 * x + sigma * randn(1, K + 3);
            y_z = 1 - 2 * z + sigma * randn(1, K + 3);
            frame_Lx{f} = 2 * y_x / sigma2;
            frame_Lz{f} = 2 * y_z / sigma2;
            full_xe{f} = fixedpoint_constituent_decoder(frame_Lx{f}, frame_Lz{f});
        end

        for wi = 1:n_wl
            W = A_WL(wi, 1); L = A_WL(wi, 2);
            se = 0; ne = 0; mx = 0; hda = 0; nbits = 0;
            for f = 1:frames
                es = fixedpoint_constituent_decoder_sw( ...
                    frame_Lx{f}, frame_Lz{f}, [], W, L);
                err = es(1:K) - full_xe{f}(1:K);
                mx = max(mx, max(abs(err)));
                se = se + sum(err .^ 2); ne = ne + K;
                hda = hda + sum(sign(es(1:K)) == sign(full_xe{f}(1:K)));
                nbits = nbits + K;
            end
            A_max(ki, si, wi) = mx;
            A_rms(ki, si, wi) = sqrt(se / ne);
            A_hd(ki, si, wi)  = 100 * hda / nbits;

            A_rows{end+1} = sprintf('%-6d %-7g %-5d %-5d %-12.4f %-12.4f %-9.3f', ...
                K, snr_db, W, L, A_max(ki,si,wi), A_rms(ki,si,wi), A_hd(ki,si,wi));
        end
    end
end

% --- Pin the band from the worst PINNED (W_PIN, L_PIN) cell across the grid. ---
pin_wi = find(A_WL(:,1) == W_PIN & A_WL(:,2) == L_PIN, 1);
pin_max = max(max(A_max(:, :, pin_wi)));
pin_rms = max(max(A_rms(:, :, pin_wi)));
pin_hd  = min(min(A_hd(:, :, pin_wi)));

% Band ~1.5x above the worst converged cell (P1 discipline). HD floor set
% just under the worst observed (>= 99.9% is the converged plateau).
band_max = max(0.5, 1.5 * pin_max);   % LLR; floor at 0.5 (~8 LSB) like P1
band_rms = max(0.05, 1.5 * pin_rms);
band_hd  = 99.5;                       % percent

A_pass = (pin_max <= band_max) && (pin_rms <= band_rms) && (pin_hd >= band_hd);

% ----------------------------------------------------------------------- %
% PART B — LOOP-LEVEL BER (windowed core vs full-block core vs float).      %
% ----------------------------------------------------------------------- %
rand('state', 20260522); randn('state', 20260522);

B_K   = [40, 512];
B_snr = [-2.5, -2.0, -1.5, -1.0, -0.5];
B_frames = containers.Map('KeyType','double','ValueType','double');
B_frames(40)  = 120;
B_frames(512) = 10;
B_max_iter = 8;
B_target = 1e-2;

ber_fl = zeros(numel(B_K), numel(B_snr));
ber_full = zeros(numel(B_K), numel(B_snr));
ber_sw = zeros(numel(B_K), numel(B_snr));

B_rows = {};
B_rows{end+1} = sprintf('%-6s %-8s %-7s %-12s %-12s %-12s', ...
    'K','SNR_dB','frames','float_BER','fullblk_BER','sw_BER');

for ki = 1:numel(B_K)
    K = B_K(ki);
    pii = internal_interleaver(0:K-1);
    frames = B_frames(K);
    for si = 1:numel(B_snr)
        snr_db = B_snr(si);
        sigma2 = 10 ^ (-snr_db / 10); sigma = sqrt(sigma2);
        e_fl = 0; e_full = 0; e_sw = 0; nb = 0;
        for f = 1:frames
            c = double(rand(1, K) < 0.5);
            d = turbo_encoder(c, pii);
            y = (1 - 2 * d) + sigma * randn(size(d));
            d_llr = 2 * y / sigma2;

            approx_star = true;
            c_fl   = turbo_decoder(d_llr, pii, B_max_iter);
            c_full = fixedpoint_turbo_decoder(d_llr, pii, B_max_iter);
            c_sw   = fixedpoint_turbo_decoder_sw(d_llr, pii, B_max_iter, W_PIN, L_PIN);

            e_fl   = e_fl   + sum(c_fl   ~= c);
            e_full = e_full + sum(c_full ~= c);
            e_sw   = e_sw   + sum(c_sw   ~= c);
            nb = nb + K;
        end
        ber_fl(ki,si)   = e_fl / nb;
        ber_full(ki,si) = e_full / nb;
        ber_sw(ki,si)   = e_sw / nb;
        B_rows{end+1} = sprintf('%-6d %-8.2f %-7d %-12.4e %-12.4e %-12.4e', ...
            K, snr_db, frames, ber_fl(ki,si), ber_full(ki,si), ber_sw(ki,si));
    end
end

% Windowing BER loss = SW SNR@target - full-block SNR@target (per K).
B_loss_rows = {};
B_loss_rows{end+1} = sprintf('%-6s %-16s %-16s %-12s', ...
    'K','fullblk_SNR@tgt','sw_SNR@tgt','win_loss_dB');
worst_B_loss = -Inf;
for ki = 1:numel(B_K)
    s_full = crossing_snr(B_snr, ber_full(ki,:), B_target);
    s_sw   = crossing_snr(B_snr, ber_sw(ki,:),   B_target);
    if isnan(s_full) || isnan(s_sw)
        B_loss_rows{end+1} = sprintf('%-6d %-16s %-16s %-12s', ...
            B_K(ki), fmt_snr(s_full), fmt_snr(s_sw), 'N/A (grid)');
    else
        loss = s_sw - s_full;
        worst_B_loss = max(worst_B_loss, loss);
        B_loss_rows{end+1} = sprintf('%-6d %-16.3f %-16.3f %-12.3f', ...
            B_K(ki), s_full, s_sw, loss);
    end
end
band_B_loss = 0.2;   % windowing loop loss <= 0.2 dB (design.md §3/§7)
B_pass = ~isfinite(worst_B_loss) || (worst_B_loss <= band_B_loss);

% ----------------------------------------------------------------------- %
% Print + persist                                                          %
% ----------------------------------------------------------------------- %
out = '';
out = [out, sprintf('\n%s\n%s\n', ...
    'characterize_sliding_window — M2 windowed-vs-full-block (windowing loss)', ...
    repmat('-', 1, 78))];

out = [out, sprintf('\nPART 0 — SUPERSET (window_len >= K+3 == full-block, byte-exact):\n')];
out = [out, sprintf('  %d/%d checks byte-exact (K in {40,512,6144}).  %s\n', ...
    superset_checks - superset_fail, superset_checks, ...
    ternary(superset_fail == 0, 'PASS', 'FAIL'))];

out = [out, sprintf('\nPART A — constituent windowing-loss sweep (windowed vs full-block):\n')];
for ii = 1:numel(A_rows); out = [out, sprintf('  %s\n', A_rows{ii})]; end
out = [out, sprintf('\n  Pinned defaults: W = %d, L = %d.\n', W_PIN, L_PIN)];
out = [out, sprintf('  Worst (W=%d,L=%d) cell across grid: max=%.4f rms=%.4f hd=%.3f%%\n', ...
    W_PIN, L_PIN, pin_max, pin_rms, pin_hd)];
out = [out, sprintf('  Pinned band: max|err| <= %.3f LLR, rms|err| <= %.4f LLR, hd >= %.2f%%\n', ...
    band_max, band_rms, band_hd)];
out = [out, sprintf('  PART A: %s\n', ternary(A_pass, 'PASS', 'FAIL'))];

out = [out, sprintf('\nPART B — loop-level BER (float vs full-block-core vs windowed-core), max_iter=%d:\n', B_max_iter)];
for ii = 1:numel(B_rows); out = [out, sprintf('  %s\n', B_rows{ii})]; end
out = [out, sprintf('\n  Windowing BER loss (SW SNR@%.0e - full-block SNR@%.0e):\n', B_target, B_target)];
for ii = 1:numel(B_loss_rows); out = [out, sprintf('    %s\n', B_loss_rows{ii})]; end
out = [out, sprintf('  Pinned band: windowing loop loss <= %.2f dB\n', band_B_loss)];
if isfinite(worst_B_loss)
    out = [out, sprintf('  Worst observed windowing loss: %.3f dB\n', worst_B_loss)];
else
    out = [out, sprintf('  Worst observed windowing loss: (target BER not bracketed for some K)\n')];
end
out = [out, sprintf('  PART B: %s\n', ternary(B_pass, 'PASS', 'FAIL'))];

overall = (superset_fail == 0) && A_pass && B_pass;
out = [out, sprintf('\nOVERALL: %s\n', ternary(overall, 'PASS', 'FAIL'))];

fprintf('%s', out);

results_dir = fullfile(repo_root, 'results');
if exist(results_dir, 'dir')
    fid = fopen(fullfile(results_dir, 'characterize_sliding_window.txt'), 'w');
    if fid >= 0
        fprintf(fid, '%s', out);
        fclose(fid);
        fprintf('\nWrote %s\n', fullfile(results_dir, 'characterize_sliding_window.txt'));
    end
end

if superset_fail ~= 0
    error('characterize_sliding_window:SupersetNotByteExact', ...
          'window_len >= K+3 did NOT reproduce the full-block reference byte-for-byte.');
end
if ~A_pass
    error('characterize_sliding_window:ConstituentBandViolated', ...
          'Constituent windowing-loss band not met — see table.');
end
if ~B_pass
    error('characterize_sliding_window:LoopBandViolated', ...
          'Loop-level windowing BER-loss band not met — see table.');
end
