function test_suite = test_constituent_encoder
    % Scenarios covered (turbo-encoder/spec.md, constituent-encoder requirement):
    %   Output shape, Zero input produces zero output,
    %   Trellis termination forces zero state
    try
        test_functions = localfunctions(); %#ok<NASGU>
    catch
    end
    initTestSuite;

function test_output_shape
    K = 40;
    c = double(rand(1, K) > 0.5);
    [z, x] = constituent_encoder(c);
    assertEqual(numel(z), K + 3);
    assertEqual(numel(x), K + 3);
    assertEqual(x(1:K), c);

function test_zero_input_produces_zero_output
    % All-zero input never excites the encoder state -- outputs are all zero
    % including the 3 termination tail bits.
    K = 64;
    c = zeros(1, K);
    [z, x] = constituent_encoder(c);
    assertEqual(z, zeros(1, K + 3));
    assertEqual(x, zeros(1, K + 3));

function test_trellis_termination_forces_zero_state
    % After the 3 termination steps the encoder state (s1, s2, s3) must be
    % zero for any input. Replay the trellis locally using the *encoder's
    % own* termination bits (x(K+1..K+3)) so a bug in the encoder's
    % termination logic would actually fail this assertion.
    K = 96;
    c = double(rand(1, K) > 0.5);
    [~, x] = constituent_encoder(c);
    s1 = 0; s2 = 0; s3 = 0;
    for k = 1:K
        s1_plus = mod(c(k) + s2 + s3, 2);
        s2_plus = s1;
        s3_plus = s2;
        s1 = s1_plus; s2 = s2_plus; s3 = s3_plus;
    end
    for k = 1:3
        u = x(K + k);                       % encoder-supplied termination input
        s1_plus = mod(u + s2 + s3, 2);
        s2_plus = s1;
        s3_plus = s2;
        s1 = s1_plus; s2 = s2_plus; s3 = s3_plus;
    end
    assertEqual([s1, s2, s3], [0, 0, 0]);
