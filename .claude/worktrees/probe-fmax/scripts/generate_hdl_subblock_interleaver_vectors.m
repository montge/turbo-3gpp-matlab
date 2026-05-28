% Golden vectors for the HDL sub-block interleaver address generator.
%
% Each CSV row is one test case:
%   D   - input length
%   idx - sub-block interleaver index (0, 1 or 2)
%   pat - space-separated K_Pi ints = subblock_interleaver(0:D-1, idx),
%         with NaN filler mapped to -1
%
% subblock_interleaver is the only dependency (the golden model). D set
% spans encoder-relevant lengths, an exact multiple of 32 (no filler), and
% non-multiples (filler), for indices {0,2}; an idx=1 row spot-checks that
% index 1 equals index 0 (the helper treats them identically).

repo_root = fileparts(fileparts(mfilename('fullpath')));
out_dir   = fullfile(repo_root, 'hdl', 'vectors');
out_path  = fullfile(out_dir, 'subblock_interleaver.csv');
if ~exist(out_dir, 'dir'); mkdir(out_dir); end

cases = { 44,0; 44,2; 44,1; 64,0; 64,2; 100,0; 100,2; ...
          516,0; 516,2; 6148,0; 6148,2 };

fid = fopen(out_path, 'w');
if fid < 0
    error('generate_hdl_subblock_interleaver_vectors:OpenFailed', ...
        'Cannot open %s', out_path);
end
co = onCleanup(@() fclose(fid));
fprintf(fid, 'D,idx,pat\n');

for ci = 1:size(cases, 1)
    D   = cases{ci, 1};
    idx = cases{ci, 2};
    v   = subblock_interleaver(0:D-1, idx);   % length K_Pi, NaN = filler
    v(isnan(v)) = -1;
    fprintf(fid, '%d,%d,%s\n', D, idx, strtrim(sprintf('%d ', v)));
end

fprintf('Wrote %s\n', out_path);
