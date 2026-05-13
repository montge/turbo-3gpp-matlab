function test_suite = test_get_crc_generator_matrix
    % Scenarios covered (crc/spec.md):
    %   Generator matrix shape, Invalid polynomial,
    %   Generator matrix sized larger than input, Generator matrix smaller than input
    try
        test_functions = localfunctions(); %#ok<NASGU>
    catch
    end
    initTestSuite;

function test_generator_matrix_shape
    A = 40;
    pgen = get_3gpp_crc_polynomial('CRC24A');
    G = get_crc_generator_matrix(A, pgen);
    assertEqual(size(G, 1), A);
    assertEqual(size(G, 2), numel(pgen) - 1);
    assertTrue(all(G(:) == 0 | G(:) == 1));

function test_invalid_polynomial
    % An empty polynomial cannot define a CRC (P < 1) and must be rejected.
    assertExceptionThrown(@() get_crc_generator_matrix(10, []), '');
    % A single-bit polynomial gives P = 0, also invalid.
    assertExceptionThrown(@() get_crc_generator_matrix(10, [1]), '');

function test_generator_matrix_sized_larger_than_input
    % calculate_crc_bits keeps only the last A rows: building a 40-row matrix
    % then computing a 16-bit CRC must give the same result as building a
    % 16-row matrix directly.
    pgen = get_3gpp_crc_polynomial('CRC24A');
    G_big = get_crc_generator_matrix(40, pgen);
    G_small = get_crc_generator_matrix(16, pgen);
    assertEqual(size(G_big), [40, numel(pgen) - 1]);
    assertEqual(G_big(end - 15:end, :), G_small);

function test_generator_matrix_smaller_than_input
    % A = 0: matrix has zero rows.
    pgen = get_3gpp_crc_polynomial('CRC8');
    G = get_crc_generator_matrix(0, pgen);
    assertEqual(size(G, 1), 0);
    assertEqual(size(G, 2), numel(pgen) - 1);
