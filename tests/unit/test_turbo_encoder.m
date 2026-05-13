function test_suite = test_turbo_encoder
%TEST_TURBO_ENCODER
%   Covers openspec/specs/turbo-encoder/spec.md "Requirement: Rate-1/3
%   parallel-concatenated turbo encoder".
    try
        test_functions = localfunctions();
    catch
    end
    initTestSuite;
end

function test_output_shape
    K = 40;
    c = round(rand(1, K));
    pi = internal_interleaver(0:K-1);
    d = turbo_encoder(c, pi);
    assertEqual(size(d), [3, K + 4]);
end

function test_interleaver_length_mismatch
    K = 40;
    c = round(rand(1, K));
    bad_pi = 0:34;  % length 35, doesn't match K=40
    assertExceptionThrown(@() turbo_encoder(c, bad_pi), '');
end

function test_filler_bit_propagation
    K = 40;
    c = round(rand(1, K));
    % Put NaN filler in positions 1..3.
    c(1:3) = NaN;
    pi = internal_interleaver(0:K-1);
    d = turbo_encoder(c, pi);
    % Rows 1 and 2 should be NaN at filler positions.
    assertTrue(all(isnan(d(1, 1:3))));
    assertTrue(all(isnan(d(2, 1:3))));
end

function test_zero_input_zero_systematic
    K = 40;
    pi = internal_interleaver(0:K-1);
    d = turbo_encoder(zeros(1, K), pi);
    % First row is systematic = input zeros (for k=0..K-1).
    assertEqual(d(1, 1:K), zeros(1, K));
end
