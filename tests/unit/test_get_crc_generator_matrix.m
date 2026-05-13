function test_suite = test_get_crc_generator_matrix
%TEST_GET_CRC_GENERATOR_MATRIX
%   Covers scenarios in openspec/specs/crc/spec.md under "Requirement:
%   CRC generator matrix construction".
    try
        test_functions = localfunctions();
    catch
    end
    initTestSuite;
end

function test_generator_matrix_shape
    poly = get_3gpp_crc_polynomial('CRC24A');
    G = get_crc_generator_matrix(40, poly);
    assertEqual(size(G), [40, 24]);
end

function test_generator_matrix_binary
    poly = get_3gpp_crc_polynomial('CRC16');
    G = get_crc_generator_matrix(20, poly);
    assertTrue(all(G(:) == 0 | G(:) == 1));
end

function test_invalid_polynomial_too_short
    % polynomial of length < 2 has P = length(poly) - 1 < 1 -> error
    assertExceptionThrown(@() get_crc_generator_matrix(10, [1]), '');
end
