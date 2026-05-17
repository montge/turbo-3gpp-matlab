% Golden vectors for the HDL QPP interleaver address generator.
%
% Each CSV row is one test case:
%   K     - supported TS36.212 information block length
%   d0    - (f1 + f2) mod K, derived as pi(1)            [0-based: pi[1]]
%   step  - (2 * f2)  mod K, derived as the 2nd difference of pi
%   pi    - space-separated K integers, internal_interleaver(0:K-1)
%
% d0/step are derived purely from the golden pi (the QPP second difference is
% constant = 2*f2 mod K), so internal_interleaver is the only dependency and
% the constants are guaranteed consistent with the model. K is taken only
% from internal_interleaver's supported table (it errors otherwise), so the
% size set cannot drift from the standard.

repo_root = fileparts(fileparts(mfilename('fullpath')));
output_dir = fullfile(repo_root, 'hdl', 'vectors');
output_path = fullfile(output_dir, 'internal_interleaver.csv');

if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

K_values = [40, 512, 6144];   % LTE min / mid / max; validated by the helper

fid = fopen(output_path, 'w');
if fid < 0
    error('generate_hdl_internal_interleaver_vectors:OpenFailed', ...
        'Could not open %s for writing.', output_path);
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, 'K,d0,step,pi\n');

for K = K_values
    pii = internal_interleaver(0:K-1);     % zero-based QPP pattern, length K

    d0   = mod(pii(2) - pii(1), K);                       % = (f1+f2) mod K
    step = mod((pii(3) - pii(2)) - (pii(2) - pii(1)), K); % = (2*f2) mod K

    fprintf(fid, '%d,%d,%d,%s\n', K, d0, step, ...
        strtrim(sprintf('%d ', pii)));
end

fprintf('Wrote %s\n', output_path);
