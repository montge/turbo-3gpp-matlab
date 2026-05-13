function test_suite = test_turbo_encoding_chain
    % Scenarios covered (coding-chain/spec.md):
    %   Default-size encode produces G bits, Encode is deterministic,
    %   Encode rejects wrong-length input
    try
        test_functions = localfunctions(); %#ok<NASGU>
    catch
    end
    initTestSuite;

function test_default_size_encode_produces_g_bits
    global approx_star;
    approx_star = false;
    hEnc = turbo_encoding_chain();
    a = double(rand(1, 16) > 0.5);
    f = step(hEnc, a);
    assertEqual(numel(f), 132);

function test_encode_is_deterministic
    global approx_star;
    approx_star = false;
    hEnc = turbo_encoding_chain('A', 40, 'G', 132, 'Q_m', 2);
    a = double(rand(1, 40) > 0.5);
    f1 = step(hEnc, a);
    f2 = step(hEnc, a);
    assertEqual(f1, f2);

function test_encode_rejects_wrong_length_input
    global approx_star;
    approx_star = false;
    hEnc = turbo_encoding_chain('A', 16);
    assertExceptionThrown(@() step(hEnc, zeros(1, 17)), '*');
    assertExceptionThrown(@() step(hEnc, zeros(1, 15)), '*');
