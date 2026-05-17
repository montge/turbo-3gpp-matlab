% Golden vectors for the complete HW transmit chain (tx_chain_top):
%   pi = internal_interleaver(0:K-1)
%   d  = turbo_encoder(c, pi)                    % 3 x (K+4)
%   e  = rate_matching(d, N_ref, I_LBRM, rv, E)
%
% CSV per row: K,N_ref,I_LBRM,rv,E,c,e
%   c : K-char code-block bit string
%   e : E-char rate-matched bit string

repo_root = fileparts(fileparts(mfilename('fullpath')));
out_dir   = fullfile(repo_root, 'hdl', 'vectors');
out_path  = fullfile(out_dir, 'tx_chain.csv');
if ~exist(out_dir, 'dir'); mkdir(out_dir); end

rand('state', 20260520);

% K, N_ref, I_LBRM, rv, E
cases = [ ...
   40,    0, 0, 0,  400; ...
   40,    0, 0, 3,  400; ...
   40,  300, 1, 0,  250; ...
  512,    0, 0, 0, 1000; ...
  512,    0, 0, 2, 1000; ...
  512,  800, 1, 3,  600; ...
 6144,    0, 0, 0, 4000 ];

fid = fopen(out_path, 'w');
if fid < 0
    error('generate_hdl_tx_chain_vectors:OpenFailed', ...
        'Cannot open %s', out_path);
end
co = onCleanup(@() fclose(fid));
fprintf(fid, 'K,N_ref,I_LBRM,rv,E,c,e\n');

for ci = 1:size(cases, 1)
    K     = cases(ci, 1);
    N_ref = cases(ci, 2);
    I_LBRM= cases(ci, 3);
    rv    = cases(ci, 4);
    E     = cases(ci, 5);

    c  = double(rand(1, K) < 0.5);
    pii = internal_interleaver(0:K-1);
    d  = turbo_encoder(c, pii);
    e  = rate_matching(d, N_ref, I_LBRM, rv, E);

    fprintf(fid, '%d,%d,%d,%d,%d,%s,%s\n', K, N_ref, I_LBRM, rv, E, ...
        char(c + '0'), char(e + '0'));
end

fprintf('Wrote %s\n', out_path);
