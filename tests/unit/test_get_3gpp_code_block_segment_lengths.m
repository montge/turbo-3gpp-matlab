function test_suite = test_get_3gpp_code_block_segment_lengths
%TEST_GET_3GPP_CODE_BLOCK_SEGMENT_LENGTHS
%   Covers openspec/specs/code-block-segmentation/spec.md, "Requirement:
%   Code block segment lengths follow TS36.212 §5.1.2".
    try
        test_functions = localfunctions();
    catch
    end
    initTestSuite;
end

function test_single_segment_small_transport_block
    K_r = get_3gpp_code_block_segment_lengths(40);
    assertEqual(K_r, 40);
end

function test_single_segment_up_to_Z
    % For B in [1, 6144], result is a single segment (smallest supported K >= B).
    % Verify a handful of values.
    samples = [1, 39, 40, 41, 100, 500, 511, 512, 1000, 6143, 6144];
    for s = samples
        K_r = get_3gpp_code_block_segment_lengths(s);
        assertEqual(numel(K_r), 1, sprintf('B=%d should give 1 segment', s));
        assertTrue(K_r >= s, sprintf('B=%d: K_r=%d is too small', s, K_r));
    end
end

function test_multi_segment_over_Z
    % B > 6144 should produce C = ceil(B/(6144-24)) segments.
    B = 6145;
    K_r = get_3gpp_code_block_segment_lengths(B);
    assertEqual(numel(K_r), ceil(B / 6120));
    B = 12000;
    K_r = get_3gpp_code_block_segment_lengths(B);
    assertEqual(numel(K_r), ceil(B / 6120));
end

function test_multi_segment_K_in_supported_set
    supported_K = [40:8:511, 512:16:1023, 1024:32:2047, 2048:64:6144];
    K_r = get_3gpp_code_block_segment_lengths(12000);
    for k = K_r
        assertTrue(any(supported_K == k), sprintf('K=%d not in supported set', k));
    end
    % At most two distinct K values
    assertTrue(numel(unique(K_r)) <= 2);
end

function test_invalid_transport_block_size
    assertExceptionThrown(@() get_3gpp_code_block_segment_lengths(0), '');
    assertExceptionThrown(@() get_3gpp_code_block_segment_lengths(-1), '');
end
