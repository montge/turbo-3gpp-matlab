function test_suite = test_get_3gpp_encoded_code_block_segment_lengths
%TEST_GET_3GPP_ENCODED_CODE_BLOCK_SEGMENT_LENGTHS
%   Covers "Requirement: Encoded code block segment lengths follow
%   TS36.212 §5.1.4.1.2".
    try
        test_functions = localfunctions();
    catch
    end
    initTestSuite;
end

function test_sum_equals_G_when_evenly_divisible
    G = 24000; C = 2; N_L = 1; Q_m = 2;
    E_r = get_3gpp_encoded_code_block_segment_lengths(G, C, N_L, Q_m);
    assertEqual(sum(E_r), G);
end

function test_equal_length_segments
    G = 24000; C = 2; N_L = 1; Q_m = 2;
    E_r = get_3gpp_encoded_code_block_segment_lengths(G, C, N_L, Q_m);
    assertTrue(all(E_r == G / C));
end

function test_unequal_distribution_when_inputs_are_standards_compliant
    % When G is a multiple of N_L*Q_m (a precondition tracked in issue #3),
    % and G_prime = G/(N_L*Q_m) is not divisible by C, the impl produces a
    % distribution of C-gamma short + gamma long segments. Pick a case
    % where G is a multiple of N_L*Q_m and verify the invariants.
    % G = 1320, C = 7, N_L = 1, Q_m = 2  -> G_prime = 660, mod(660, 7) = 2.
    G = 1320; C = 7; N_L = 1; Q_m = 2;
    E_r = get_3gpp_encoded_code_block_segment_lengths(G, C, N_L, Q_m);
    assertEqual(length(E_r), C);
    assertTrue(all(mod(E_r, N_L * Q_m) == 0));
    distinct = unique(E_r);
    assertTrue(numel(distinct) <= 2);
    if numel(distinct) == 2
        assertEqual(abs(distinct(2) - distinct(1)), N_L * Q_m);
    end
end

function test_each_E_r_is_multiple_of_N_L_times_Q_m
    G = 132; C = 1; N_L = 1; Q_m = 2;
    E_r = get_3gpp_encoded_code_block_segment_lengths(G, C, N_L, Q_m);
    assertTrue(all(mod(E_r, N_L * Q_m) == 0));
end
