function test_suite = test_generate_and_append_crc_bits
    % Scenarios covered (crc/spec.md):
    %   CRC append round-trips with check (append side)
    try
        test_functions = localfunctions(); %#ok<NASGU>
    catch
    end
    initTestSuite;

function test_appended_length_equals_a_plus_l
    pgen = get_3gpp_crc_polynomial('CRC8');
    G = get_crc_generator_matrix(40, pgen);
    a = double(rand(1, 40) > 0.5);
    b = generate_and_append_crc_bits(a, G);
    assertEqual(numel(b), 40 + (numel(pgen) - 1));
    % First A bits are the unchanged information bits.
    assertEqual(b(1:40), a);

function test_appended_crc_satisfies_calculate_crc_bits
    pgen = get_3gpp_crc_polynomial('CRC24A');
    G = get_crc_generator_matrix(64, pgen);
    a = double(rand(1, 64) > 0.5);
    b = generate_and_append_crc_bits(a, G);
    L = numel(pgen) - 1;
    p = calculate_crc_bits(a, G);
    assertEqual(b(end - L + 1:end), p);

function test_crc_append_round_trips_with_check
    pgen = get_3gpp_crc_polynomial('CRC16');
    G = get_crc_generator_matrix(48, pgen);
    a = double(rand(1, 48) > 0.5);
    b = generate_and_append_crc_bits(a, G);
    a_back = check_and_remove_crc_bits(b, G);
    assertEqual(a_back, a);
