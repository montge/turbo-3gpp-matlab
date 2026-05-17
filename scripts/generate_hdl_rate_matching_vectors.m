% Golden vectors for the HDL rate_matching_top integration.
%
% CSV per row: D,N_ref,I_LBRM,rv,E,d,e
%   d : 3*D space-separated bits, column-major (col k -> d(1,k) d(2,k) d(3,k))
%   e : E-char bit string = rate_matching(d, N_ref, I_LBRM, rv, E)
% v1 uses no code-block filler (random d); the structural NaN comes from
% sub-block interleaving inside rate_matching, exactly as in the chain.

repo_root = fileparts(fileparts(mfilename('fullpath')));
out_dir   = fullfile(repo_root, 'hdl', 'vectors');
out_path  = fullfile(out_dir, 'rate_matching.csv');
if ~exist(out_dir, 'dir'); mkdir(out_dir); end

rand('state', 20260519);

% K, N_ref, I_LBRM, rv, E   (D = K+4)
cases = [ ...
   40,    0, 0, 0,  400; ...
   40,    0, 0, 3,  400; ...
  512,    0, 0, 0, 1000; ...
  512,    0, 0, 2, 1000; ...
  512,  800, 1, 0,  600; ...
  512,  800, 1, 3,  600; ...
 6144,    0, 0, 0, 4000; ...
 6144,    0, 0, 2, 4000 ];

fid = fopen(out_path, 'w');
if fid < 0
    error('generate_hdl_rate_matching_vectors:OpenFailed', ...
        'Cannot open %s', out_path);
end
co = onCleanup(@() fclose(fid));
fprintf(fid, 'D,N_ref,I_LBRM,rv,E,d,e\n');

for ci = 1:size(cases, 1)
    K     = cases(ci, 1);
    N_ref = cases(ci, 2);
    I_LBRM= cases(ci, 3);
    rv    = cases(ci, 4);
    E     = cases(ci, 5);
    D     = K + 4;

    d = double(rand(3, D) < 0.5);
    e = rate_matching(d, N_ref, I_LBRM, rv, E);

    d_flat = reshape(d, 1, []);          % column-major: col1 r1..r3, ...

    fprintf(fid, '%d,%d,%d,%d,%d,%s,%s\n', D, N_ref, I_LBRM, rv, E, ...
        strtrim(sprintf('%d ', d_flat)), char(e + '0'));
end

fprintf('Wrote %s\n', out_path);
