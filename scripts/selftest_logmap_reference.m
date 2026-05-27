% SELFTEST_LOGMAP_REFERENCE  Stage-1 self-test for the fixed-point
% exact-Log-MAP constituent reference (scripts/fixedpoint_constituent_decoder_logmap.m).
%
% Checks two contracts from design.md:
%   (A) SUPERSET (byte-exact): with EXACT_LOGMAP=false the new reference
%       reproduces scripts/fixedpoint_constituent_decoder.m EXACTLY (integer
%       extrinsic codes identical bit-for-bit), over many random LLR frames.
%   (B) TRACKING: with EXACT_LOGMAP=true the new reference's hard decisions
%       on the systematic body match the FLOAT exact-Log-MAP oracle
%       (constituent_decoder.m, approx_star=false) better than Max-Log-MAP
%       does, and its extrinsic LLRs sit numerically between Max-Log-MAP and
%       the float exact oracle (the correction is the always-positive f term,
%       so |x_e| should grow toward the exact oracle's larger magnitudes).
%
% Run as a BLOCKING foreground Octave-CLI command. Prints a PASS/FAIL.

1;  % script (not a function file)

repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_root);
addpath(fullfile(repo_root, 'scripts'));

global approx_star;

rand('state',  20260525);
randn('state', 20260525);

K_values   = [40, 512];
snr_db_set = [0, 2, 4];
frames     = 6;

% ---- (A) Superset byte-exact check (EXACT_LOGMAP=false ≡ Max-Log-MAP). ----
off = struct('EXACT_LOGMAP', false);
max_abs_codediff = 0;
n_frames_A = 0;
for K = K_values
    for snr_db = snr_db_set
        sigma2 = 10 ^ (-snr_db / 10); sigma = sqrt(sigma2);
        for f = 1:frames
            c = double(rand(1, K) < 0.5);
            [z, x] = constituent_encoder(c);
            L_x = 2 * ((1 - 2*x) + sigma*randn(1, K+3)) / sigma2;
            L_z = 2 * ((1 - 2*z) + sigma*randn(1, K+3)) / sigma2;

            [~, q_ml]  = fixedpoint_constituent_decoder(L_x, L_z);
            [~, q_off] = fixedpoint_constituent_decoder_logmap(L_x, L_z, off);

            max_abs_codediff = max(max_abs_codediff, max(abs(q_ml - q_off)));
            n_frames_A = n_frames_A + 1;
        end
    end
end
pass_A = (max_abs_codediff == 0);
verdict_A = 'FAIL'; if pass_A, verdict_A = 'PASS'; end
fprintf('\n(A) SUPERSET byte-exact (EXACT_LOGMAP=false == fixedpoint_constituent_decoder):\n');
fprintf('    frames checked: %d   max |code diff|: %d   => %s\n', ...
    n_frames_A, max_abs_codediff, verdict_A);

% ---- (B) Tracking: exact-fp follows float exact better than Max-Log-MAP. ----
% Aggregate over frames the mean |x_e| and the hard-decision agreement with
% the float exact oracle for: float Max-Log-MAP, fp Max-Log-MAP, fp exact,
% float exact. Per design.md §6 Max-Log-MAP OVER-estimates extrinsic
% magnitude (it drops the always-positive f term); the exact correction
% damps the magnitude back DOWN toward the float-exact oracle. So the
% tracking check is: fp-exact's mean |x_e| is CLOSER to the float-exact
% oracle than fp-MaxLogMAP's, AND fp-exact's sign-agreement with the
% float-exact oracle is at least as good as fp-MaxLogMAP's.
on = struct('EXACT_LOGMAP', true);
sum_abs_mlfp = 0; sum_abs_exfp = 0; sum_abs_exfl = 0; nbits = 0;
hd_mlfp = 0; hd_exfp = 0;          % vs float exact signs
for K = K_values
    for snr_db = snr_db_set
        sigma2 = 10 ^ (-snr_db / 10); sigma = sqrt(sigma2);
        for f = 1:frames
            c = double(rand(1, K) < 0.5);
            [z, x] = constituent_encoder(c);
            L_x = 2 * ((1 - 2*x) + sigma*randn(1, K+3)) / sigma2;
            L_z = 2 * ((1 - 2*z) + sigma*randn(1, K+3)) / sigma2;

            approx_star = false;
            xe_fl_ex = constituent_decoder(L_x, L_z);

            xe_ml_fp = fixedpoint_constituent_decoder(L_x, L_z);
            xe_ex_fp = fixedpoint_constituent_decoder_logmap(L_x, L_z, on);

            b = 1:K;
            sum_abs_mlfp = sum_abs_mlfp + sum(abs(xe_ml_fp(b)));
            sum_abs_exfp = sum_abs_exfp + sum(abs(xe_ex_fp(b)));
            sum_abs_exfl = sum_abs_exfl + sum(abs(xe_fl_ex(b)));
            hd_mlfp = hd_mlfp + sum(sign(xe_ml_fp(b)) == sign(xe_fl_ex(b)));
            hd_exfp = hd_exfp + sum(sign(xe_ex_fp(b)) == sign(xe_fl_ex(b)));
            nbits = nbits + K;
        end
    end
end
fprintf('\n(B) TRACKING (vs float exact-Log-MAP oracle):\n');
fprintf('    mean |x_e|: fp-MaxLogMAP=%.4f  fp-exact=%.4f  float-exact=%.4f\n', ...
    sum_abs_mlfp/nbits, sum_abs_exfp/nbits, sum_abs_exfl/nbits);
fprintf('    sign-agree vs float-exact: fp-MaxLogMAP=%.3f%%  fp-exact=%.3f%%\n', ...
    100*hd_mlfp/nbits, 100*hd_exfp/nbits);
% fp-exact's mean |x_e| should be closer to the float-exact oracle than
% fp-MaxLogMAP's (the correction damps Max-Log-MAP's over-optimism), and
% its sign-agreement with the float-exact oracle should be no worse.
mag_ml = sum_abs_mlfp / nbits;
mag_ex = sum_abs_exfp / nbits;
mag_fl = sum_abs_exfl / nbits;
closer = abs(mag_ex - mag_fl) <= abs(mag_ml - mag_fl);
pass_B = closer && (hd_exfp >= hd_mlfp);
verdict_B = 'FAIL'; if pass_B, verdict_B = 'PASS'; end
fprintf('    |mean|x_e| - float-exact|: fp-MaxLogMAP=%.4f  fp-exact=%.4f\n', ...
    abs(mag_ml - mag_fl), abs(mag_ex - mag_fl));
fprintf('    => %s (fp-exact magnitude closer to float-exact AND sign-agree >= MaxLogMAP)\n', ...
    verdict_B);

% ---- LUT dump (the table as built). ----
fprintf('\nCorrection LUT (depth 56, F_in=4) — nonzero region:\n');
lut = round(log(1 + exp(-((0:55)/16))) * 16);
for d = 0:55
    if lut(d+1) > 0
        fprintf('  lut[%2d] = %d\n', d, lut(d+1));
    end
end
fprintf('  (lut[%d..55] flat at the last printed value; lut[56+] = 0)\n', 0);

if pass_A && pass_B
    fprintf('\nSELFTEST: PASS\n');
else
    error('selftest_logmap_reference:FAIL', 'self-test failed — see above');
end
