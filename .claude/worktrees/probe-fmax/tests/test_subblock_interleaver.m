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
    for idx = [0, 1]
        v = subblock_interleaver(d, idx);
        payload = v(~isnan(v));
        assertEqual(sort(payload), 1:D);
    end

function test_index_2_pads_with_nan
    % Index 2 also produces K_Pi - D filler NaNs.
    D = 100;
    v = subblock_interleaver(1:D, 2);
    assertEqual(sum(isnan(v)), numel(v) - D);

function test_exact_legacy_reference_ordering
    % Backfills the old subblock_int branch's independent ordering check in
    % bounded MOxUnit form.
    for D = [1, 40, 41, 100, 6148]
        d = 0:D - 1;
        for idx = 0:2
            expected = reference_subblock_interleaver(d, idx);
            actual = subblock_interleaver(d, idx);
            assertEqual(isnan(actual), isnan(expected), ...
                sprintf('D=%d idx=%d filler mismatch', D, idx));
            assertEqual(actual(~isnan(actual)), expected(~isnan(expected)), ...
                sprintf('D=%d idx=%d ordering mismatch', D, idx));
        end
    end

function v = reference_subblock_interleaver(d, idx)
    D = length(d);
    C_TC_subblock = 32;
    R_TC_subblock = ceil(D / C_TC_subblock);
    N_D = R_TC_subblock * C_TC_subblock - D;
    y = [nan(1, N_D), d];
    matrix = reshape(y, C_TC_subblock, R_TC_subblock)';
    P = [0 16 8 24 4 20 12 28 2 18 10 26 6 22 14 30 ...
         1 17 9 25 5 21 13 29 3 19 11 27 7 23 15 31];
    K_Pi = R_TC_subblock * C_TC_subblock;
    if idx < 2
        matrix = matrix(:, P + 1);
        v = reshape(matrix, 1, K_Pi);
    else
        k = 0:K_Pi - 1;
        pi = mod(P(floor(k / R_TC_subblock) + 1) + ...
                 C_TC_subblock * mod(k, R_TC_subblock) + 1, K_Pi);
        v = y(pi + 1);
    end
