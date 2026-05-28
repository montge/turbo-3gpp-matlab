function test_suite = test_code_block_segmentation
    % Scenarios covered (code-block-segmentation/spec.md):
    %   Round-trip single-segment (the segmentation side)
    try
        test_functions = localfunctions(); %#ok<NASGU>
    catch
    end
    initTestSuite;

function test_single_segment_no_filler
    % B == K(1) means no filler bits and no per-CB CRC overhead.
    B = 40;
    K_r = [40];
    b = double(rand(1, B) > 0.5);
    c_r = code_block_segmentation(b, K_r, []);
    assertEqual(numel(c_r), 1);
    assertEqual(numel(c_r{1}), 40);
    assertEqual(c_r{1}, b);

function test_single_segment_with_filler_prepends_nan
    % When K_r(1) > B and C == 1 there is no per-CB CRC, so filler = K_r - B
    % bits of NaN are prepended.
    B = 24;
    K_r = [40];
    b = double(rand(1, B) > 0.5);
    c_r = code_block_segmentation(b, K_r, []);
    assertEqual(numel(c_r{1}), 40);
    assertTrue(all(isnan(c_r{1}(1:16))));
    assertEqual(c_r{1}(17:end), b);

function test_round_trip_single_segment
    B = 40;
    K_r = [40];
    b = double(rand(1, B) > 0.5);
    c_r = code_block_segmentation(b, K_r, []);
    b_back = code_block_desegmentation(c_r, B, []);
    assertEqual(b_back, b);

function test_multi_segment_appends_per_block_crc
    % With C > 1 every segment ends with a 24-bit CRC (CRC24B).
    pgen = get_3gpp_crc_polynomial('CRC24B');
    L = numel(pgen) - 1;
    K_r = [6144, 6144];
    B = sum(K_r) - L * numel(K_r);   % no filler
    G = get_crc_generator_matrix(max(K_r), pgen);
    b = double(rand(1, B) > 0.5);
    c_r = code_block_segmentation(b, K_r, G);
    assertEqual(numel(c_r), 2);
    for r = 1:numel(c_r)
        a_r = c_r{r}(1:end - L);
        a_r(isnan(a_r)) = 0;
        p_expected = calculate_crc_bits(a_r, G);
        assertEqual(c_r{r}(end - L + 1:end), p_expected);
    end
