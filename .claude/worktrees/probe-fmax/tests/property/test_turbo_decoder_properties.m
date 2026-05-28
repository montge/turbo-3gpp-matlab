function test_suite = test_turbo_decoder_properties
    % Property-based tests for the `turbo-decoder` capability.
    try
        test_functions = localfunctions(); %#ok<NASGU>
    catch
    end
    initTestSuite;

function test_noise_free_llr_mapping_recovers_original_bits
    global approx_star;
    approx_star = false;
    rand('state', 4);
    sample_count = 16;
    A_values = [16, 24, 40, 64, 88, 112, 200, 320];
    Q_m_values = [1, 2, 4];
    rv_values = 0:3;
    G_extra = [0, 12, 48, 96];
    for ii = 1:sample_count
        A = A_values(mod(ii - 1, numel(A_values)) + 1);
        Q_m = Q_m_values(mod(ii - 1, numel(Q_m_values)) + 1);
        rv_idx = rv_values(mod(ii - 1, numel(rv_values)) + 1);
        G_extra_v = G_extra(mod(ii - 1, numel(G_extra)) + 1);
        % G must be a multiple of Q_m * N_L; pick the smallest such G >= a
        % reasonable rate.
        G_min = 3 * (A + 24) + 12;
        G = ceil((G_min + G_extra_v) / Q_m) * Q_m;
        hEnc = turbo_encoding_chain('A', A, 'G', G, 'Q_m', Q_m, 'rv_idx', rv_idx);
        hDec = turbo_decoding_chain('A', A, 'G', G, 'Q_m', Q_m, ...
                                    'rv_idx', rv_idx, 'iterations', 8);
        a = double(rand(1, A) > 0.5);
        f = step(hEnc, a);
        f_llr = 1 - 2 * f;
        a_hat = step(hDec, f_llr);
        assertEqual(a_hat, a, sprintf( ...
            'A=%d G=%d Q_m=%d rv_idx=%d round-trip failed', ...
            A, G, Q_m, rv_idx));
    end
