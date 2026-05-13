function test_suite = test_turbo_decoding_chain
    % Scenarios covered (coding-chain/spec.md):
    %   Decoding-chain constructor accepts name-value pairs,
    %   Noise-free round trip recovers information bits,
    %   HARQ accumulation, CRC failure returns empty,
    %   Decode rejects wrong-length input
    try
        test_functions = localfunctions(); %#ok<NASGU>
    catch
    end
    initTestSuite;

function test_decoding_chain_constructor_accepts_name_value_pairs
    % Guards against the historical NRLDPCDecoder typo that silently
    % dropped construction arguments under Octave.
    obj = turbo_decoding_chain('A', 8000, 'G', 24000, 'Q_m', 2, ...
                               'iterations', 16, 'I_HARQ', 1);
    assertEqual(obj.A, 8000);
    assertEqual(obj.G, 24000);
    assertEqual(obj.Q_m, 2);
    assertEqual(obj.iterations, 16);
    assertEqual(obj.I_HARQ, 1);

function test_noise_free_round_trip_recovers_information_bits
    global approx_star;
    approx_star = false;
    A = 40;
    G = 132;
    hEnc = turbo_encoding_chain('A', A, 'G', G, 'Q_m', 2);
    hDec = turbo_decoding_chain('A', A, 'G', G, 'Q_m', 2, 'iterations', 8);
    a = double(rand(1, A) > 0.5);
    f = step(hEnc, a);
    f_llr = 1 - 2 * f;
    a_hat = step(hDec, f_llr);
    assertEqual(a_hat, a);

function test_harq_accumulation
    % With I_HARQ = 1 the decoder accumulates successive blocks. Send the
    % same noise-free LLR vector twice; the decode must succeed after the
    % second step. After reset(obj), the buffer is cleared.
    global approx_star;
    approx_star = false;
    A = 40;
    G = 132;
    hEnc = turbo_encoding_chain('A', A, 'G', G, 'Q_m', 2);
    hDec = turbo_decoding_chain('A', A, 'G', G, 'Q_m', 2, ...
                                'iterations', 8, 'I_HARQ', 1);
    a = double(rand(1, A) > 0.5);
    f = step(hEnc, a);
    f_llr = 1 - 2 * f;
    a_hat1 = step(hDec, f_llr);
    a_hat2 = step(hDec, f_llr);
    assertEqual(a_hat1, a);
    assertEqual(a_hat2, a);
    reset(hDec);

function test_crc_failure_returns_empty
    global approx_star;
    approx_star = false;
    A = 40;
    G = 132;
    hEnc = turbo_encoding_chain('A', A, 'G', G, 'Q_m', 2);
    hDec = turbo_decoding_chain('A', A, 'G', G, 'Q_m', 2, 'iterations', 4);
    a = double(rand(1, A) > 0.5);
    f = step(hEnc, a);
    f_llr = 1 - 2 * f;
    % Flip the sign of every LLR -- the decoder cannot recover a valid CRC.
    a_hat = step(hDec, -f_llr);
    assertTrue(isempty(a_hat));

function test_decode_rejects_wrong_length_input
    global approx_star;
    approx_star = false;
    hDec = turbo_decoding_chain('A', 16, 'G', 132);
    % Assert on the specific identifier so a future refactor that hides this
    % error path (e.g. an upstream check raising a different error) will fail.
    assertExceptionThrown(@() step(hDec, zeros(1, 131)), ...
        'turbo_decoding_chain:wrong_length_input');
    assertExceptionThrown(@() step(hDec, zeros(1, 133)), ...
        'turbo_decoding_chain:wrong_length_input');
