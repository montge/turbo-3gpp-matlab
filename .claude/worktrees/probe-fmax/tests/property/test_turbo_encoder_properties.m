function test_suite = test_turbo_encoder_properties
    % Property-based tests for the `turbo-encoder` capability.
    try
        test_functions = localfunctions(); %#ok<NASGU>
    catch
    end
    initTestSuite;

function test_encoder_is_deterministic_and_shape_correct
    rand('state', 3);
    supported = [40:8:511, 512:16:1023, 1024:32:2047, 2048:64:6144];
    sample_count = 16;
    indices = floor(rand(1, sample_count) * numel(supported)) + 1;
    for ii = 1:sample_count
        K = supported(indices(ii));
        c = double(rand(1, K) > 0.5);
        pi = internal_interleaver(0:K - 1);
        d1 = turbo_encoder(c, pi);
        d2 = turbo_encoder(c, pi);
        assertEqual(size(d1), [3, K + 4]);
        assertEqual(d1, d2);
    end
