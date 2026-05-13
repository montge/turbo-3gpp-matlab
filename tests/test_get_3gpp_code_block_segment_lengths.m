function test_suite = test_get_3gpp_code_block_segment_lengths
    % Scenarios covered (code-block-segmentation/spec.md):
    %   Single-segment small transport block, Single-segment up to Z,
    %   Multi-segment over Z, Invalid transport block size
    try
        test_functions = localfunctions(); %#ok<NASGU>
    catch
    end
    initTestSuite;

function test_single_segment_small_transport_block
    % B <= 6144 yields C = 1; K_r(1) is the smallest supported K >= B.
    K_r = get_3gpp_code_block_segment_lengths(40);
    assertEqual(numel(K_r), 1);
    assertEqual(K_r(1), 40);

function test_single_segment_up_to_z
    % B = 6144 still fits a single segment.
    K_r = get_3gpp_code_block_segment_lengths(6144);
    assertEqual(numel(K_r), 1);
    assertEqual(K_r(1), 6144);

function test_multi_segment_over_z
    % B > 6144 forces segmentation with per-segment CRC overhead (L = 24).
    B = 12000;
    K_r = get_3gpp_code_block_segment_lengths(B);
    assertTrue(numel(K_r) >= 2);
    % Each segment is at most 6144 bits.
    assertTrue(all(K_r <= 6144));
    % Total capacity must cover B plus the per-segment 24-bit CRCs.
    assertTrue(sum(K_r) >= B + 24 * numel(K_r));
    % Per-segment lengths come from the supported set.
    supported = [40:8:511, 512:16:1023, 1024:32:2047, 2048:64:6144];
    for v = K_r
        assertFalse(isempty(find(supported == v, 1)));
    end

function test_invalid_transport_block_size
    % Both zero and negative B must be rejected.
    assertExceptionThrown(@() get_3gpp_code_block_segment_lengths(0), '*');
    assertExceptionThrown(@() get_3gpp_code_block_segment_lengths(-1), '*');
