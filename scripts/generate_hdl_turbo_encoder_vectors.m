% Generates golden vectors for the HDL turbo-encoder core.
%
% Each CSV row is one test case:
%   K       - information block length (a supported TS36.212 size)
%   c       - K characters, the natural-order code block bits ('0'/'1')
%   cprime  - K characters, the interleaved block bits, c_prime = c(pi+1)
%   d       - 3*(K+4) characters, the expected turbo_encoder(c,pi) matrix
%             flattened COLUMN-MAJOR: for col = 1..K+4 append d(1,col),
%             d(2,col), d(3,col). This is exactly the order the HDL core
%             streams its output column triples, so the cocotb comparison
%             is a direct sequence equality.
%
% K is taken only from internal_interleaver's supported table (it errors on
% unsupported lengths), so the size set cannot drift from the standard.
% No filler/NaN: v1 encodes concrete full code blocks.

repo_root = fileparts(fileparts(mfilename('fullpath')));
output_dir = fullfile(repo_root, 'hdl', 'vectors');
output_path = fullfile(output_dir, 'turbo_encoder.csv');

if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

% Representative subset of the 188 supported sizes: LTE min, a mid value,
% and the LTE max. internal_interleaver() validates each K.
K_values = [40, 512, 6144];

rand('state', 20260517);

fid = fopen(output_path, 'w');
if fid < 0
    error('generate_hdl_turbo_encoder_vectors:OpenFailed', ...
        'Could not open %s for writing.', output_path);
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, 'K,c,cprime,d\n');

for K = K_values
    pii = internal_interleaver(0:K-1);   % zero-based QPP pattern

    % Deterministic edge cases + pseudo-random blocks.
    blocks = {zeros(1, K), ones(1, K)};
    for r = 1:4
        blocks{end+1} = double(rand(1, K) < 0.5); %#ok<AGROW>
    end

    for bi = 1:numel(blocks)
        c = blocks{bi};
        c_prime = c(pii + 1);
        d = turbo_encoder(c, pii);       % 3 x (K+4), all 0/1 (no filler)

        d_colmajor = reshape(d, 1, []);  % column-major: col1 r1..r3, col2 ...

        fprintf(fid, '%d,%s,%s,%s\n', K, ...
            char(c + '0'), char(c_prime + '0'), char(d_colmajor + '0'));
    end
end

fprintf('Wrote %s\n', output_path);
