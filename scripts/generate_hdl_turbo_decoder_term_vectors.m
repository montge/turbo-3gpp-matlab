% Golden vectors for the HDL P3 turbo-decoder-termination core
% (turbo_decoder_term top, fixed-point Max-Log-MAP + CRC-aided early
% termination + filler-bit handling + HARQ soft combining,
% TS36.212 §5.1.3.2 / §5.1.2). This is the inner-gate oracle the cocotb lane
% (hdl/sim/turbo_decoder_termination/, authored separately under task 4.x by a
% sibling agent) will bit-exact against. The reference is the stage-1 pair
%   scripts/fixedpoint_turbo_decoder_term.m   (decode + early-term + filler)
%   scripts/fixedpoint_turbo_harq_accumulate.m (HARQ soft buffer)
% layered around the P2 loop EXACTLY as the float oracles turbo_decoder.m /
% turbo_decoding_chain.m do. See
% openspec/changes/add-fpga-turbo-decoder-termination/design.md for the pinned
% Q-format table, the early-stop check schedule, and the filler / HARQ pins.
%
% This generator is ADDITIVE: it emits a NEW CSV
% (hdl/vectors/turbo_decoder_term_top.csv) and does NOT touch the P2 generator
% or hdl/vectors/turbo_decoder_top.csv. It modifies no existing .m source.
%
% ---------------------------------------------------------------------------
% Build recipe per frame (mirrors scripts/characterize_turbo_decoder_term.m so
% the inner-gate vectors live in the same channel/LLR regime as the outer
% characterization):
%   1. Build a code block whose information+CRC bits ARE a valid CRC codeword
%      (CRC24A when crc_sel=1 / single-CB transport-block CRC, CRC24B when
%      crc_sel=2 / per-code-block CRC) using calculate_crc_bits + the
%      get_crc_generator_matrix(6144, ·) generator matrix the reference uses.
%      A correct decode therefore yields a passing CRC and the early-stop
%      genuinely fires (the stop is meaningless if the CRC never passes).
%   2. For a filler case, force the first F_r information bits to 0 (encoder-
%      side filler are known 0), compute the CRC over the WHOLE block, encode,
%      then mark the first F_r systematic LLRs NaN on the channel matrix
%      (turbo_decoding_chain.m's d(1:2,1:F_r)=NaN). The reference maps
%      NaN -> +inf -> MAX_SENT and forces c(filler)=NaN on output.
%   3. QPP interleaver pattern pi = internal_interleaver(0:K-1).
%   4. Turbo-encode via the already-verified turbo_encoder.m -> d (3x(K+4)
%      coded bits, including the termination tail).
%   5. BPSK + AWGN at SNR (Es/N0 dB, Es=1, sigma^2 = 10^(-SNR/10); bit 0 ->
%      +1, bit 1 -> -1).
%   6. Channel LLRs d_llr = 2*y/sigma^2 (standard AWGN BPSK LLR), the 3x(K+4)
%      real-LLR matrix fed to the reference.
%   7. For a HARQ case, build n_retx independent noisy transmissions of the
%      SAME encoded block at a low per-tx SNR; the lane replays the saturating
%      soft accumulate (fixedpoint_turbo_harq_accumulate) over the per-tx
%      quantized matrices, then decodes the combined matrix. The expected
%      outputs here come from running the reference on the fp-combined matrix.
%   8. Quantize each d_llr to the exchange grid (F_in=4 LSB, round-half-away-
%      from-zero + saturate to the W_ext=12 word) -> the integer LSB codes the
%      HDL loads. Filler NaN positions are mapped to +inf BEFORE quantizing so
%      they emit as the saturated MAX_SENT-equivalent ext_max code (+2047).
%   9. Run [c, iterations_performed, c_a, c_e] =
%      fixedpoint_turbo_decoder_term(<d for this case>, pi, max_iter, opts):
%        - non-HARQ : d = the (filler-mapped) real-LLR matrix; opts.G_max set
%                     to the selected CRC matrix (or [] for the no-CRC P2-path
%                     regression rows); opts.filler_bits for the filler case.
%        - HARQ     : d = the fp soft-combined matrix from the accumulate
%                     helper; opts.G_max = CRC24B.
%      -> the K hard bits c (REQUIRED gate), the REQUIRED iterations_performed
%      (the lane asserts the early-stop point), and c_a / c_e (diagnostic).
%
% ---------------------------------------------------------------------------
% Pinned Q-format (design.md "Fixed-point format — PINNED"; the references'
% default_params are the source of truth, replicated here only to emit the
% integer codes the HDL sees, not floats):
%   Core input  W_in   = 9   (Q4.4)            range [-256, 255]
%   Exchange    W_ext  = 12  (Q7.4)            range [-2048, 2047]
%   Accumulator W_acc  = 14                    range [-8192, 8191]
%   HARQ accum  W_harq = 16  (Q11.4)           range [-32768, 32767]
%   Fractional  F_in   = 4   (LSB = 2^-4 = 0.0625), shared core<->exchange.
%   Max retx    N_retx_max = 4 (HARQ).
% Filler -> +inf -> MAX_SENT reuses the P1 sentinel; on the W_ext exchange
% grid that saturates to ext_max = +2047 (the de-mux input format).
%
% ---------------------------------------------------------------------------
% CSV schema (one row per frame; header line first). NEW P3 columns marked *:
%   case_id              * - short label identifying the special case this row
%                            exercises (preloop0 / earlystop / runtomax /
%                            filler / harq / nocrc), for triage. No semantics
%                            for the lane; informational.
%   K                      - information block length.
%   max_iter               - max iteration count (multiple of 0.5);
%                            H = round(2*max_iter) half-iterations. With
%                            crc_sel>0, early termination may stop before H.
%   crc_sel              * - CRC polynomial select for early termination:
%                            0 = no CRC (pure P2 fixed-H path, byte-for-byte
%                                P2 behaviour; iterations_performed = max_iter),
%                            1 = CRC24A (transport-block CRC, single CB C==1),
%                            2 = CRC24B (code-block CRC, C>1).
%   F_r                  * - number of filler bits (the first F_r systematic
%                            positions). 0 when no filler.
%   filler_pos           * - F_r space-separated 1-based systematic indices of
%                            the filler positions (always 1..F_r here; emitted
%                            explicitly so the lane need not assume contiguity).
%                            Empty string when F_r = 0.
%   n_retx               * - number of channel-LLR transmissions stacked in the
%                            d_a field. 1 for all non-HARQ rows; >=2 (<=
%                            N_retx_max) for a HARQ row, where the lane replays
%                            the saturating soft accumulate before decoding.
%   d_a                    - n_retx * 3*(K+4) space-separated signed integers:
%                            n_retx consecutive quantized channel-LLR matrices,
%                            each in COLUMN-MAJOR order (d_a_q(:)' — col 1 rows
%                            1..3, col 2 rows 1..3, ...), each an exchange-grid
%                            LSB code in the W_ext=12 range [-2048, 2047].
%                            For n_retx=1 this is exactly the matrix fed to the
%                            decoder. For n_retx>=2 the lane accumulates the
%                            matrices on the W_harq grid (saturating add,
%                            fixedpoint_turbo_harq_accumulate), re-saturates to
%                            W_ext, and decodes the result. Filler positions
%                            carry the saturated ext_max code (+2047 = the
%                            +inf/MAX_SENT sentinel on the exchange grid).
%   iterations_performed * - REQUIRED early-stop output: the half-iteration
%                            index at which decoding stopped (0 pre-loop,
%                            iteration_index-0.5 post-upper, iteration_index
%                            post-lower), or max_iter if the CRC never passed /
%                            crc_sel=0. Stored as the value (a multiple of 0.5);
%                            the lane may compare round(2*·) as a half-index.
%                            The lane asserts this (early-stop determinism).
%   c                      - K space-separated decoded hard bits, REQUIRED
%                            gate. 0/1 for normal positions; 2 marks a FILLER
%                            position (the reference returns NaN there per
%                            turbo_decoder.m's c(filler_bits)=NaN; 2 is the CSV
%                            integer encoding of that NaN-equivalent "known"
%                            flag — the lane treats 2 as "filler/known", not a
%                            data bit).
%   c_a                    - K space-separated signed integers (W_ext=12 LSB
%                            codes): final cyclic interleaved-extrinsic state.
%                            DIAGNOSTIC only (helps localize a half-iteration
%                            divergence). Filler-NaN -> 0 here (state, not bit).
%   c_e                    - K space-separated signed integers (W_ext=12 LSB
%                            codes): final upper-decoder cyclic extrinsic.
%                            DIAGNOSTIC only.
%
% The inner gate is the K bits in `c` AND the scalar `iterations_performed`.
% c_a / c_e are emitted for debug/triage and the cocotb driver may ignore them.
%
% ---------------------------------------------------------------------------
% Vector grid (tasks 2.1-2.5; kept economical — the fp reference is a scalar
% loop in interpreted Octave and the cycle budget is ~4*H*K, design.md §10).
% The suite EXERCISES every P3 behaviour (design.md Decision 9):
%
%   Special cases (the P3-specific behaviours, all at max_iter=8 / H=16):
%     preloop0  : a crafted near-noiseless K=40 matrix whose COLUMN-MAJOR
%                 first-K signs form a valid CRC24A codeword, so the float-quirk
%                 pre-loop hard decision (c = d_a(1:K)<0 over column-major
%                 linear indices) passes the CRC BEFORE any iteration =>
%                 iterations_performed = 0. (The genuine pre-loop-pass case;
%                 design.md Decision 2 stage-1 pin.)  [crc_sel=1]
%     earlystop : a high-SNR K=512 frame that converges in 1-3 iterations
%                 (iterations_performed small, < max_iter).                [CRC24B]
%     runtomax  : a low-SNR K=512 frame the CRC never satisfies =>
%                 iterations_performed = max_iter = 8.                     [CRC24B]
%     filler    : a K=64 code block with F_r=8 filler bits (first 8 systematic
%                 positions NaN -> +inf), decodes correct, c(filler)=NaN(=2),
%                 CRC handled per the float model.                         [CRC24B]
%     harq      : a K=40 sequence of n_retx=4 transmissions at a low per-tx SNR
%                 that only decodes after soft combining; the lane replays the
%                 saturating accumulate then decodes.                      [CRC24B]
%
%   Plain early-term grid (representative K and a couple of SNRs):
%     K        in {40, 512}
%     SNR_dB   in {0.0, 2.0}   (inside the converging region; mixed iters)
%     => 4 rows, all CRC24B, max_iter=8.
%
%   Regression (no-CRC P2-path) row:
%     nocrc    : one K=40 frame with crc_sel=0 (early termination disabled) so
%                the lane confirms the P3 core degenerates to fixed-H P2
%                behaviour (iterations_performed = max_iter, no CRC check).
%
%   Total = 5 special + 4 grid + 1 nocrc = 10 rows. Few large-K cases (the
%   tx_chain_top lesson, a locked roadmap constraint): the largest K here is
%   512 (no K=6144 — early-term coverage does not need it and the cycle budget
%   stays modest).
%
% Idempotent: rand/randn state is reseeded with a fixed seed per case so
% repeated invocations produce byte-identical output (verify by running twice
% and diffing). Uses only existing helpers (turbo_encoder, internal_interleaver,
% calculate_crc_bits, get_crc_generator_matrix, get_3gpp_crc_polynomial) + the
% stage-1 references (fixedpoint_turbo_decoder_term,
% fixedpoint_turbo_harq_accumulate); no other .m sources modified. Per-row
% integers are emitted with strtrim(sprintf('%d ', ...)) — matches the
% established constituent_decoder / turbo_encoder / rate_matching / P2
% turbo_decoder_top CSV style.

repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_root);
addpath(fullfile(repo_root, 'scripts'));

global approx_star;
approx_star = true;       % Max-Log-MAP (matches the fp reference algorithm).

out_dir  = fullfile(repo_root, 'hdl', 'vectors');
out_path = fullfile(out_dir, 'turbo_decoder_term_top.csv');
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

% --- Pinned Q-format (design.md; references' default_params are source of
%     truth). Replicated here only to emit integer codes for the CSV. ---
W_in  = 9;
W_ext = 12;
W_acc = 14;
F_in  = 4;
in_min  = -2^(W_in  - 1);   in_max  = 2^(W_in  - 1) - 1;   % [-256, 255]
ext_min = -2^(W_ext - 1);   ext_max = 2^(W_ext - 1) - 1;   % [-2048, 2047]
lsb     = 2^(-F_in);

L_crc = 24;
max_iter = 8;             % H = 16 half-iterations (confirmed default).

% --- CRC generator matrices (the SAME the reference slices via
%     calculate_crc_bits' tail-index G_max(end-K+1:end,:)). ---
G24A = get_crc_generator_matrix(6144, get_3gpp_crc_polynomial('CRC24A'));
G24B = get_crc_generator_matrix(6144, get_3gpp_crc_polynomial('CRC24B'));

fid = fopen(out_path, 'w');
if fid < 0
    error('generate_hdl_turbo_decoder_term_vectors:OpenFailed', ...
        'Cannot open %s', out_path);
end
co = onCleanup(@() fclose(fid));

fprintf(fid, ['case_id,K,max_iter,crc_sel,F_r,filler_pos,n_retx,d_a,', ...
              'iterations_performed,c,c_a,c_e\n']);

n_rows = 0;

% ===================================================================== %
% Helper closures (column-major LSB-code quantize; row emit).            %
% ===================================================================== %
quantize = @(d_llr) max(ext_min, min(ext_max, ...
                        sign(d_llr ./ lsb) .* floor(abs(d_llr ./ lsb) + 0.5)));

% c -> CSV integers: NaN (filler) -> 2, else 0/1.
function s = emit_c(c)
    cc = c;
    cc(isnan(cc)) = 2;
    s = strtrim(sprintf('%d ', cc));
end

% ===================================================================== %
% Common per-row sanity + emit.                                          %
% ===================================================================== %
function emit_row(fid, case_id, K, max_iter, crc_sel, filler_pos, ...
                  d_a_q_list, c_hat, iters, c_a_q, c_e_q, ext_min, ext_max)
    n_retx = numel(d_a_q_list);
    F_r    = numel(filler_pos);

    % --- Sanity / range. ---
    for t = 1:n_retx
        dq = d_a_q_list{t};
        assert(all(dq(:) >= ext_min & dq(:) <= ext_max), ...
            'generate_hdl_turbo_decoder_term_vectors:DaOutOfRange');
        assert(numel(dq) == 3 * (K + 4), ...
            'generate_hdl_turbo_decoder_term_vectors:DaSizeMismatch');
    end
    assert(all(c_a_q >= ext_min & c_a_q <= ext_max), ...
        'generate_hdl_turbo_decoder_term_vectors:CaOutOfRange');
    assert(all(c_e_q >= ext_min & c_e_q <= ext_max), ...
        'generate_hdl_turbo_decoder_term_vectors:CeOutOfRange');
    assert(numel(c_hat) == K, ...
        'generate_hdl_turbo_decoder_term_vectors:CLengthMismatch');
    okc = (c_hat == 0 | c_hat == 1 | isnan(c_hat));
    assert(all(okc), ...
        'generate_hdl_turbo_decoder_term_vectors:CNotBinaryOrFiller');
    assert(iters == round(2 * iters) / 2 && iters >= 0, ...
        'generate_hdl_turbo_decoder_term_vectors:ItersNotHalfMultiple');

    % --- Build the d_a field: n_retx column-major matrices, space-joined. ---
    da_parts = cell(1, n_retx);
    for t = 1:n_retx
        dq = d_a_q_list{t};
        da_parts{t} = strtrim(sprintf('%d ', dq(:)'));   % COLUMN-MAJOR
    end
    da_str = strjoin(da_parts, ' ');

    if F_r == 0
        fpos_str = '';
    else
        fpos_str = strtrim(sprintf('%d ', filler_pos));
    end

    fprintf(fid, '%s,%d,%d,%d,%d,%s,%d,%s,%g,%s,%s,%s\n', ...
        case_id, K, max_iter, crc_sel, F_r, fpos_str, n_retx, da_str, ...
        iters, emit_c(c_hat), ...
        strtrim(sprintf('%d ', c_a_q)), strtrim(sprintf('%d ', c_e_q)));
end

% ===================================================================== %
% CASE 1: preloop0 — iterations_performed = 0 (pre-loop CRC pass).        %
%   The float pre-loop hard decision c = double(d_a(1:K) < 0) reads the   %
%   first K elements of the 3x(K+4) matrix in COLUMN-MAJOR order (the     %
%   pinned float quirk, design.md Decision 2). To make that pass the CRC  %
%   before any iteration, we craft a near-noiseless matrix whose first K  %
%   column-major signs realize a valid CRC24A codeword. High magnitude    %
%   (+/-50 real LLR) saturates to ext_max/-ext_max on the W_ext grid, so  %
%   the quantized signs (which the reference uses) match. The remaining   %
%   matrix entries are filled with the genuine encoding of the same       %
%   codeword (so the row is a real near-noiseless decode, not garbage),   %
%   but only the first-K column-major signs decide the pre-loop CRC.       %
% ===================================================================== %
rand('state',  20260523001);
randn('state', 20260523001);
Kp  = 40;
pip = internal_interleaver(0:Kp-1);
% A valid CRC24A codeword of length Kp.
ap  = double(rand(1, Kp - L_crc) < 0.5);
ppp = calculate_crc_bits(ap, G24A);
wp  = [ap, ppp];                          % length Kp, sum(crc)==0
assert(sum(calculate_crc_bits(wp, G24A)) == 0);
% Genuine high-SNR encode of wp -> a realistic near-noiseless channel matrix.
dp_bits = turbo_encoder(wp, pip);
mag_llr = 50;                             % near-noiseless: |LLR| huge
M = (1 - 2 * dp_bits) * mag_llr;          % bit 0 -> +mag, bit 1 -> -mag
% Force the first K COLUMN-MAJOR elements' signs to realize the codeword wp
% (so the float-quirk pre-loop decision is exactly wp and passes the CRC).
for i = 1:Kp
    r   = mod(i - 1, 3) + 1;
    col = floor((i - 1) / 3) + 1;
    if wp(i) == 1
        M(r, col) = -mag_llr;
    else
        M(r, col) =  mag_llr;
    end
end
c0 = double(M(1:Kp) < 0);                 % column-major linear index
assert(isequal(c0, wp) && sum(calculate_crc_bits(c0, G24A)) == 0, ...
    'preloop0: crafted pre-loop decision is not a valid codeword');
[c_hat, iters, c_a_real, c_e_real] = ...
    fixedpoint_turbo_decoder_term(M, pip, max_iter, struct('G_max', G24A));
assert(iters == 0, 'preloop0: expected iterations_performed=0, got %g', iters);
dq = quantize(M);
emit_row(fid, 'preloop0', Kp, max_iter, 1, [], {dq}, c_hat, iters, ...
         round(c_a_real / lsb), round(c_e_real / lsb), ext_min, ext_max);
n_rows = n_rows + 1;

% ===================================================================== %
% CASE 2: earlystop — high SNR, K=512, converges in 1-3 iterations.       %
% ===================================================================== %
rand('state',  20260523002);
randn('state', 20260523002);
Ke   = 512;
pie  = internal_interleaver(0:Ke-1);
snr  = 2.0;  sigma2 = 10 ^ (-snr / 10);  sigma = sqrt(sigma2);
ae   = double(rand(1, Ke - L_crc) < 0.5);
ce   = [ae, calculate_crc_bits(ae, G24B)];
de   = turbo_encoder(ce, pie);
ye   = (1 - 2 * de) + sigma * randn(size(de));
de_llr = 2 * ye / sigma2;
[c_hat, iters, c_a_real, c_e_real] = ...
    fixedpoint_turbo_decoder_term(de_llr, pie, max_iter, struct('G_max', G24B));
assert(iters > 0 && iters < max_iter, ...
    'earlystop: expected 0<iters<max_iter, got %g', iters);
dq = quantize(de_llr);
emit_row(fid, 'earlystop', Ke, max_iter, 2, [], {dq}, c_hat, iters, ...
         round(c_a_real / lsb), round(c_e_real / lsb), ext_min, ext_max);
n_rows = n_rows + 1;

% ===================================================================== %
% CASE 3: runtomax — low SNR, K=512, CRC never passes => iters=max_iter.   %
% ===================================================================== %
rand('state',  20260523003);
randn('state', 20260523003);
Kr   = 512;
pir  = internal_interleaver(0:Kr-1);
snr  = -2.0;  sigma2 = 10 ^ (-snr / 10);  sigma = sqrt(sigma2);
ar   = double(rand(1, Kr - L_crc) < 0.5);
cr   = [ar, calculate_crc_bits(ar, G24B)];
dr   = turbo_encoder(cr, pir);
yr   = (1 - 2 * dr) + sigma * randn(size(dr));
dr_llr = 2 * yr / sigma2;
[c_hat, iters, c_a_real, c_e_real] = ...
    fixedpoint_turbo_decoder_term(dr_llr, pir, max_iter, struct('G_max', G24B));
assert(iters == max_iter, ...
    'runtomax: expected iters=max_iter=%g, got %g', max_iter, iters);
dq = quantize(dr_llr);
emit_row(fid, 'runtomax', Kr, max_iter, 2, [], {dq}, c_hat, iters, ...
         round(c_a_real / lsb), round(c_e_real / lsb), ext_min, ext_max);
n_rows = n_rows + 1;

% ===================================================================== %
% CASE 4: filler — K=64, F_r=8 filler bits (first 8 systematic = NaN).     %
%   Filler are known 0 at the encoder; the channel marks them NaN, the    %
%   reference maps NaN -> +inf -> MAX_SENT, decodes them as known 0, and  %
%   forces c(filler)=NaN on output (emitted as 2 in the CSV).             %
% ===================================================================== %
rand('state',  20260523004);
randn('state', 20260523004);
Kf   = 64;
F_r  = 8;
pif  = internal_interleaver(0:Kf-1);
snr  = 3.0;  sigma2 = 10 ^ (-snr / 10);  sigma = sqrt(sigma2);
af   = double(rand(1, Kf - L_crc) < 0.5);
af(1:F_r) = 0;                              % filler info bits forced 0
cf   = [af, calculate_crc_bits(af, G24B)];
df   = turbo_encoder(cf, pif);
yf   = (1 - 2 * df) + sigma * randn(size(df));
df_llr = 2 * yf / sigma2;
df_llr(1:2, 1:F_r) = NaN;                   % turbo_decoding_chain.m d(1:2,1:F_r)=NaN
filler_pos = 1:F_r;
[c_hat, iters, c_a_real, c_e_real] = ...
    fixedpoint_turbo_decoder_term(df_llr, pif, max_iter, ...
        struct('G_max', G24B, 'filler_bits', filler_pos));
assert(sum(isnan(c_hat)) == F_r, ...
    'filler: expected %d NaN (filler) outputs, got %d', F_r, sum(isnan(c_hat)));
% Non-filler positions must decode correct (the body bits).
assert(isequal(c_hat(F_r+1:end), cf(F_r+1:end)), ...
    'filler: non-filler body bits did not decode correctly');
% Quantize: NaN filler -> +inf -> ext_max (the MAX_SENT sentinel on W_ext).
df_map = df_llr;  df_map(isnan(df_map)) = inf;
dq = quantize(df_map);
assert(all(dq(1, 1:F_r) == ext_max), ...
    'filler: filler systematic positions did not map to ext_max');
emit_row(fid, 'filler', Kf, max_iter, 2, filler_pos, {dq}, c_hat, iters, ...
         round(c_a_real / lsb), round(c_e_real / lsb), ext_min, ext_max);
n_rows = n_rows + 1;

% ===================================================================== %
% CASE 5: harq — K=40, n_retx=4 at a low per-tx SNR; only decodes after    %
%   soft combining. The lane replays fixedpoint_turbo_harq_accumulate over %
%   the 4 quantized matrices, re-saturates to W_ext, then decodes. The     %
%   expected outputs come from the reference run on the fp-combined matrix. %
%   tx1-alone fails (errors > 0); tx4-combined decodes (CRC passes).        %
% ===================================================================== %
rand('state',  20260523005);
randn('state', 20260523005);
Kh   = 40;
n_retx = 4;                                 % == N_retx_max
pih  = internal_interleaver(0:Kh-1);
snr  = -5.0;  sigma2 = 10 ^ (-snr / 10);  sigma = sqrt(sigma2);
ah   = double(rand(1, Kh - L_crc) < 0.5);
ch   = [ah, calculate_crc_bits(ah, G24B)];
dh   = turbo_encoder(ch, pih);

dq_list = cell(1, n_retx);
buf = [];
c_hat = []; iters = NaN; c_a_real = []; c_e_real = [];
errs_tx1 = NaN;
for tx = 1:n_retx
    yh = (1 - 2 * dh) + sigma * randn(size(dh));
    dh_llr = 2 * yh / sigma2;
    dq_list{tx} = quantize(dh_llr);          % what the lane loads / accumulates
    % fp soft-combine then decode (mirrors the lane replay).
    [buf, d_comb] = fixedpoint_turbo_harq_accumulate(buf, dh_llr);
    [c_hat, iters, c_a_real, c_e_real] = ...
        fixedpoint_turbo_decoder_term(d_comb, pih, max_iter, ...
            struct('G_max', G24B));
    if tx == 1
        errs_tx1 = sum(c_hat ~= ch);
    end
end
errs_txN = sum(c_hat ~= ch);
assert(errs_tx1 > 0, ...
    'harq: tx1-alone unexpectedly decoded (need a combine-only case), errs=%d', errs_tx1);
assert(errs_txN == 0, ...
    'harq: tx%d-combined did not decode, errs=%d', n_retx, errs_txN);
assert(iters < max_iter, ...
    'harq: combined decode did not early-terminate (iters=%g)', iters);
emit_row(fid, 'harq', Kh, max_iter, 2, [], dq_list, c_hat, iters, ...
         round(c_a_real / lsb), round(c_e_real / lsb), ext_min, ext_max);
n_rows = n_rows + 1;

% ===================================================================== %
% Plain early-term grid: representative K and SNRs (converging region).    %
% ===================================================================== %
grid_K   = [40, 512];
grid_snr = [0.0, 2.0];
seed_ofs = 20260523100;
for K = grid_K
    pii = internal_interleaver(0:K-1);
    for snr = grid_snr
        seed_ofs = seed_ofs + 1;
        rand('state',  seed_ofs);
        randn('state', seed_ofs);
        sigma2 = 10 ^ (-snr / 10);  sigma = sqrt(sigma2);
        ag = double(rand(1, K - L_crc) < 0.5);
        cg = [ag, calculate_crc_bits(ag, G24B)];
        dg = turbo_encoder(cg, pii);
        yg = (1 - 2 * dg) + sigma * randn(size(dg));
        dg_llr = 2 * yg / sigma2;
        [c_hat, iters, c_a_real, c_e_real] = ...
            fixedpoint_turbo_decoder_term(dg_llr, pii, max_iter, ...
                struct('G_max', G24B));
        dq = quantize(dg_llr);
        emit_row(fid, 'grid', K, max_iter, 2, [], {dq}, c_hat, iters, ...
                 round(c_a_real / lsb), round(c_e_real / lsb), ext_min, ext_max);
        n_rows = n_rows + 1;
    end
end

% ===================================================================== %
% Regression: no-CRC P2 path (crc_sel=0 => early termination disabled).    %
%   Confirms the P3 core degenerates to fixed-H P2 behaviour.             %
% ===================================================================== %
rand('state',  20260523200);
randn('state', 20260523200);
Kn   = 40;
pin  = internal_interleaver(0:Kn-1);
snr  = 0.0;  sigma2 = 10 ^ (-snr / 10);  sigma = sqrt(sigma2);
cn   = double(rand(1, Kn) < 0.5);           % no CRC embedded (not needed)
dn   = turbo_encoder(cn, pin);
yn   = (1 - 2 * dn) + sigma * randn(size(dn));
dn_llr = 2 * yn / sigma2;
[c_hat, iters, c_a_real, c_e_real] = ...
    fixedpoint_turbo_decoder_term(dn_llr, pin, max_iter);   % no opts => no CRC
assert(iters == max_iter, ...
    'nocrc: expected iters=max_iter=%g (no early term), got %g', max_iter, iters);
dq = quantize(dn_llr);
emit_row(fid, 'nocrc', Kn, max_iter, 0, [], {dq}, c_hat, iters, ...
         round(c_a_real / lsb), round(c_e_real / lsb), ext_min, ext_max);
n_rows = n_rows + 1;

clear co;
fprintf('Wrote %s (%d rows)\n', out_path, n_rows);
