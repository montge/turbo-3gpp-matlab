repo_root = fileparts(fileparts(mfilename('fullpath')));
output_dir = fullfile(repo_root, 'hdl', 'vectors');
output_path = fullfile(repo_root, 'hdl', 'vectors', 'crc8_parallel.csv');

if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

pgen = get_3gpp_crc_polynomial('CRC8');
generator_matrix = get_crc_generator_matrix(16, pgen);

data_words = uint16([0, 1, hex2dec('00FF'), hex2dec('1234'), ...
    hex2dec('ACE1'), hex2dec('FFFF')]);

fid = fopen(output_path, 'w');
if fid < 0
    error('generate_hdl_crc8_vectors:OpenFailed', ...
        'Could not open %s for writing.', output_path);
end

cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'data_hex,crc_bits\n');

for idx = 1:numel(data_words)
    data_hex = dec2hex(data_words(idx), 4);
    data_bits = double(dec2bin(data_words(idx), 16) == '1');
    crc_bits = calculate_crc_bits(data_bits, generator_matrix);
    fprintf(fid, '%s,%s\n', data_hex, char(crc_bits + '0'));
end

fprintf('Wrote %s\n', output_path);
