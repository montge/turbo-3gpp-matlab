function test_suite = test_turbo_decoder
    % Scenarios covered (turbo-decoder/spec.md):
    %   Decoder shape and iteration count, CRC-based early termination,
    %   Filler bits in output, Half-iteration support,
    %   Invalid iteration count (not multiple of 0.5),
    %   Invalid iteration count (negative value)
    try
        test_functions = localfunctions(); %#ok<NASGU>
    catch
    end
    initTestSuite;

function test_decoder_shape_and_iteration_count
    global approx_star;
    approx_star = false;
    K = 40;
    c = double(rand(1, K) > 0.5);
    pi = internal_interleaver(0:K - 1);
    d = turbo_encoder(c, pi);
    d_a = 1 - 2 * d;
    [c_hat, iter] = turbo_decoder(d_a, pi, 4);
    assertEqual(numel(c_hat), K);
    assertTrue(iter <= 4);

function test_crc_based_early_termination
    % With a valid noise-free LLR mapping and a CRC supplied, the decoder
    % terminates early -- well within max_iterations -- and recovers b.
    global approx_star;
    approx_star = false;
    A = 40;
    pgen = get_3gpp_crc_polynomial('CRC24A');
    G_max = get_crc_generator_matrix(A + numel(pgen) - 1, pgen);
    a = double(rand(1, A) > 0.5);
    b = generate_and_append_crc_bits(a, G_max);
    K = numel(b);
    pi = internal_interleaver(0:K - 1);
    d = turbo_encoder(b, pi);
    d_a = 1 - 2 * d;
    [c_hat, iter] = turbo_decoder(d_a, pi, 8, G_max);
    assertEqual(c_hat, b);
    assertTrue(iter < 8);

function test_filler_bits_in_output
    % NaN-marked filler positions in d_a row 1 must show up as NaN in c.
    global approx_star;
    approx_star = false;
    K = 40;
    F = 8;
    d_a = zeros(3, K + 4);
    d_a(1, 1:F) = NaN;
    pi = internal_interleaver(0:K - 1);
    c_hat = turbo_decoder(d_a, pi, 1);
    assertEqual(numel(c_hat), K);
    assertTrue(all(isnan(c_hat(1:F))));

function test_half_iteration_support
    global approx_star;
    approx_star = false;
    K = 40;
    c = double(rand(1, K) > 0.5);
    pi = internal_interleaver(0:K - 1);
    d = turbo_encoder(c, pi);
    d_a = 1 - 2 * d;
    [c_hat, iter] = turbo_decoder(d_a, pi, 0.5);
    assertEqual(numel(c_hat), K);
    assertEqual(iter, 0.5);

function test_invalid_iteration_count_not_multiple_of_half
    global approx_star;
    approx_star = false;
    K = 40;
    d_a = zeros(3, K + 4);
    pi = internal_interleaver(0:K - 1);
    assertExceptionThrown(@() turbo_decoder(d_a, pi, 0.3), '');
    assertExceptionThrown(@() turbo_decoder(d_a, pi, 1.25), '');

function test_invalid_iteration_count_negative_value
    global approx_star;
    approx_star = false;
    K = 40;
    d_a = zeros(3, K + 4);
    pi = internal_interleaver(0:K - 1);
    assertExceptionThrown(@() turbo_decoder(d_a, pi, -1), '');
    assertExceptionThrown(@() turbo_decoder(d_a, pi, -0.5), '');

function test_d_a_must_have_three_rows
    global approx_star;
    approx_star = false;
    K = 40;
    d_a_bad = zeros(2, K + 4);
    pi = internal_interleaver(0:K - 1);
    assertExceptionThrown(@() turbo_decoder(d_a_bad, pi, 1), '');

function test_pi_length_must_match_k
    global approx_star;
    approx_star = false;
    K = 40;
    d_a = zeros(3, K + 4);
    pi_bad = internal_interleaver(0:K - 1);
    pi_bad = pi_bad(1:end - 1);
    assertExceptionThrown(@() turbo_decoder(d_a, pi_bad, 1), '');
