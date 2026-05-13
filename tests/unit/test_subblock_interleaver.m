function test_suite = test_subblock_interleaver
%TEST_SUBBLOCK_INTERLEAVER
%   Covers openspec/specs/rate-matching/spec.md "Requirement: Subblock
%   interleaving with three indices".
    try
        test_functions = localfunctions();
    catch
    end
    initTestSuite;
end

function test_output_length_multiple_of_32
    for idx = 0:2
        for D = [10, 32, 100, 500]
            v = subblock_interleaver(0:D-1, idx);
            assertEqual(mod(length(v), 32), 0, sprintf('D=%d, idx=%d', D, idx));
            assertTrue(length(v) >= D, sprintf('D=%d, idx=%d: too short', D, idx));
            % Smallest multiple of 32 >= D
            assertEqual(length(v), 32 * ceil(D / 32));
        end
    end
end

function test_unsupported_index
    assertExceptionThrown(@() subblock_interleaver(0:31, 3), '');
    assertExceptionThrown(@() subblock_interleaver(0:31, -1), '');
end

function test_filler_propagates
    % If we left-pad with NaN entries, those NaN values should appear in the output.
    D = 50;
    v = subblock_interleaver(0:D-1, 0);
    % Padding adds K_Pi - D = 64 - 50 = 14 NaN entries
    K_Pi = length(v);
    nan_count = sum(isnan(v));
    assertEqual(nan_count, K_Pi - D);
end
