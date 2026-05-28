% Golden vectors for the HDL iterative turbo-decode loop core
% (turbo_decoder_top, fixed-point Max-Log-MAP, TS36.212 §5.1.3.2). This is
% the inner-gate oracle the cocotb lane (hdl/sim/turbo_decoder_top/, authored
% separately under task 4.x by a sibling agent) will bit-exact against. The
% reference is scripts/fixedpoint_turbo_decoder.m (P2 task 1.x) which wraps
% the P1 fixed-point constituent reference in the float turbo_decoder.m loop
% algebra. See openspec/changes/add-fpga-turbo-decode-loop/design.md for the
% pinned Q-format table and the half-iteration framing.
%
% ---------------------------------------------------------------------------
% Build recipe per frame (mirrors scripts/characterize_turbo_decoder.m so the
% inner-gate vectors live in the same channel/LLR regime as the outer BER
% characterization):
%   1. Random uncoded block c (K bits, uniform).
%   2. QPP interleaver pattern pi = internal_interleaver(0:K-1).
%   3. Turbo-encode via the already-verified turbo_encoder.m -> d (3x(K+4)
%      coded bits, including the termination tail).
%   4. BPSK + AWGN at SNR (Es/N0 dB, Es=1, sigma^2 = 10^(-SNR/10); bit 0 ->
%      +1, bit 1 -> -1).
%   5. Channel LLRs d_llr = 2*y/sigma^2 (standard AWGN BPSK LLR), the 3x(K+4)
%      real-LLR matrix fed to turbo_decoder.m / fixedpoint_turbo_decoder.m.
%   6. Quantize d_llr to the exchange grid (F_in=4 LSB, round-half-away-from-
%      zero + saturate to the W_ext=12 word) -> the integer LSB codes d_a_q
%      the HDL will actually load. The reference re-saturates each de-muxed
%      row internally to its own width (ch_sys @ W_ext, parity/termination @
%      W_in); emitting the whole matrix at the widest exchange word (W_ext)
%      is lossless w.r.t. that internal re-saturation because |d_llr|/lsb is
%      well inside [-2048, 2047] at these SNRs and any value the reference
%      would clip to W_in it re-clips on entry regardless.
%   7. Run [c, c_a, c_e] = fixedpoint_turbo_decoder(d_llr, pi, max_iter) ->
%      the K hard-decision bits c (the REQUIRED gate output) plus the final
%      cyclic extrinsic state c_a / c_e in real LLR space (diagnostic).
%
% ---------------------------------------------------------------------------
% Pinned Q-format (design.md "Fixed-point format — PINNED"; the reference's
% default_params is the source of truth, replicated here only to emit the
% integer codes the HDL sees, not floats):
%   Core input  W_in  = 9   (Q4.4)            range [-256, 255]
%   Exchange    W_ext = 12   (Q7.4)           range [-2048, 2047]
%   Accumulator W_acc = 14                    range [-8192, 8191]
%   Fractional  F_in  = 4   (LSB = 2^-4 = 0.0625), shared core<->exchange.
%
% ---------------------------------------------------------------------------
% CSV schema (one row per frame; header line first):
%   K        - information block length.
%   max_iter - iteration count (multiple of 0.5); H = round(2*max_iter)
%              half-iterations (even = upper/systematic, odd = lower/
%              interleaved). No early termination (P3).
%   d_a      - 3*(K+4) space-separated signed integers: the quantized channel
%              LLR matrix in COLUMN-MAJOR order (d_a_q(:)' — column 1 rows
%              1..3, then column 2 rows 1..3, ...), each an exchange-grid LSB
%              code in the W_ext=12 range [-2048, 2047]. This is exactly the
%              real-LLR d_a matrix fed to the decoder, quantized once to the
%              F_in=4 grid; the HDL de-muxes + re-saturates it per the loop
%              algebra (design.md §1).
%   c        - K space-separated hard-decision bits (0/1); the REQUIRED gate
%              output. c(k) = (c_a(k) + c_e(k)) < 0.
%   c_a      - K space-separated signed integers (W_ext=12 LSB codes): final
%              cyclic interleaved-extrinsic state. DIAGNOSTIC only.
%   c_e      - K space-separated signed integers (W_ext=12 LSB codes): final
%              upper-decoder cyclic extrinsic. DIAGNOSTIC only.
%
% The inner gate is the K bits in column `c`. c_a / c_e are emitted for
% debug/triage (they let the lane localize a divergence to a half-iteration
% boundary) and are cheap to carry; the cocotb driver may ignore them.
%
% ---------------------------------------------------------------------------
% Vector grid (task 2.2 — kept economical; the fp reference is a scalar loop
% in interpreted Octave and the cycle budget is ~4*H*K, design.md §10):
%   K        in {40, 512, 6144}
%   SNR_dB   in {-1.5, -0.5}
%   max_iter in {2, 8}        (H = 4  small-H regression case;
%                              H = 16 the CONFIRMED default)
%   frames   : 2 per (K, SNR, max_iter) cell for K in {40, 512};
%              1 per cell for K = 6144 (a FEW large-K cases only — the
%              tx_chain_top lesson, a locked roadmap constraint).
%   => K=40 : 2*2*2 = 8 rows ; K=512 : 8 rows ; K=6144 : 2*2*1 = 4 rows
%      Total = 20 rows.
% The SNR points sit inside the characterize_turbo_decoder.m waterfall so the
% vectors exercise a realistic decode (mix of corrected / residual errors),
% not a trivial all-zero or all-correct case.
%
% Idempotent: rand/randn state is reseeded with a fixed seed per run, so
% repeated invocations produce byte-identical output (verify by running
% twice and diffing). Uses only existing helpers (turbo_encoder,
% internal_interleaver) + the P2 full-loop reference
% (fixedpoint_turbo_decoder); no other .m sources modified. Per-row integers
% are emitted with strtrim(sprintf('%d ', ...)) -- matches the established
% constituent_decoder / turbo_encoder / rate_matching CSV style.

repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_root);
addpath(fullfile(repo_root, 'scripts'));

out_dir  = fullfile(repo_root, 'hdl', 'vectors');
out_path = fullfile(out_dir, 'turbo_decoder_top.csv');
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

% --- Pinned Q-format (design.md; reference default_params is source of
%     truth). Replicated here only to emit integer codes for the CSV. ---
W_in  = 9;
W_ext = 12;
W_acc = 14;
F_in  = 4;
in_min  = -2^(W_in  - 1);   in_max  = 2^(W_in  - 1) - 1;   % [-256, 255]
ext_min = -2^(W_ext - 1);   ext_max = 2^(W_ext - 1) - 1;   % [-2048, 2047]
lsb     = 2^(-F_in);

% --- Vector grid (task 2.2). Economical: few large-K cases. ---
K_values   = [40, 512, 6144];
snr_db_set = [-1.5, -0.5];
iter_set   = [2, 8];                 % H = 4 (small-H) and H = 16 (default)
frames_for_K = containers.Map('KeyType', 'double', 'ValueType', 'double');
frames_for_K(40)   = 2;
frames_for_K(512)  = 2;
frames_for_K(6144) = 1;              % a FEW large-K cases only.

% --- Idempotent RNG. Fixed seed => byte-identical CSV across runs. ---
rand('state',  20260522);
randn('state', 20260522);

fid = fopen(out_path, 'w');
if fid < 0
    error('generate_hdl_turbo_decoder_vectors:OpenFailed', ...
        'Cannot open %s', out_path);
end
co = onCleanup(@() fclose(fid));

fprintf(fid, 'K,max_iter,d_a,c,c_a,c_e\n');

n_rows = 0;
for K = K_values
    pii             = internal_interleaver(0:K-1);   % QPP pattern.
    frames_per_cell = frames_for_K(K);

    for snr_db = snr_db_set
        sigma2 = 10 ^ (-snr_db / 10);
        sigma  = sqrt(sigma2);

        for max_iter = iter_set
            for f = 1:frames_per_cell
                c = double(rand(1, K) < 0.5);
                d = turbo_encoder(c, pii);             % 3x(K+4) coded bits
                y = (1 - 2 * d) + sigma * randn(size(d));   % BPSK + AWGN
                d_llr = 2 * y / sigma2;                % channel LLRs (3x(K+4))

                % --- Quantize d_a to the exchange grid (F_in=4) the HDL
                %     loads: round-half-away-from-zero + saturate to W_ext.
                r = d_llr / lsb;
                d_a_q = max(ext_min, min(ext_max, ...
                            sign(r) .* floor(abs(r) + 0.5)));

                % --- Reference fixed-point full-loop decoder on the SAME
                %     real-LLR matrix. Returns hard bits + final c_a/c_e in
                %     real LLR space; we emit the integer LSB codes.
                [c_hat, c_a_real, c_e_real] = ...
                    fixedpoint_turbo_decoder(d_llr, pii, max_iter);
                c_a_q = round(c_a_real / lsb);
                c_e_q = round(c_e_real / lsb);

                % --- Sanity / round-trip ranges. ---
                assert(all(d_a_q(:) >= ext_min & d_a_q(:) <= ext_max), ...
                    'generate_hdl_turbo_decoder_vectors:DaOutOfRange');
                assert(all(c_a_q >= ext_min & c_a_q <= ext_max), ...
                    'generate_hdl_turbo_decoder_vectors:CaOutOfRange');
                assert(all(c_e_q >= ext_min & c_e_q <= ext_max), ...
                    'generate_hdl_turbo_decoder_vectors:CeOutOfRange');
                assert(all(c_hat == 0 | c_hat == 1), ...
                    'generate_hdl_turbo_decoder_vectors:CNotBinary');
                assert(numel(c_hat) == K, ...
                    'generate_hdl_turbo_decoder_vectors:CLengthMismatch');
                assert(numel(d_a_q) == 3 * (K + 4), ...
                    'generate_hdl_turbo_decoder_vectors:DaSizeMismatch');

                % d_a_q(:)' is COLUMN-MAJOR (col1 rows1..3, col2 rows1..3,...).
                fprintf(fid, '%d,%d,%s,%s,%s,%s\n', K, max_iter, ...
                    strtrim(sprintf('%d ', d_a_q(:)')), ...
                    strtrim(sprintf('%d ', c_hat)), ...
                    strtrim(sprintf('%d ', c_a_q)), ...
                    strtrim(sprintf('%d ', c_e_q)));
                n_rows = n_rows + 1;
            end
        end
    end
end

clear co;
fprintf('Wrote %s (%d rows)\n', out_path, n_rows);
