function test_suite = test_constituent_decoder
%TEST_CONSTITUENT_DECODER
%   Covers openspec/specs/turbo-decoder/spec.md "Requirement: Log-BCJR
%   constituent decoder".
    try
        test_functions = localfunctions();
    catch
    end
    initTestSuite;
end

function test_llr_length_mismatch
    global approx_star;
    approx_star = false;
    x_a = zeros(1, 43);
    z_a = zeros(1, 42);
    assertExceptionThrown(@() constituent_decoder(x_a, z_a), '');
end

function test_output_length_matches_input
    global approx_star;
    approx_star = false;
    K = 40;
    x_a = zeros(1, K + 3);
    z_a = zeros(1, K + 3);
    x_e = constituent_decoder(x_a, z_a);
    assertEqual(length(x_e), K + 3);
end
