function test_suite = test_constituent_encoder
%TEST_CONSTITUENT_ENCODER
%   Covers openspec/specs/turbo-encoder/spec.md "Requirement: Recursive
%   systematic convolutional constituent encoder".
    try
        test_functions = localfunctions();
    catch
    end
    initTestSuite;
end

function test_output_shape
    K = 40;
    c = round(rand(1, K));
    [z, x] = constituent_encoder(c);
    assertEqual(length(z), K + 3);
    assertEqual(length(x), K + 3);
end

function test_zero_input_produces_zero_output
    for K = [40, 56, 128]
        [z, x] = constituent_encoder(zeros(1, K));
        assertEqual(z, zeros(1, K + 3), sprintf('z not zero for K=%d', K));
        assertEqual(x, zeros(1, K + 3), sprintf('x not zero for K=%d', K));
    end
end

function test_systematic_bits_equal_input
    K = 40;
    c = round(rand(1, K));
    [~, x] = constituent_encoder(c);
    % x(1..K) are the systematic bits; x(K+1..K+3) are termination.
    assertEqual(x(1:K), c);
end

function test_output_is_binary
    K = 64;
    c = round(rand(1, K));
    [z, x] = constituent_encoder(c);
    assertTrue(all(z == 0 | z == 1));
    assertTrue(all(x == 0 | x == 1));
end
