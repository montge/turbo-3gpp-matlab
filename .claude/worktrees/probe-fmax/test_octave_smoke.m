% test_octave_smoke  Noise-free encode -> decode round trip for GNU Octave.
%
% Runs the default turbo coding chain over a deterministic information block
% with infinite-confidence LLRs and asserts bit-exact recovery. Designed to be
% invoked from a shell as:
%
%     octave --no-gui test_octave_smoke.m
%
% Exits with status 0 on success (printing OCTAVE SMOKE TEST PASSED) and a
% non-zero status on any failure.

repo_root = fileparts(mfilename('fullpath'));
addpath(repo_root);
addpath(fullfile(repo_root, 'octave_shims'));

% Suppress the warnings emitted when Octave re-encodes the latin-1 (c) marks
% in the existing copyright headers; they are noise and would obscure real
% diagnostics.
old_warn_state = warning('off', 'Octave:invalid-utf8');

exit_code = 1;
try
    rand('state', 1);

    A = 16;
    G = 132;

    hEnc = turbo_encoding_chain('A', A, 'G', G, 'Q_m', 2);
    hDec = turbo_decoding_chain('A', A, 'G', G, 'Q_m', 2, 'iterations', 8);

    a = double(rand(1, A) > 0.5);

    f = step(hEnc, a);
    if length(f) ~= G
        error('Encoder produced %d bits, expected G=%d.', length(f), G);
    end

    % Map encoded bits to infinite-confidence LLRs: 0 -> +1, 1 -> -1.
    % The decoder treats negative LLRs as bit=1.
    f_llr = 1 - 2 * f;

    a_hat = step(hDec, f_llr);

    if isempty(a_hat)
        error('Decoder returned empty (CRC failed).');
    end
    if ~isequal(a_hat, a)
        n_errors = sum(a_hat ~= a);
        error('Decoded vector does not match input (%d bit errors).', n_errors);
    end

    fprintf('OCTAVE SMOKE TEST PASSED\n');
    exit_code = 0;
catch err
    fprintf(2, 'OCTAVE SMOKE TEST FAILED: %s\n', err.message);
    if isfield(err, 'stack') && ~isempty(err.stack)
        for s = 1:length(err.stack)
            fprintf(2, '  at %s:%d (%s)\n', err.stack(s).file, ...
                    err.stack(s).line, err.stack(s).name);
        end
    end
end

warning(old_warn_state);
exit(exit_code);
