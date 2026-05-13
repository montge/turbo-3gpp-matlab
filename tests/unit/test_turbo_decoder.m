function test_suite = test_turbo_decoder
%TEST_TURBO_DECODER
%   Covers openspec/specs/turbo-decoder/spec.md "Requirement: Iterative
%   turbo decoder with optional CRC early termination".
    try
        test_functions = localfunctions();
    catch
    end
    initTestSuite;
end

function test_noise_free_recovery
    global approx_star;
    approx_star = false;
    K = 40;
    rng_state = rand('state');
    rand('state', 1);
    c = round(rand(1, K));
    rand('state', rng_state);
    pi = internal_interleaver(0:K-1);
    d = turbo_encoder(c, pi);
    % Map encoded bits to infinite-confidence LLRs: 0 -> +1, 1 -> -1.
    d_llr = 1 - 2 * d;
    c_hat = turbo_decoder(d_llr, pi, 8);
    assertEqual(c_hat, c);
end

function test_invalid_max_iterations_not_multiple_of_0p5
    global approx_star;
    approx_star = false;
    K = 40;
    d = zeros(3, K + 4);
    pi = internal_interleaver(0:K-1);
    assertExceptionThrown(@() turbo_decoder(d, pi, 0.3), '');
end

function test_d_a_wrong_row_count
    global approx_star;
    approx_star = false;
    K = 40;
    pi = internal_interleaver(0:K-1);
    bad_d = zeros(2, K + 4);
    assertExceptionThrown(@() turbo_decoder(bad_d, pi, 8), '');
end

function test_pi_length_mismatch
    global approx_star;
    approx_star = false;
    K = 40;
    d = zeros(3, K + 4);
    bad_pi = 0:30;
    assertExceptionThrown(@() turbo_decoder(d, bad_pi, 8), '');
end

function test_half_iteration_support
    global approx_star;
    approx_star = false;
    K = 40;
    pi = internal_interleaver(0:K-1);
    rand('state', 2);
    c = round(rand(1, K));
    d = turbo_encoder(c, pi);
    d_llr = 1 - 2 * d;
    % max_iterations = 0.5: should complete without error.
    [c_hat, iters] = turbo_decoder(d_llr, pi, 0.5);
    assertEqual(length(c_hat), K);
    assertTrue(iters <= 0.5);
end
