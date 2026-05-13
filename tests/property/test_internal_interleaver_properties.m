function test_suite = test_internal_interleaver_properties
    % Property-based tests for the `internal-interleaver` capability.
    try
        test_functions = localfunctions(); %#ok<NASGU>
    catch
    end
    initTestSuite;

function test_bijection_for_32_random_k_with_fixed_seed
    rand('state', 2);
    supported = [40:8:511, 512:16:1023, 1024:32:2047, 2048:64:6144];
    sample_count = 32;
    indices = floor(rand(1, sample_count) * numel(supported)) + 1;
    for ii = 1:sample_count
        K = supported(indices(ii));
        pi = internal_interleaver(0:K - 1);
        assertEqual(numel(pi), K);
        assertEqual(min(pi), 0);
        assertEqual(max(pi), K - 1);
        assertEqual(numel(unique(pi)), K);
    end
