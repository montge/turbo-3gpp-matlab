function test_suite = test_get_3gpp_crc_polynomial
    % Scenarios covered (crc/spec.md):
    %   CRC24A polynomial returned, CRC24B polynomial returned,
    %   CRC16 polynomial returned, CRC8 polynomial returned,
    %   Unknown CRC identifier
    try
        test_functions = localfunctions(); %#ok<NASGU>
    catch
    end
    initTestSuite;

function test_crc24a_polynomial_returned
    % TS36.212 Section 5.1.1: g_CRC24A(D) =
    %   D^24 + D^23 + D^18 + D^17 + D^14 + D^11 + D^10 + D^7
    %   + D^6  + D^5  + D^4  + D^3  + D     + 1.
    p = get_3gpp_crc_polynomial('CRC24A');
    assertEqual(numel(p), 25);
    assertEqual(p(1), 1);                       % D^24
    assertEqual(p(end), 1);                     % constant term
    expected_exponents = [24,23,18,17,14,11,10,7,6,5,4,3,1,0];
    assertEqual(sum(p), numel(expected_exponents));
    for e = expected_exponents
        assertEqual(p(end - e), 1);
    end

function test_crc24b_polynomial_returned
    % g_CRC24B(D) = D^24 + D^23 + D^6 + D^5 + D + 1.
    p = get_3gpp_crc_polynomial('CRC24B');
    assertEqual(numel(p), 25);
    expected_exponents = [24,23,6,5,1,0];
    assertEqual(sum(p), numel(expected_exponents));
    for e = expected_exponents
        assertEqual(p(end - e), 1);
    end

function test_crc16_polynomial_returned
    % g_CRC16(D) = D^16 + D^12 + D^5 + 1.
    p = get_3gpp_crc_polynomial('CRC16');
    assertEqual(numel(p), 17);
    expected_exponents = [16,12,5,0];
    assertEqual(sum(p), numel(expected_exponents));
    for e = expected_exponents
        assertEqual(p(end - e), 1);
    end

function test_crc8_polynomial_returned
    % g_CRC8(D) = D^8 + D^7 + D^4 + D^3 + D + 1.
    p = get_3gpp_crc_polynomial('CRC8');
    assertEqual(numel(p), 9);
    expected_exponents = [8,7,4,3,1,0];
    assertEqual(sum(p), numel(expected_exponents));
    for e = expected_exponents
        assertEqual(p(end - e), 1);
    end

function test_unknown_crc_identifier
    assertExceptionThrown(@() get_3gpp_crc_polynomial('CRC32'), '*');
    assertExceptionThrown(@() get_3gpp_crc_polynomial(''), '*');
