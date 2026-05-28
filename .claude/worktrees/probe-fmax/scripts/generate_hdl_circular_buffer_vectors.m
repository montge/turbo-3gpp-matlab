% Golden vectors for the HDL circular-buffer core.
%
% A realistic v is built exactly as rate_matching does (sub-block interleave
% of a random encoder-shaped d, so the structural NaN left-pad is genuine),
% then e = circular_buffer(v, N_ref, I_LBRM, rv_idx, E).
%
% CSV per row:
%   K_Pi,N_ref,I_LBRM,rv_idx,E,v,e
%     v : 3*K_Pi space-separated values, column-major
%         (col k -> v(1,k) v(2,k) v(3,k)), bit 0/1 or -1 for NaN filler
%     e : E-char bit string (circular_buffer output, no NaN)

repo_root = fileparts(fileparts(mfilename('fullpath')));
out_dir   = fullfile(repo_root, 'hdl', 'vectors');
out_path  = fullfile(out_dir, 'circular_buffer.csv');
if ~exist(out_dir, 'dir'); mkdir(out_dir); end

rand('state', 20260518);

% K, N_ref, I_LBRM, rv_idx, E
cases = [ ...
   40,    0, 0, 0,  400; ...   % K_w=192 -> E=400 forces wrap
   40,    0, 0, 1,  400; ...
   40,    0, 0, 2,  400; ...
   40,    0, 0, 3,  400; ...
  512,    0, 0, 0, 1000; ...
  512,    0, 0, 2, 1000; ...
  512,  800, 1, 0,  600; ...   % LBRM: N_cb=min(800,1632)=800 constrains
  512,  800, 1, 3,  600; ...
 6144,    0, 0, 0, 4000; ...
 6144,    0, 0, 2, 4000 ];

fid = fopen(out_path, 'w');
if fid < 0
    error('generate_hdl_circular_buffer_vectors:OpenFailed', ...
        'Cannot open %s', out_path);
end
co = onCleanup(@() fclose(fid));
fprintf(fid, 'K_Pi,N_ref,I_LBRM,rv_idx,E,v,e\n');

for ci = 1:size(cases, 1)
    K     = cases(ci, 1);
    N_ref = cases(ci, 2);
    I_LBRM= cases(ci, 3);
    rv    = cases(ci, 4);
    E     = cases(ci, 5);

    D = K + 4;                              % turbo-encoder column count
    d = double(rand(3, D) < 0.5);           % no code-block filler in v1

    v = [ subblock_interleaver(d(1,:), 0); ...
          subblock_interleaver(d(2,:), 1); ...
          subblock_interleaver(d(3,:), 2) ];
    K_Pi = size(v, 2);

    e = circular_buffer(v, N_ref, I_LBRM, rv, E);

    vc = v;                                 % column-major flatten with -1 NaN
    vc(isnan(vc)) = -1;
    v_flat = reshape(vc, 1, []);            % col1 r1..r3, col2 ...

    fprintf(fid, '%d,%d,%d,%d,%d,%s,%s\n', K_Pi, N_ref, I_LBRM, rv, E, ...
        strtrim(sprintf('%d ', v_flat)), char(e + '0'));
end

fprintf('Wrote %s\n', out_path);
