function test_suite = test_subblock_interleaver
    % Scenarios covered (rate-matching/spec.md):
    %   Output length is a multiple of 32, Unsupported index
    try
        test_functions = localfunctions(); %#ok<NASGU>
    catch
    end
    initTestSuite;

function test_output_length_is_a_multiple_of_32
    for D = [40, 64, 100, 200, 500, 1024]
        for idx = 0:2
            v = subblock_interleaver(0:D - 1, idx);
            assertEqual(mod(numel(v), 32), 0);
            assertTrue(numel(v) >= D);
            assertTrue(numel(v) - D < 32);
        end
    end

function test_unsupported_index
    assertExceptionThrown(@() subblock_interleaver(0:31, 3), '*');
    assertExceptionThrown(@() subblock_interleaver(0:31, -1), '*');

function test_indices_0_and_1_preserve_payload_set
    % Indices 0 and 1 use the column-permutation form. The non-NaN entries
    % of the output are a permutation of the input.
    D = 100;
    d = 1:D;
    v = subblock_interleaver(d, 0);
    payload = v(~isnan(v));
    assertEqual(sort(payload), 1:D);

function test_index_2_pads_with_nan
    % Index 2 also produces K_Pi - D filler NaNs.
    D = 100;
    v = subblock_interleaver(1:D, 2);
    assertEqual(sum(isnan(v)), numel(v) - D);
