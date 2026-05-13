function test_suite = test_code_block_desegmentation
%TEST_CODE_BLOCK_DESEGMENTATION
%   Covers desegmentation round trip + CRC corruption detection.
    try
        test_functions = localfunctions();
    catch
    end
    initTestSuite;
end

function test_desegment_corrupt_segment_returns_empty
    % Build a valid multi-segment then flip one bit in one of the CRC fields.
    B = 7000;
    b = round(rand(1, B));
    K_r = get_3gpp_code_block_segment_lengths(B);
    poly = get_3gpp_crc_polynomial('CRC24B');
    G = get_crc_generator_matrix(6144, poly);
    c_r = code_block_segmentation(b, K_r, G);
    % Flip a single bit in the first segment's data area (not in NaN filler).
    first_seg = c_r{1};
    valid_idx = find(~isnan(first_seg), 1, 'first');
    first_seg(valid_idx) = 1 - first_seg(valid_idx);
    c_r{1} = first_seg;
    recovered = code_block_desegmentation(c_r, B, G);
    assertEqual(recovered, []);
end

function test_single_segment_no_crc_round_trip
    b = round(rand(1, 40));
    K_r = 40;
    c_r = code_block_segmentation(b, K_r, []);
    recovered = code_block_desegmentation(c_r, length(b), []);
    assertEqual(recovered, b);
end
