% Golden vectors for the HDL constituent-decoder core (fixed-point
% Max-Log-MAP Log-BCJR). This is the inner-gate oracle the cocotb lane
% (hdl/sim/constituent_decoder/, authored separately under task 4.x) will
% bit-exact against. The reference is scripts/fixedpoint_constituent_decoder.m
% (task 1.x). See openspec/changes/add-fpga-constituent-decoder/design.md
% for the pinned Q-format table and the realistic-vector recipe (§7).
%
% Build recipe per frame (identical structure to
% scripts/characterize_constituent_decoder.m, so the *same* LLR statistics
% the outer equivalence check used now produce the inner gate):
%   1. Random uncoded block c (K bits, uniform).
%   2. Encode via the already-verified constituent_encoder.m -> (z, x),
%      length K+3 including the trellis-termination tail.
%   3. BPSK + AWGN at SNR (Es/N0 dB, Es=1, sigma^2 = 10^(-SNR/10)).
%   4. Form a-priori LLRs L = 2*y/sigma^2.
%   5. Quantize (L_x, L_z) to the pinned Q-format (W_in=9, F_in=4) via
%      round-half-away-from-zero + saturate to [-256, 255] -- this happens
%      *inside* fixedpoint_constituent_decoder.m but we replicate the
%      quantization here so we can also emit the integer LSB codes the HDL
%      will actually see.
%   6. Run fixedpoint_constituent_decoder(L_x, L_z) -> extrinsic in integer
%      LSB codes (W_xe=18-bit signed); call this x_e_q.
%
% CSV schema (one row per frame):
%   K     - information block length
%   x_a   - K+3 space-separated signed integers in W_in=9-bit range
%           [-256, 255]; these are quantized x_a LSB codes (the systematic
%           a-priori LLRs in Q(4).4 form). HDL receives exactly these.
%   z_a   - K+3 space-separated signed integers in W_in=9-bit range; the
%           quantized parity a-priori LLRs.
%   x_e   - K+3 space-separated signed integers in W_xe=18-bit range
%           [-131072, 131071]; the expected extrinsic LLR codes from the
%           fixed-point reference. The HDL must reproduce these exactly.
%
% Frame count: K in {40, 512, 6144}, SNR in {0, 2, 4} dB, 3 frames per cell
% = 27 rows. Representative K set matches every other HDL lane; the SNR grid
% matches characterize_constituent_decoder.m so the inner-gate vectors live
% in the same regime as the outer equivalence band.
%
% Idempotent: rand/randn state is reseeded with a fixed seed per run, so
% repeated invocations produce byte-identical output. Uses only existing
% helpers (constituent_encoder, fixedpoint_constituent_decoder); no other
% .m sources modified. Per-row integers are emitted with strtrim(sprintf
% ('%d ', ...)) -- matches subblock_interleaver / circular_buffer /
% rate_matching CSVs.

repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_root);
addpath(fullfile(repo_root, 'scripts'));

out_dir  = fullfile(repo_root, 'hdl', 'vectors');
out_path = fullfile(out_dir, 'constituent_decoder.csv');
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

% --- Sweep (matches characterize_constituent_decoder.m's grid). ---
K_values        = [40, 512, 6144];
snr_db_set      = [0, 2, 4];
frames_per_cell = 3;

% --- Pinned Q-format (design.md §4, post-task-1.2). Replicated here only
%     for the quantized x_a/z_a we emit; the reference is the source of
%     truth and does the same saturate-round internally.
W_in  = 9;
F_in  = 4;
in_min = -2^(W_in - 1);
in_max =  2^(W_in - 1) - 1;
lsb    = 2^(-F_in);

% --- Idempotent RNG. Fixed seed => byte-identical CSV across runs.
rand('state',  20260521);
randn('state', 20260521);

fid = fopen(out_path, 'w');
if fid < 0
    error('generate_hdl_constituent_decoder_vectors:OpenFailed', ...
        'Cannot open %s', out_path);
end
co = onCleanup(@() fclose(fid));

fprintf(fid, 'K,x_a,z_a,x_e\n');

n_rows = 0;
for K = K_values
    for snr_db = snr_db_set
        sigma2 = 10 ^ (-snr_db / 10);
        sigma  = sqrt(sigma2);

        for f = 1:frames_per_cell
            c = double(rand(1, K) < 0.5);
            [z, x] = constituent_encoder(c);     % length K+3

            n_x = sigma * randn(1, K + 3);
            n_z = sigma * randn(1, K + 3);
            % BPSK: bit 0 -> +1, bit 1 -> -1 (matches characterization).
            y_x = 1 - 2 * x + n_x;
            y_z = 1 - 2 * z + n_z;
            L_x = 2 * y_x / sigma2;
            L_z = 2 * y_z / sigma2;

            % --- Quantize a-priori LLRs to the W_in/F_in codes the HDL
            % will actually consume (round-half-away-from-zero + saturate).
            % The reference function does this same step internally (its
            % local sat_round = sign.*floor(abs+0.5) then clamp); we redo
            % it here, identically, only so we emit the integer codes the
            % HDL sees, not floats.
            rx = L_x / lsb;
            rz = L_z / lsb;
            x_a_q = max(in_min, min(in_max, sign(rx) .* floor(abs(rx) + 0.5)));
            z_a_q = max(in_min, min(in_max, sign(rz) .* floor(abs(rz) + 0.5)));

            % --- Reference fixed-point decoder. Returns scaled-real x_e
            % AND integer codes; we want the latter for the CSV.
            [~, x_e_q] = fixedpoint_constituent_decoder(L_x, L_z);

            % Sanity: integer ranges.
            assert(all(x_a_q >= in_min & x_a_q <= in_max), ...
                'generate_hdl_constituent_decoder_vectors:XaOutOfRange');
            assert(all(z_a_q >= in_min & z_a_q <= in_max), ...
                'generate_hdl_constituent_decoder_vectors:ZaOutOfRange');
            xe_min = -2^(18 - 1);
            xe_max =  2^(18 - 1) - 1;
            assert(all(x_e_q >= xe_min & x_e_q <= xe_max), ...
                'generate_hdl_constituent_decoder_vectors:XeOutOfRange');

            fprintf(fid, '%d,%s,%s,%s\n', K, ...
                strtrim(sprintf('%d ', x_a_q)), ...
                strtrim(sprintf('%d ', z_a_q)), ...
                strtrim(sprintf('%d ', x_e_q)));
            n_rows = n_rows + 1;
        end
    end
end

clear co;
fprintf('Wrote %s (%d rows)\n', out_path, n_rows);
