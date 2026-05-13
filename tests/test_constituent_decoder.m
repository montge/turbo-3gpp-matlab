function test_suite = test_constituent_decoder
    % Scenarios covered (turbo-decoder/spec.md):
    %   LLR length mismatch
    try
        test_functions = localfunctions(); %#ok<NASGU>
    catch
    end
    initTestSuite;

function test_llr_length_mismatch
    global approx_star;
    approx_star = false;
    x_a = zeros(1, 10);
    z_a = zeros(1, 11);
    assertExceptionThrown(@() constituent_decoder(x_a, z_a), '');

function test_returns_same_length_as_input
    global approx_star;
    approx_star = false;
    K = 40;
    x_a = zeros(1, K + 3);
    z_a = zeros(1, K + 3);
    x_e = constituent_decoder(x_a, z_a);
    assertEqual(numel(x_e), K + 3);
