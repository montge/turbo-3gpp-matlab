function test_suite = test_code_block_segmentation
%TEST_CODE_BLOCK_SEGMENTATION
%   Covers segmentation round trip with and without code-block CRCs.
    try
        test_functions = localfunctions();
    catch
    end
    initTestSuite;
end

function test_single_segment_no_crc
    % C = 1 -> no CRC, no filler when K_r >= length(b).
    b = round(rand(1, 40));
    K_r = 40;
    c_r = code_block_segmentation(b, K_r, []);
    assertEqual(numel(c_r), 1);
    assertEqual(c_r{1}, b);
end

function test_single_segment_with_filler
    b = round(rand(1, 35));
    K_r = 40;
    c_r = code_block_segmentation(b, K_r, []);
    assertEqual(numel(c_r), 1);
    assertEqual(length(c_r{1}), 40);
    % First 5 bits should be NaN filler
    assertTrue(all(isnan(c_r{1}(1:5))));
    assertEqual(c_r{1}(6:end), b);
end

function test_multi_segment_with_crc_round_trip
    % B > 6144 triggers multi-segment with CRC24B per code block.
    B = 7000;
    b = round(rand(1, B));
    K_r = get_3gpp_code_block_segment_lengths(B);
    poly = get_3gpp_crc_polynomial('CRC24B');
    G = get_crc_generator_matrix(6144, poly);
    c_r = code_block_segmentation(b, K_r, G);
    assertEqual(numel(c_r), numel(K_r));
    % Round-trip via desegmentation
    recovered = code_block_desegmentation(c_r, B, G);
    assertEqual(recovered, b);
end
