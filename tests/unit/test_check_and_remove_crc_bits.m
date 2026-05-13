function test_suite = test_check_and_remove_crc_bits
%TEST_CHECK_AND_REMOVE_CRC_BITS
%   Covers the CRC append round-trip scenarios from openspec/specs/crc/spec.md.
    try
        test_functions = localfunctions();
    catch
    end
    initTestSuite;
end

function test_crc_append_round_trips_with_check
    poly = get_3gpp_crc_polynomial('CRC24A');
    G = get_crc_generator_matrix(40, poly);
    a = round(rand(1, 40));
    b = generate_and_append_crc_bits(a, G);
    recovered = check_and_remove_crc_bits(b, G);
    assertEqual(recovered, a);
end

function test_crc_failure_returns_empty
    poly = get_3gpp_crc_polynomial('CRC24A');
    G = get_crc_generator_matrix(40, poly);
    a = round(rand(1, 40));
    b = generate_and_append_crc_bits(a, G);
    % Flip a single bit
    b(1) = 1 - b(1);
    recovered = check_and_remove_crc_bits(b, G);
    assertEqual(recovered, []);
end

function test_round_trip_all_polynomials
    for crc_name = {'CRC24A', 'CRC24B', 'CRC16', 'CRC8'}
        poly = get_3gpp_crc_polynomial(crc_name{1});
        G = get_crc_generator_matrix(50, poly);
        a = round(rand(1, 50));
        b = generate_and_append_crc_bits(a, G);
        recovered = check_and_remove_crc_bits(b, G);
        assertEqual(recovered, a, sprintf('round trip failed for %s', crc_name{1}));
    end
end
