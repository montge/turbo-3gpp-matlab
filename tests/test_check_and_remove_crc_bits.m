function test_suite = test_check_and_remove_crc_bits
    % Scenarios covered (crc/spec.md):
    %   CRC failure returns empty (and the passing round-trip from
    %   "CRC append round-trips with check")
    try
        test_functions = localfunctions(); %#ok<NASGU>
    catch
    end
    initTestSuite;

function test_crc_append_round_trips_with_check
    pgen = get_3gpp_crc_polynomial('CRC8');
    G = get_crc_generator_matrix(32, pgen);
    a = double(rand(1, 32) > 0.5);
    b = generate_and_append_crc_bits(a, G);
    a_back = check_and_remove_crc_bits(b, G);
    assertEqual(a_back, a);

function test_crc_failure_returns_empty
    pgen = get_3gpp_crc_polynomial('CRC8');
    G = get_crc_generator_matrix(16, pgen);
    a = double(rand(1, 16) > 0.5);
    b = generate_and_append_crc_bits(a, G);
    % Corrupt the last bit (a CRC bit) -- the parity check must now fail.
    b(end) = 1 - b(end);
    a_back = check_and_remove_crc_bits(b, G);
    assertTrue(isempty(a_back));

function test_information_bit_corruption_also_fails
    pgen = get_3gpp_crc_polynomial('CRC16');
    G = get_crc_generator_matrix(24, pgen);
    a = double(rand(1, 24) > 0.5);
    b = generate_and_append_crc_bits(a, G);
    b(3) = 1 - b(3);
    a_back = check_and_remove_crc_bits(b, G);
    assertTrue(isempty(a_back));
