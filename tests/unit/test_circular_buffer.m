function test_suite = test_circular_buffer
%TEST_CIRCULAR_BUFFER
%   Covers openspec/specs/rate-matching/spec.md "Requirement: Circular
%   buffer with redundancy versions and optional LBRM".
    try
        test_functions = localfunctions();
    catch
    end
    initTestSuite;
end

function test_distinct_offsets_no_lbrm
    % I_LBRM = 0, four rv_idx values produce distinct k_0 modulo N_cb.
    K_Pi = 64;
    v = round(rand(3, K_Pi));
    E = 80;
    seen = zeros(1, 4);
    for rv = 0:3
        e = circular_buffer(v, inf, 0, rv, E);
        assertEqual(length(e), E);
        % Use the first 8 bits as a fingerprint of the starting offset.
        seen(rv + 1) = sum(e(1:8) .* 2.^(0:7));
    end
    % Four distinct fingerprints
    assertEqual(length(unique(seen)), 4);
end

function test_output_length_matches_E
    K_Pi = 32;
    v = round(rand(3, K_Pi));
    e = circular_buffer(v, inf, 0, 0, 50);
    assertEqual(length(e), 50);
end

function test_invalid_rv_idx
    K_Pi = 32;
    v = round(rand(3, K_Pi));
    assertExceptionThrown(@() circular_buffer(v, inf, 0, -1, 20), '');
    assertExceptionThrown(@() circular_buffer(v, inf, 0, 4, 20), '');
end

function test_K_Pi_not_multiple_of_32_errors
    v = round(rand(3, 30));
    assertExceptionThrown(@() circular_buffer(v, inf, 0, 0, 20), '');
end

function test_wrong_row_count_errors
    v = round(rand(2, 32));
    assertExceptionThrown(@() circular_buffer(v, inf, 0, 0, 20), '');
end

function test_filler_bits_skipped
    K_Pi = 32;
    v = round(rand(3, K_Pi));
    v(:, 1:5) = NaN;  % Mark first 5 columns as filler
    e = circular_buffer(v, inf, 0, 0, 50);
    assertEqual(length(e), 50);
    assertTrue(~any(isnan(e)));
end
