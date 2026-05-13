function test_suite = test_calculate_crc_bits
%TEST_CALCULATE_CRC_BITS
%   Covers scenarios in openspec/specs/crc/spec.md under "Requirement:
%   CRC calculation, append, and verify".
    try
        test_functions = localfunctions();
    catch
    end
    initTestSuite;
end

function test_crc_length_matches_polynomial
    poly = get_3gpp_crc_polynomial('CRC24A');
    G = get_crc_generator_matrix(40, poly);
    a = round(rand(1, 40));
    p = calculate_crc_bits(a, G);
    assertEqual(length(p), 24);
end

function test_crc_is_binary
    poly = get_3gpp_crc_polynomial('CRC16');
    G = get_crc_generator_matrix(32, poly);
    a = round(rand(1, 32));
    p = calculate_crc_bits(a, G);
    assertTrue(all(p == 0 | p == 1));
end

function test_zero_input_produces_zero_crc
    poly = get_3gpp_crc_polynomial('CRC8');
    G = get_crc_generator_matrix(16, poly);
    p = calculate_crc_bits(zeros(1, 16), G);
    assertEqual(p, zeros(1, 8));
end

function test_generator_matrix_larger_than_input
    % Spec: with size(G_max,1) > length(a), only the trailing length(a)
    % rows are used, and the CRC length is size(G_max, 2).
    poly = get_3gpp_crc_polynomial('CRC24A');
    G_max = get_crc_generator_matrix(100, poly);  % rows for up to A=100
    a = round(rand(1, 40));
    p = calculate_crc_bits(a, G_max);
    assertEqual(length(p), 24);
    % Compare against an exactly-sized generator matrix
    G_exact = get_crc_generator_matrix(40, poly);
    p_exact = calculate_crc_bits(a, G_exact);
    assertEqual(p, p_exact);
end
