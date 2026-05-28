function test_suite = test_code_block_segmentation_properties
    % Property-based tests for the `code-block-segmentation` capability.
    try
        test_functions = localfunctions(); %#ok<NASGU>
    catch
    end
    initTestSuite;

function test_segmentation_round_trip_for_random_b_including_b_greater_than_6144
    rand('state', 6);
    sample_count = 32;
    % Span both the single-segment (B <= 6144) and multi-segment regimes.
    Bs = [40, 56, 96, 200, 500, 1024, 2048, 4096, 6000, 6144, ...
          6500, 8000, 10000, 12000, 16000, 20000, 24000, 30000];
    pgen = get_3gpp_crc_polynomial('CRC24B');
    L = numel(pgen) - 1;
    G = get_crc_generator_matrix(6144, pgen);
    for ii = 1:sample_count
        B = Bs(mod(ii - 1, numel(Bs)) + 1);
        K_r = get_3gpp_code_block_segment_lengths(B);
        b = double(rand(1, B) > 0.5);
        if numel(K_r) > 1
            c_r = code_block_segmentation(b, K_r, G);
            b_back = code_block_desegmentation(c_r, B, G);
        else
            c_r = code_block_segmentation(b, K_r, []);
            b_back = code_block_desegmentation(c_r, B, []);
        end
        assertEqual(b_back, b, sprintf('B=%d round-trip failed', B));
        assertEqual(numel(c_r), numel(K_r));
        for r = 1:numel(K_r)
            assertEqual(numel(c_r{r}), K_r(r));
        end
        % Filler bits land in segment 1 only.
        if numel(K_r) >= 1
            filler_count = sum(isnan(c_r{1}));
            if numel(K_r) > 1
                expected_F = sum(K_r) - (B + numel(K_r) * L);
            else
                expected_F = sum(K_r) - B;
            end
            assertEqual(filler_count, expected_F);
        end
    end
