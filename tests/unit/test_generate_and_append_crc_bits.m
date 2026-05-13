function test_suite = test_generate_and_append_crc_bits
%TEST_GENERATE_AND_APPEND_CRC_BITS
%   Covers the generate-and-append CRC bits flow.
    try
        test_functions = localfunctions();
    catch
    end
    initTestSuite;
end

function test_output_length_equals_A_plus_L
    poly = get_3gpp_crc_polynomial('CRC24A');
    G = get_crc_generator_matrix(40, poly);
    a = round(rand(1, 40));
    b = generate_and_append_crc_bits(a, G);
    assertEqual(length(b), 40 + 24);
end

function test_information_bits_preserved_at_head
    poly = get_3gpp_crc_polynomial('CRC16');
    G = get_crc_generator_matrix(32, poly);
    a = round(rand(1, 32));
    b = generate_and_append_crc_bits(a, G);
    assertEqual(b(1:32), a);
end

function test_appended_bits_match_calculated_crc
    poly = get_3gpp_crc_polynomial('CRC8');
    G = get_crc_generator_matrix(16, poly);
    a = round(rand(1, 16));
    b = generate_and_append_crc_bits(a, G);
    expected_crc = calculate_crc_bits(a, G);
    assertEqual(b(17:24), expected_crc);
end
