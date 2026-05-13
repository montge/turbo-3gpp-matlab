function test_suite = test_internal_interleaver
%TEST_INTERNAL_INTERLEAVER
%   Covers openspec/specs/internal-interleaver/spec.md scenarios for the QPP
%   interleaver over the 188 supported K values.
    try
        test_functions = localfunctions();
    catch
    end
    initTestSuite;
end

function test_supported_short_block
    % K=40, f1=3, f2=10. Expected pi(i) = mod(3*i + 10*i^2, 40).
    pi = internal_interleaver(0:39);
    expected = mod(3*(0:39) + 10*(0:39).^2, 40);
    assertEqual(pi, expected);
end

function test_supported_largest_block
    % K=6144, f1=263, f2=480.
    pi = internal_interleaver(0:6143);
    expected = mod(263*(0:6143) + 480*(0:6143).^2, 6144);
    assertEqual(pi, expected);
end

function test_permutation_is_bijection
    % For any supported K, multiset of pi(0:K-1) == 0..K-1.
    for K = [40, 56, 256, 1024, 2048, 6144]
        pi = internal_interleaver(0:K-1);
        assertEqual(sort(pi), 0:K-1, sprintf('K=%d is not a bijection', K));
    end
end

function test_unsupported_block_length
    % K=41 is not in the supported set
    assertExceptionThrown(@() internal_interleaver(0:40), '');
end
