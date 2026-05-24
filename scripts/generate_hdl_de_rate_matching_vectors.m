% Golden vectors for the HDL de-rate-matching core (de_rate_matching_top,
% rate DEmatching, TS36.212 §5.1.4.1 inverse). This is the inner-gate oracle
% the cocotb lane (hdl/sim/de_rate_matching_top/, authored separately under
% task 4.x by a sibling agent) will bit-exact against. The reference is
% scripts/fixedpoint_de_rate_matching.m (P4 task 1.x, stage 1) which factors
% the INLINE float de-rate-match (turbo_decoding_chain.m lines 86-93:
% scatter-accumulate via the rate_matching permutation, reshape 3xD,
% d(1:2,1:F_r)=NaN) into a callable fixed-point reference (W_LLR -> W_DRM
% saturating soft-combine, inverse subblock permute, +inf filler / 0 erasure,
% saturate-to-W_EXT output). See
% openspec/changes/add-fpga-rx-chain-integration/design.md (Decision 1
% inverse circular-buffer soft-combine + inverse subblock-interleave;
% Decision 3 fixed-point pins) and tasks.md task 2.
%
% ---------------------------------------------------------------------------
% Build recipe per frame (mirrors scripts/characterize_de_rate_matching.m so
% the inner-gate vectors live in the same channel/LLR regime as the outer
% end-to-end BER characterization):
%   1. Source the EXACT TX rate-match params for a realistic single code
%      block (C = 1): either via turbo_encoding_chain (the 3GPP segment math
%      gives K_r, F_r, E, the internal interleaver) for the I_LBRM = 0 cases,
%      or directly for the limited-buffer (I_LBRM = 1) case.
%   2. Random uncoded block c (K_r bits; the first F_r filler bits forced 0).
%   3. Turbo-encode via the already-verified turbo_encoder.m -> d (3x(K_r+4)
%      coded bits incl. the termination tail; filler rows 1:2 are NaN).
%   4. TX rate-match gather e_tx = d_vec(pi+1) using the SAME length-E
%      permutation pi the de-rate-match inverts (filler NaN -> known 0 bit,
%      the transmitted convention).
%   5. BPSK + AWGN at SNR (Es/N0 dB, Es=1, sigma^2 = 10^(-SNR/10); bit 0 ->
%      +1, bit 1 -> -1) -> received y.
%   6. Channel LLRs e_llr = 2*y/sigma^2 (standard AWGN BPSK LLR), length E.
%   7. Quantize e_llr to the W_LLR (Q3.4) channel grid (round-half-away-from-
%      zero + saturate) -> the integer LSB codes e_soft the HDL loads.
%   8. Run the stage-1 reference
%         [~, d_a_q] = fixedpoint_de_rate_matching(e_q, K_r, F_r, N_ref,
%                                                  I_LBRM, rv_idx, E)
%      on the SAME real-space quantized LLR vector e_q (= e_soft * lsb) ->
%      the expected 3x(K_r+4) d_a matrix as W_EXT (Q7.4) integer codes, with
%      filler positions = the +inf sentinel ext_max (= MAX_SENT) and erasure
%      (untransmitted) positions = 0. This is exactly the d_a the unmodified
%      turbo_decoder_top loads.
%
% Both the e_soft codes and the d_a codes are emitted, so the cocotb lane
% drives the DUT with e_soft and asserts its 3x(K_r+4) output is BIT-FOR-BIT
% the d_a column. The deterministic soft de-rate-match is integer-exact (the
% permutation/accumulate reuses the SAME rate_matching permutation the TX
% gather used; the soft add stays inside the W_DRM range at this grid).
%
% ---------------------------------------------------------------------------
% Pinned fixed-point format (design.md Decision 3; the reference's
% default_params is the source of truth, replicated here only to emit the
% integer codes the HDL sees, not floats):
%   Received channel LLR  W_LLR = 8   (Q3.4)   range [-128, 127]   (e_soft)
%   Soft-combine accum.   W_DRM = 16  (Q11.4)  range [-32768,32767] (internal)
%   Output d_a word       W_EXT = 12  (Q7.4)   range [-2048, 2047] (d_a)
%   Fractional            F_in  = 4   (LSB = 2^-4 = 0.0625), shared across all
%                                     three grids (every grid boundary is a
%                                     pure width/saturate, no rescale).
%   Filler token          +inf -> MAX_SENT = ext_max = 2^(W_EXT-1)-1 = 2047
%                                     (the P1 sentinel; the float oracle's NaN,
%                                     which the decoder maps to +inf).
%   Erasure               0 LSB code (equal-probability; the accumulate zero-
%                                     init for untransmitted w-positions).
%
% ---------------------------------------------------------------------------
% CSV schema (one row per frame; header line first):
%   case_id  - integer 1..N: stable per-frame id for lane triage.
%   K        - information code-block length K_r (the decoder's K; D = K+4).
%   N_ref    - floor(N_IR/C) limited-buffer parameter (TS36.212 §5.1.4.1.2).
%              0 when I_LBRM = 0 (N_ref is then UNUSED; N_cb = K_w = 3*(K+4)).
%   I_LBRM   - 0 = full buffer (UL-SCH etc.; N_cb = K_w), 1 = limited buffer
%              (N_cb = min(N_ref, K_w)). Passed straight to rate_matching.
%   rv_idx   - redundancy version 0..3 (selects the circular-buffer start k_0).
%   E        - encoded/transmitted length = length(e_soft) = the number of
%              received channel LLRs.
%   F_r      - number of filler bits: rows 1:2 of the first F_r columns of d_a
%              are +inf (MAX_SENT). 0 for no filler.
%   e_soft   - E space-separated signed integers: the received channel LLRs
%              quantized to the W_LLR = 8 (Q3.4) grid, range [-128, 127]. The
%              DUT input stream (real LLR = code * 2^-4).
%   d_a      - 3*(K+4) space-separated signed integers: the EXPECTED de-rate-
%              matched soft matrix in COLUMN-MAJOR order (d_a(:)' -- column 1
%              rows 1..3, then column 2 rows 1..3, ...), each a W_EXT = 12
%              (Q7.4) LSB code in [-2048, 2047]. Filler positions hold
%              MAX_SENT = 2047 (+inf); erasure (untransmitted) positions hold
%              0. This is the decoder's exact da_valid/da{1,2,3} load order.
%
% The inner gate is the d_a column (bit-exact). case_id / the params columns
% let the lane reconstruct N_cb / k_0 / the permutation if it cross-checks the
% addressing.
%
% ---------------------------------------------------------------------------
% Vector grid (task 2.2 -- exercises EVERY new behaviour, kept economical;
% the de-rate-match latency is linear in E + 3*K_Pi, the tx_chain_top lesson):
%   1  baseline      K=40   E=132  rv=0  no wrap (maxhit 1)
%   2  wrap          K=40   E=400  rv=0  E > N_cb, a w-pos soft-combines 4 LLRs
%   3  erasure       K=40   E=72   rv=0  E < N_cb, 60 untransmitted -> 0
%   4  filler        K=48   E=400  rv=0  F_r=4 -> rows 1:2 first 4 cols = +inf
%   5  rv_idx=2      K=40   E=200  rv=2  different k_0 (maxhit 2)
%   6  K=512 wrap    K=512  E=2000 rv=0  large-K soft-combine (maxhit 2)
%   7  K=512 fill/er K=512  E=1200 rv=3  F_r=4 + erasure, different rv/k_0
%   8  K=512 LBRM    K=512  E=1200 rv=0  I_LBRM=1 N_ref=800 (limited buffer ->
%                                        N_cb<K_w: BOTH wrap and erasure)
%   9  K=6144        K=6144 E=12000 rv=0 one large-K case (the few-large-K rule)
%   => 9 rows total. K in {40, 48, 512, 6144}; rv in {0, 2, 3}; I_LBRM in {0,1};
%      F_r in {0, 4}; wrap (maxhit>1), no-wrap, and erasure all present.
%
% The SNR points sit inside the characterize_de_rate_matching.m / RX-chain
% waterfall so the LLRs exercise a realistic channel (mix of strong/weak,
% occasional Q3.4-boundary clip), not a trivial all-confident case.
%
% Idempotent: rand/randn state is reseeded with a fixed seed at the top of
% every run, and each frame draws its randomness in a deterministic order, so
% repeated invocations produce BYTE-IDENTICAL output (verify by running twice
% and diffing). Uses only existing helpers (turbo_encoding_chain,
% turbo_encoder, rate_matching, internal/subblock_interleaver, circular_buffer
% via rate_matching) + the stage-1 reference (fixedpoint_de_rate_matching); no
% existing .m source is modified. Per-row integers are emitted with
% strtrim(sprintf('%d ', ...)) -- matches the established
% rate_matching / turbo_decoder_top CSV style.

repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_root);
addpath(fullfile(repo_root, 'scripts'));
% The chain classdefs declare `< matlab.System`; under GNU Octave that base
% class is provided by the octave_shims/ shim (added here, exactly as the
% other HDL/Octave runners do). MATLAB users have the built-in and ignore it.
if exist(fullfile(repo_root, 'octave_shims'), 'dir')
    addpath(fullfile(repo_root, 'octave_shims'));
end

out_dir  = fullfile(repo_root, 'hdl', 'vectors');
out_path = fullfile(out_dir, 'de_rate_matching.csv');
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

% --- Pinned Q-format (design.md; reference default_params is source of
%     truth). Replicated here only to emit integer codes for the CSV. ---
W_LLR = 8;
W_DRM = 16;          %#ok<NASGU>  internal accumulator (documented, not emitted)
W_EXT = 12;
F_in  = 4;
lsb     = 2^(-F_in);
llr_min = -2^(W_LLR - 1);   llr_max = 2^(W_LLR - 1) - 1;   % [-128, 127]
ext_min = -2^(W_EXT - 1);   ext_max = 2^(W_EXT - 1) - 1;   % [-2048, 2047]
MAX_SENT = ext_max;                                        % +inf filler token

% --- Bounded case grid (task 2.2). Columns:
%       use_chain : 1 = derive (K_r, F_r, E) from turbo_encoding_chain via
%                       (A, G); 0 = direct (K, F_r, E) for the LBRM case.
%       A_or_K, G_or_pad, rv, N_ref, I_LBRM, E_direct, F_direct, SNR_dB, label
%     (For use_chain=1 only A, G, rv, SNR are used; N_ref forced 0, I_LBRM 0.) ---
cases = { ...
%  chain  A/K    G/-     rv  N_ref  ILBRM  E(direct) F(direct) SNR   label
    1,    16,    132,    0,  0,     0,     0,        0,        1.0, 'baseline  (K=40,  E~N_cb, no wrap)'; ...
    1,    16,    400,    0,  0,     0,     0,        0,        1.0, 'wrap      (K=40,  E>N_cb soft-combine)'; ...
    1,    16,     72,    0,  0,     0,     0,        0,        1.0, 'erasure   (K=40,  E<N_cb -> 0 positions)'; ...
    1,    20,    400,    0,  0,     0,     0,        0,        1.0, 'filler    (K=48,  F_r=4 rows 1:2 -> +inf)'; ...
    1,    16,    200,    2,  0,     0,     0,        0,        1.0, 'rv_idx=2  (K=40,  different k_0)'; ...
    1,   488,   2000,    0,  0,     0,     0,        0,        0.5, 'K512 wrap (K=512, large-K soft-combine)'; ...
    1,   484,   1200,    3,  0,     0,     0,        0,        0.5, 'K512 f/er (K=512, F_r=4 + erasure, rv=3)'; ...
    0,   512,      0,    0,  800,   1,     1200,     0,        0.5, 'K512 LBRM (K=512, I_LBRM=1 N_ref=800)'; ...
    1,  6120,  12000,    0,  0,     0,     0,        0,       -0.5, 'K6144     (large-K single case)' ...
};
n_cases = size(cases, 1);

% --- Idempotent RNG. Fixed seed => byte-identical CSV across runs. The frame
%     loop draws c then the AWGN noise in a fixed order, so the stream is
%     deterministic. ---
rand('state',  20260524);
randn('state', 20260524);

fid = fopen(out_path, 'w');
if fid < 0
    error('generate_hdl_de_rate_matching_vectors:OpenFailed', ...
        'Cannot open %s', out_path);
end
co = onCleanup(@() fclose(fid));

fprintf(fid, 'case_id,K,N_ref,I_LBRM,rv_idx,E,F_r,e_soft,d_a\n');

n_rows = 0;
for ci = 1:n_cases
    use_chain = cases{ci, 1};
    rv_idx    = cases{ci, 4};
    snr_db    = cases{ci, 9};
    label     = cases{ci, 10};

    if use_chain
        % --- Realistic 3GPP single code block: the segment math gives the
        %     exact K_r / F_r / E and the internal interleaver. C must be 1. ---
        A = cases{ci, 2};
        G = cases{ci, 3};
        enc = turbo_encoding_chain('A', A, 'G', G, 'rv_idx', rv_idx);
        step(enc, zeros(1, A));          % first step runs setupImpl, populating
                                         % the hidden patterns/params.
        if enc.C ~= 1
            error('generate_hdl_de_rate_matching_vectors:multiblock', ...
                  'case %d (A=%d,G=%d) gave C=%d (need C=1)', ci, A, G, enc.C);
        end
        K      = enc.K_r(1);
        F_r    = enc.F_r(1);
        E      = enc.E_r(1);
        I_LBRM = 0;                      % chain path: full buffer.
        N_ref  = 0;                      % UNUSED when I_LBRM=0 (repo CSV
                                         % convention; chain reports Inf).
        pii_il = enc.internal_interleaver_patterns{1};   % QPP pattern.
    else
        % --- Direct limited-buffer (I_LBRM=1) case: params straight from the
        %     grid; build the interleaver from the helper for the chosen K. ---
        K      = cases{ci, 2};
        N_ref  = cases{ci, 5};
        I_LBRM = cases{ci, 6};
        E      = cases{ci, 7};
        F_r    = cases{ci, 8};
        pii_il = internal_interleaver(0:K-1);
    end

    D = K + 4;

    % --- Random block -> turbo encode (filler bits forced 0). ---
    c = double(rand(1, K) < 0.5);
    if F_r > 0
        c(1:F_r) = 0;                    % filler bits are 0 by convention.
    end
    d = turbo_encoder(c, pii_il);        % 3x(K+4); filler rows 1:2 are NaN.

    % --- TX rate-match gather using the SAME permutation the inverse uses.
    %     Build pi from the 3xD 0-based index template with filler NaN,
    %     EXACTLY as fixedpoint_de_rate_matching / turbo_coding_chain do, so
    %     the length-E permutation matches the reference bit-for-bit. ---
    d_vec  = reshape(d, 1, numel(d));
    d_idx  = reshape(0:3*D-1, 3, D);
    d_idx(1:2, 1:F_r) = NaN;
    pii_rm = rate_matching(d_idx, N_ref, I_LBRM, rv_idx, E);   % length-E 0-based
    % (e_tx = d_vec(pii_rm+1) is the rate_matching read; the inverse scatters
    %  the same pi, so the data gather is exact.)
    e_tx = d_vec(pii_rm + 1);

    % Filler (NaN) positions that were selected map to the known transmitted
    % bit 0 (the convention). Row-3 lower-parity is never filler.
    tx_bits = e_tx;
    tx_bits(isnan(tx_bits)) = 0;

    % --- BPSK + AWGN -> channel LLRs (length E). ---
    sigma2 = 10 ^ (-snr_db / 10);        % Es=1 BPSK => sigma^2 = 10^(-SNR/10).
    sigma  = sqrt(sigma2);
    y      = (1 - 2 * tx_bits) + sigma * randn(1, E);   % bit 0 -> +1, 1 -> -1.
    e_llr  = 2 * y / sigma2;             % standard AWGN BPSK LLR.

    % --- Quantize the received LLRs to the W_LLR (Q3.4) channel grid: the
    %     e_soft codes the HDL loads. round-half-away-from-zero + saturate. ---
    r        = e_llr / lsb;
    e_soft   = max(llr_min, min(llr_max, sign(r) .* floor(abs(r) + 0.5)));
    e_q      = double(e_soft) * lsb;     % real-space quantized LLRs.

    % --- Stage-1 reference on the SAME quantized LLRs -> expected d_a (W_EXT
    %     integer codes, filler = MAX_SENT, erasure = 0). ---
    [~, d_a_q] = fixedpoint_de_rate_matching(e_q, K, F_r, N_ref, I_LBRM, ...
                                             rv_idx, E);

    % --- Sanity / round-trip ranges. ---
    assert(numel(e_soft) == E, ...
        'generate_hdl_de_rate_matching_vectors:ESizeMismatch');
    assert(all(e_soft >= llr_min & e_soft <= llr_max), ...
        'generate_hdl_de_rate_matching_vectors:EOutOfRange');
    assert(numel(d_a_q) == 3 * D, ...
        'generate_hdl_de_rate_matching_vectors:DaSizeMismatch');
    assert(all(d_a_q(:) >= ext_min & d_a_q(:) <= ext_max), ...
        'generate_hdl_de_rate_matching_vectors:DaOutOfRange');
    % Filler positions must be exactly the +inf sentinel; row 3 is NOT filler.
    if F_r > 0
        assert(all(d_a_q(1, 1:F_r) == MAX_SENT) ...
            && all(d_a_q(2, 1:F_r) == MAX_SENT), ...
            'generate_hdl_de_rate_matching_vectors:FillerNotSentinel');
    end

    % d_a_q(:)' is COLUMN-MAJOR (col1 rows1..3, col2 rows1..3, ...).
    fprintf(fid, '%d,%d,%d,%d,%d,%d,%d,%s,%s\n', ...
        ci, K, N_ref, I_LBRM, rv_idx, E, F_r, ...
        strtrim(sprintf('%d ', e_soft)), ...
        strtrim(sprintf('%d ', d_a_q(:)')));
    n_rows = n_rows + 1;

    fprintf('  case %d: %-42s K=%-5d E=%-6d F_r=%-3d rv=%d I_LBRM=%d\n', ...
        ci, label, K, E, F_r, rv_idx, I_LBRM);
end

clear co;
fprintf('Wrote %s (%d rows)\n', out_path, n_rows);
