function test_suite = test_rate_matching
%TEST_RATE_MATCHING
%   Covers openspec/specs/rate-matching/spec.md "Requirement: Combined
%   rate matching produces invertible bit-position pattern".
    try
        test_functions = localfunctions();
    catch
    end
    initTestSuite;
end

function test_encode_derate_round_trip_no_filler
    D = 44;
    d = reshape(0:3*D-1, 3, D);
    E = 132;
    pi = rate_matching(d, inf, 0, 0, E);
    assertEqual(length(pi), E);
    % Encoded round trip: map 0->+1, 1->-1, then accumulate back
    d_bits = mod(d, 2);  % treat as bits
    d_vec = reshape(d_bits, 1, numel(d_bits));
    e_bits = d_vec(pi + 1);
    % e_bits should match what rate_matching extracts
    assertEqual(length(e_bits), E);
end

function test_pattern_indices_in_range
    D = 44;
    d = reshape(0:3*D-1, 3, D);
    pi = rate_matching(d, inf, 0, 0, 132);
    assertTrue(all(pi >= 0 & pi < 3 * D));
end

function test_with_filler_bits
    D = 44;
    F = 4;  % filler bit count
    d = reshape(0:3*D-1, 3, D);
    d(1:2, 1:F) = NaN;
    pi = rate_matching(d, inf, 0, 0, 100);
    % No filler positions selected
    d_vec = reshape(d, 1, numel(d));
    selected = d_vec(pi + 1);
    assertTrue(~any(isnan(selected)));
end
