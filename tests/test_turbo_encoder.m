function test_suite = test_turbo_encoder
    % Scenarios covered (turbo-encoder/spec.md, turbo encoder requirement):
    %   Output shape, Interleaver length mismatch, Filler bit propagation
    try
        test_functions = localfunctions(); %#ok<NASGU>
    catch
    end
    initTestSuite;

function test_output_shape
    K = 40;
    c = double(rand(1, K) > 0.5);
    pi = internal_interleaver(0:K - 1);
    d = turbo_encoder(c, pi);
    assertEqual(size(d), [3, K + 4]);

function test_zero_input_produces_zero_output
    % All-zero c gives an all-zero d (interleaving zeros yields zeros).
    K = 64;
    pi = internal_interleaver(0:K - 1);
    d = turbo_encoder(zeros(1, K), pi);
    assertEqual(d, zeros(3, K + 4));

function test_interleaver_length_mismatch
    K = 40;
    c = double(rand(1, K) > 0.5);
    pi = internal_interleaver(0:K - 1);
    assertExceptionThrown(@() turbo_encoder(c, pi(1:end - 1)), '');

function test_filler_bit_propagation
    % NaN-valued filler positions in c must remain NaN on the systematic and
    % upper-encoder parity rows of d (positions 1 and 2). The interleaved
    % parity row (position 3) is filled with finite bits because the encoder
    % runs after fillers are zeroed.
    K = 40;
    c = double(rand(1, K) > 0.5);
    F = 8;
    c(1:F) = NaN;
    pi = internal_interleaver(0:K - 1);
    d = turbo_encoder(c, pi);
    assertEqual(size(d), [3, K + 4]);
    assertEqual(isnan(d(1, 1:F)), true(1, F));
    assertEqual(isnan(d(2, 1:F)), true(1, F));
    payload = d(:, F + 1:K);
    assertFalse(any(isnan(payload(:))));
