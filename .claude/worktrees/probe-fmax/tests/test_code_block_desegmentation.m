function test_suite = test_code_block_desegmentation
    % Scenarios covered (code-block-segmentation/spec.md):
    %   Round-trip multi-segment with CRC, Desegmentation rejects corrupted segment
    try
        test_functions = localfunctions(); %#ok<NASGU>
    catch
    end
    initTestSuite;

function test_round_trip_multi_segment_with_crc
    pgen = get_3gpp_crc_polynomial('CRC24B');
    L = numel(pgen) - 1;
    K_r = [6144, 6144];
    B = sum(K_r) - L * numel(K_r);
    G = get_crc_generator_matrix(max(K_r), pgen);
    b = double(rand(1, B) > 0.5);
    c_r = code_block_segmentation(b, K_r, G);
    b_back = code_block_desegmentation(c_r, B, G);
    assertEqual(b_back, b);

function test_desegmentation_rejects_corrupted_segment
    pgen = get_3gpp_crc_polynomial('CRC24B');
    L = numel(pgen) - 1;
    K_r = [6144, 6144];
    B = sum(K_r) - L * numel(K_r);
    G = get_crc_generator_matrix(max(K_r), pgen);
    b = double(rand(1, B) > 0.5);
    c_r = code_block_segmentation(b, K_r, G);
    % Flip one info bit inside the first segment -- the per-CB CRC must catch it.
    c_r{1}(100) = 1 - c_r{1}(100);
    b_back = code_block_desegmentation(c_r, B, G);
    assertTrue(isempty(b_back));

function test_round_trip_single_segment_no_crc
    B = 64;
    K_r = [64];
    b = double(rand(1, B) > 0.5);
    c_r = code_block_segmentation(b, K_r, []);
    b_back = code_block_desegmentation(c_r, B, []);
    assertEqual(b_back, b);
