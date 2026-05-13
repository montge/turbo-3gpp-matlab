function test_suite = test_get_3gpp_crc_polynomial
%TEST_GET_3GPP_CRC_POLYNOMIAL
%   MOxUnit test for get_3gpp_crc_polynomial.m, covering the scenarios in
%   openspec/specs/crc/spec.md under "Requirement: 3GPP CRC polynomial
%   selection".
    try
        test_functions = localfunctions();
    catch
    end
    initTestSuite;
end

function test_crc24a_polynomial_returned
    p = get_3gpp_crc_polynomial('CRC24A');
    assertEqual(length(p), 25);
    % D^24 + D^23 + D^18 + D^17 + D^14 + D^11 + D^10 + D^7 + D^6 + D^5 + D^4 + D^3 + D + 1
    % bit i (0-indexed from RIGHT) = coefficient of D^i
    expected = zeros(1, 25);
    expected([24, 23, 18, 17, 14, 11, 10, 7, 6, 5, 4, 3, 1, 0] + 1) = 1;
    expected = fliplr(expected);
    assertEqual(p, expected);
end

function test_crc24b_polynomial_returned
    p = get_3gpp_crc_polynomial('CRC24B');
    assertEqual(length(p), 25);
    expected = zeros(1, 25);
    expected([24, 23, 6, 5, 1, 0] + 1) = 1;
    expected = fliplr(expected);
    assertEqual(p, expected);
end

function test_crc16_polynomial_returned
    p = get_3gpp_crc_polynomial('CRC16');
    assertEqual(length(p), 17);
    expected = zeros(1, 17);
    expected([16, 12, 5, 0] + 1) = 1;
    expected = fliplr(expected);
    assertEqual(p, expected);
end

function test_crc8_polynomial_returned
    p = get_3gpp_crc_polynomial('CRC8');
    assertEqual(length(p), 9);
    expected = zeros(1, 9);
    expected([8, 7, 4, 3, 1, 0] + 1) = 1;
    expected = fliplr(expected);
    assertEqual(p, expected);
end

function test_unknown_crc_identifier
    assertExceptionThrown(@() get_3gpp_crc_polynomial('CRC32'), '');
end
