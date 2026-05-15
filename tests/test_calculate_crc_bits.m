function test_suite = test_calculate_crc_bits
    % Scenarios covered (crc/spec.md):
    %   Generator matrix sized larger than input (functional aspect),
    %   Generator matrix smaller than input
    try
        test_functions = localfunctions(); %#ok<NASGU>
    catch
    end
    initTestSuite;

function test_zero_input_yields_zero_crc
    % CRC of an all-zero message is always zero (linearity).
    pgen = get_3gpp_crc_polynomial('CRC8');
    G = get_crc_generator_matrix(32, pgen);
    p = calculate_crc_bits(zeros(1, 32), G);
    assertEqual(numel(p), numel(pgen) - 1);
    assertEqual(p, zeros(1, numel(p)));

function test_crc_is_linear_modulo_two
    % CRC(a XOR b) == CRC(a) XOR CRC(b) for binary linear codes.
    pgen = get_3gpp_crc_polynomial('CRC16');
    G = get_crc_generator_matrix(40, pgen);
    a = double(rand(1, 40) > 0.5);
    b = double(rand(1, 40) > 0.5);
    pa = calculate_crc_bits(a, G);
    pb = calculate_crc_bits(b, G);
    pab = calculate_crc_bits(mod(a + b, 2), G);
    assertEqual(pab, mod(pa + pb, 2));

function test_generator_matrix_sized_larger_than_input
    % calculate_crc_bits uses only the last A rows of G_max.
    pgen = get_3gpp_crc_polynomial('CRC24A');
    G_big = get_crc_generator_matrix(50, pgen);
    a = double(rand(1, 16) > 0.5);
    p = calculate_crc_bits(a, G_big);
    assertEqual(numel(p), numel(pgen) - 1);

function test_generator_matrix_smaller_than_input_rejected
    pgen = get_3gpp_crc_polynomial('CRC8');
    G_small = get_crc_generator_matrix(7, pgen);
    a = double(rand(1, 8) > 0.5);
    assertExceptionThrown(@() calculate_crc_bits(a, G_small), ...
        'calculate_crc_bits:generator_too_short');
