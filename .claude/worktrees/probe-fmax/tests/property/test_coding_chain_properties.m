function test_suite = test_coding_chain_properties
    % Property-based tests for the `coding-chain` capability.
    try
        test_functions = localfunctions(); %#ok<NASGU>
    catch
    end
    initTestSuite;

function test_lbrm_round_trip_for_varied_layers_and_modulation
    % Backfills the old test_chain branch's LBRM/N_L/Q_m sweep in bounded,
    % deterministic form.
    global approx_star;
    approx_star = false;
    rand('state', 7);
    cases = [
        16, 132, 132, 1, 1, 0;
        40, 288, 220, 1, 2, 1;
        88, 480, 360, 2, 4, 2;
        200, 1260, 420, 3, 6, 3
    ];
    for ii = 1:size(cases, 1)
        A = cases(ii, 1);
        G = cases(ii, 2);
        N_IR = cases(ii, 3);
        N_L = cases(ii, 4);
        Q_m = cases(ii, 5);
        rv_idx = cases(ii, 6);
        encoder = turbo_encoding_chain('A', A, 'G', G, ...
            'I_LBRM', 1, 'N_IR', N_IR, 'N_L', N_L, ...
            'Q_m', Q_m, 'rv_idx', rv_idx);
        decoder = turbo_decoding_chain('A', A, 'G', G, ...
            'I_LBRM', 1, 'N_IR', N_IR, 'N_L', N_L, ...
            'Q_m', Q_m, 'rv_idx', rv_idx, 'iterations', 8);
        a = double(rand(1, A) > 0.5);
        f = step(encoder, a);
        f_llr = 1000 * (1 - 2 * f);
        a_hat = step(decoder, f_llr);
        assertEqual(a_hat, a, sprintf( ...
            'A=%d G=%d N_IR=%d N_L=%d Q_m=%d rv_idx=%d failed', ...
            A, G, N_IR, N_L, Q_m, rv_idx));
    end
