% Golden vectors for the HDL END-TO-END receive chain (rx_chain_top =
% de_rate_matching_top -> turbo_decoder_top, TS36.212 SS5.1.4.1 inverse +
% SS5.1.3.2 decode). This is the stage-5 end-to-end smoke gate the cocotb lane
% (hdl/sim/rx_chain_top/) bit-exacts against: it drives rx_chain_top with the E
% received channel LLRs `e_soft` (+ block params) and asserts the K decoded
% hard bits equal `c` here, bit-for-bit.
%
% The golden `c` is produced by the REFERENCE CHAIN run in sequence on the SAME
% quantized channel LLRs the HDL loads:
%     d_a = fixedpoint_de_rate_matching(e_q, K, F_r, N_ref, I_LBRM, rv, E)
%     c   = fixedpoint_turbo_decoder(d_a, pi, max_iter)
% i.e. the exact two fixed-point references the two sub-cores are individually
% bit-exact against (stage-4 inner gate for the de-rate-match; the P2 turbo
% decoder lane for the decode). Chaining them is the end-to-end proof that the
% rx_chain_top wiring (de-rate-match column stream -> decoder load port) is
% correct -- any wiring/handshake drift surfaces as a hard-bit mismatch.
%
% fixedpoint_de_rate_matching returns d_a in REAL LLR space (filler = +inf,
% erasure = 0); fixedpoint_turbo_decoder consumes exactly that real-LLR d_a
% matrix (it quantizes/de-muxes internally, mapping +inf filler -> the W_EXT
% sentinel just like the decoder HDL). So the chained reference is the literal
% float RX path with the two pinned fixed-point quantizations (W_LLR channel
% grid + the decoder's W_EXT/W_in grids) -- the same arithmetic the HDL does.
%
% ---------------------------------------------------------------------------
% Build recipe per frame (mirrors generate_hdl_de_rate_matching_vectors.m for
% the TX/channel front end, then appends the decode):
%   1. Source the EXACT TX rate-match params for a realistic single code block
%      (C = 1) via turbo_encoding_chain (the 3GPP segment math gives K_r, F_r,
%      E, the QPP internal interleaver).
%   2. Random uncoded block c (K_r bits; the first F_r filler bits forced 0).
%   3. Turbo-encode (turbo_encoder.m) -> d (3x(K_r+4); filler rows 1:2 NaN).
%   4. TX rate-match gather e_tx = d_vec(pi+1) with the SAME length-E
%      permutation the de-rate-match inverts (filler NaN -> known 0 bit).
%   5. BPSK + AWGN at SNR -> received y; channel LLRs e_llr = 2*y/sigma^2.
%   6. Quantize e_llr to the W_LLR (Q3.4) channel grid -> e_soft codes.
%   7. Reference chain on the SAME quantized LLRs e_q = e_soft*lsb:
%        d_a = fixedpoint_de_rate_matching(e_q, ...);  % real-LLR 3x(K+4)
%        c_hat = fixedpoint_turbo_decoder(d_a, pi, max_iter);  % K hard bits
%
% ---------------------------------------------------------------------------
% Pinned fixed-point (design.md Decision 3 + the inherited decoder grids):
%   Received channel LLR  W_LLR = 8   (Q3.4)   e_soft, range [-128, 127].
%   max_iter             = 8   => H = 16 half-iterations -- the rx_chain_top /
%                              turbo_decoder_top MAX_ITERATIONS = 8 DEFAULT, so
%                              the HDL and this CSV decode the SAME H. (A DUT
%                              built with a different MAX_ITERATIONS cannot
%                              bit-exactly reproduce an H=16 frame -- the lane
%                              is run at the default generic.)
%
% ---------------------------------------------------------------------------
% CSV schema (one row per frame; header line first):
%   case_id  - integer 1..N: stable per-frame id for lane triage.
%   K        - information code-block length K_r (the decoder's K; D = K+4).
%   N_ref    - limited-buffer parameter (0 when I_LBRM = 0, UNUSED).
%   I_LBRM   - 0 = full buffer, 1 = limited buffer.
%   rv_idx   - redundancy version 0..3.
%   E        - received length = length(e_soft).
%   F_r      - filler-bit count (rows 1:2 of the first F_r d_a columns).
%   max_iter - decoder iteration count (H = 2*max_iter); 8 here (the default).
%   e_soft   - E space-separated signed ints: received channel LLRs quantized
%              to W_LLR = 8 (Q3.4), range [-128, 127]. The DUT input stream.
%   c        - K space-separated hard bits (0/1): the EXPECTED decoded block,
%              from the reference chain. THE end-to-end gate output.
%
% ---------------------------------------------------------------------------
% Vector grid (a FEW end-to-end frames -- the decoder fp reference is a scalar
% interpreted loop at ~4*H*K, and the HDL decode is ~4*H*K cycles, so keep K
% small and the count low; the deep BER trend is the Octave outer harness
% characterize_rx_chain.m, not this smoke gate):
%   1  baseline   K=40  E=132  rv=0  no wrap, no filler.
%   2  wrap       K=40  E=400  rv=0  E > N_cb soft-combine (>=1 pos accumulates).
%   3  filler     K=48  E=400  rv=0  F_r=4 -> +inf filler exercised end-to-end.
%   4  rv_idx=2   K=40  E=200  rv=2  different k_0.
%   => 4 rows. Each decodes at H=16. SNR chosen inside the waterfall but high
%      enough that the reference decodes the block CLEANLY (the smoke gate wants
%      a deterministic correct bit pattern; the BER-vs-SNR trend is the outer
%      harness). The bit-exact gate does NOT require c == the original block,
%      only c == the reference chain's c (HDL == reference, whatever it decoded).
%
% Idempotent: rand/randn reseeded with a fixed seed; deterministic draw order
% => byte-identical CSV across runs. Uses only existing helpers
% (turbo_encoding_chain, turbo_encoder, rate_matching, internal_interleaver) +
% the stage-1 + P2 references (fixedpoint_de_rate_matching,
% fixedpoint_turbo_decoder); no existing .m source modified.

repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_root);
addpath(fullfile(repo_root, 'scripts'));
if exist(fullfile(repo_root, 'octave_shims'), 'dir')
    addpath(fullfile(repo_root, 'octave_shims'));
end

out_dir  = fullfile(repo_root, 'hdl', 'vectors');
out_path = fullfile(out_dir, 'rx_chain_top.csv');
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

% --- Pinned Q-format (design.md; reference default_params is source of
%     truth). Replicated here only to emit integer codes for the CSV. ---
W_LLR = 8;
F_in  = 4;
lsb     = 2^(-F_in);
llr_min = -2^(W_LLR - 1);   llr_max = 2^(W_LLR - 1) - 1;   % [-128, 127]

MAX_ITER = 8;               % H = 16; the rx_chain_top / decoder DEFAULT generic.

% --- Bounded end-to-end case grid (a few smoke frames). Columns:
%       A (info bits via turbo_encoding_chain), G (rate-match length), rv,
%       SNR_dB, label. All use_chain (I_LBRM = 0, N_ref = 0). ---
cases = { ...
%   A     G     rv  SNR   label
    16,   132,  0,  3.0,  'baseline (K=40, E~N_cb, no wrap)'; ...
    16,   400,  0,  3.0,  'wrap     (K=40, E>N_cb soft-combine)'; ...
    20,   400,  0,  3.0,  'filler   (K=48, F_r=4 +inf end-to-end)'; ...
    16,   200,  2,  3.0,  'rv_idx=2 (K=40, different k_0)' ...
};
n_cases = size(cases, 1);

% --- Idempotent RNG. Fixed seed => byte-identical CSV across runs. ---
rand('state',  20260525);
randn('state', 20260525);

fid = fopen(out_path, 'w');
if fid < 0
    error('generate_hdl_rx_chain_vectors:OpenFailed', 'Cannot open %s', out_path);
end
co = onCleanup(@() fclose(fid));

fprintf(fid, 'case_id,K,N_ref,I_LBRM,rv_idx,E,F_r,max_iter,e_soft,c\n');

n_rows = 0;
for ci = 1:n_cases
    A      = cases{ci, 1};
    G      = cases{ci, 2};
    rv_idx = cases{ci, 3};
    snr_db = cases{ci, 4};
    label  = cases{ci, 5};

    % --- Realistic 3GPP single code block: segment math gives K_r/F_r/E + QPP. ---
    enc = turbo_encoding_chain('A', A, 'G', G, 'rv_idx', rv_idx);
    step(enc, zeros(1, A));
    if enc.C ~= 1
        error('generate_hdl_rx_chain_vectors:multiblock', ...
              'case %d (A=%d,G=%d) gave C=%d (need C=1)', ci, A, G, enc.C);
    end
    K      = enc.K_r(1);
    F_r    = enc.F_r(1);
    E      = enc.E_r(1);
    I_LBRM = 0;
    N_ref  = 0;
    pii_il = enc.internal_interleaver_patterns{1};

    D = K + 4;

    % --- Random block -> turbo encode (filler bits forced 0). ---
    c = double(rand(1, K) < 0.5);
    if F_r > 0
        c(1:F_r) = 0;
    end
    d = turbo_encoder(c, pii_il);            % 3x(K+4); filler rows 1:2 NaN.

    % --- TX rate-match gather using the SAME permutation the inverse uses. ---
    d_vec  = reshape(d, 1, numel(d));
    d_idx  = reshape(0:3*D-1, 3, D);
    d_idx(1:2, 1:F_r) = NaN;
    pii_rm = rate_matching(d_idx, N_ref, I_LBRM, rv_idx, E);   % length-E 0-based
    e_tx   = d_vec(pii_rm + 1);
    tx_bits = e_tx;
    tx_bits(isnan(tx_bits)) = 0;             % filler -> known 0 transmitted bit.

    % --- BPSK + AWGN -> channel LLRs (length E). ---
    sigma2 = 10 ^ (-snr_db / 10);
    sigma  = sqrt(sigma2);
    y      = (1 - 2 * tx_bits) + sigma * randn(1, E);
    e_llr  = 2 * y / sigma2;

    % --- Quantize received LLRs to the W_LLR (Q3.4) grid: the e_soft codes. ---
    r       = e_llr / lsb;
    e_soft  = max(llr_min, min(llr_max, sign(r) .* floor(abs(r) + 0.5)));
    e_q     = double(e_soft) * lsb;

    % --- Reference CHAIN: de-rate-match (real-LLR d_a) -> turbo decode. ---
    d_a   = fixedpoint_de_rate_matching(e_q, K, F_r, N_ref, I_LBRM, rv_idx, E);
    c_hat = fixedpoint_turbo_decoder(d_a, pii_il, MAX_ITER);

    % --- Sanity. ---
    assert(numel(e_soft) == E, 'generate_hdl_rx_chain_vectors:ESizeMismatch');
    assert(all(e_soft >= llr_min & e_soft <= llr_max), ...
        'generate_hdl_rx_chain_vectors:EOutOfRange');
    assert(numel(c_hat) == K, 'generate_hdl_rx_chain_vectors:CLengthMismatch');
    assert(all(c_hat == 0 | c_hat == 1), ...
        'generate_hdl_rx_chain_vectors:CNotBinary');

    n_err = sum(c_hat(:)' ~= c(:)');
    fprintf(fid, '%d,%d,%d,%d,%d,%d,%d,%d,%s,%s\n', ...
        ci, K, N_ref, I_LBRM, rv_idx, E, F_r, MAX_ITER, ...
        strtrim(sprintf('%d ', e_soft)), ...
        strtrim(sprintf('%d ', c_hat)));
    n_rows = n_rows + 1;

    fprintf('  case %d: %-40s K=%-4d E=%-5d F_r=%d rv=%d  ref bit-errors vs tx: %d/%d\n', ...
        ci, label, K, E, F_r, rv_idx, n_err, K);
end

clear co;
fprintf('Wrote %s (%d rows)\n', out_path, n_rows);
