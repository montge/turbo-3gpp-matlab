function test_suite = test_turbo_coding_chain
%TEST_TURBO_CODING_CHAIN
%   Covers openspec/specs/coding-chain/spec.md scenarios for the base class,
%   encoding chain, and decoding chain.
    try
        test_functions = localfunctions();
    catch
    end
    initTestSuite;
end

function test_default_construction
    h = turbo_coding_chain;
    assertEqual(h.A, 16);
    assertEqual(h.G, 132);
    assertEqual(h.N_L, 1);
    assertEqual(h.Q_m, 1);
    assertEqual(h.I_LBRM, 0);
    assertEqual(h.N_IR, inf);
    assertEqual(h.rv_idx, 0);
end

function test_name_value_pair_construction
    h = turbo_coding_chain('A', 40, 'G', 132, 'Q_m', 2);
    assertEqual(h.A, 40);
    assertEqual(h.G, 132);
    assertEqual(h.Q_m, 2);
end

function test_reject_unsupported_Q_m
    h = turbo_coding_chain;
    assertExceptionThrown(@() set_Q_m(h, 3), '');
end

function test_reject_rv_idx_out_of_range
    h = turbo_coding_chain;
    % rv_idx setter raises with a specific identifier; match it explicitly.
    assertExceptionThrown(@() set_rv_idx(h, 4), ...
        'ldpc_3gpp_matlab:UnsupportedParameters');
    assertExceptionThrown(@() set_rv_idx(h, -1), ...
        'ldpc_3gpp_matlab:UnsupportedParameters');
end

function test_single_segment_for_small_A
    h = turbo_coding_chain('A', 16);
    assertEqual(h.C, 1);
    assertEqual(numel(h.K_r), 1);
end

function test_multiple_segments_for_large_A
    h = turbo_coding_chain('A', 8000);
    assertTrue(h.C >= 2);
    assertEqual(numel(h.K_r), h.C);
end

function test_decoding_chain_constructor_accepts_name_value_pairs
    % Regression: turbo_decoding_chain constructor was misnamed
    % NRLDPCDecoder, dropping construction args under Octave.
    hDec = turbo_decoding_chain('A', 8000, 'G', 24000, 'Q_m', 2, ...
                                'iterations', 16, 'I_HARQ', 1);
    assertEqual(hDec.A, 8000);
    assertEqual(hDec.G, 24000);
    assertEqual(hDec.Q_m, 2);
    assertEqual(hDec.iterations, 16);
    assertEqual(hDec.I_HARQ, 1);
end

function test_default_size_encode_produces_G_bits
    global approx_star;
    approx_star = false;
    hEnc = turbo_encoding_chain('A', 16, 'G', 132, 'Q_m', 2);
    a = round(rand(1, 16));
    f = step(hEnc, a);
    assertEqual(length(f), 132);
end

function test_encode_is_deterministic
    global approx_star;
    approx_star = false;
    hEnc = turbo_encoding_chain('A', 16, 'G', 132, 'Q_m', 2);
    a = round(rand(1, 16));
    f1 = step(hEnc, a);
    f2 = step(hEnc, a);
    assertEqual(f1, f2);
end

function test_noise_free_round_trip
    global approx_star;
    approx_star = false;
    rand('state', 3);
    A = 16; G = 132;
    hEnc = turbo_encoding_chain('A', A, 'G', G, 'Q_m', 2);
    hDec = turbo_decoding_chain('A', A, 'G', G, 'Q_m', 2, 'iterations', 8);
    a = double(rand(1, A) > 0.5);
    f = step(hEnc, a);
    f_llr = 1 - 2 * f;
    a_hat = step(hDec, f_llr);
    assertEqual(a_hat, a);
end

%-------------------------------------------------------------------------
% Helpers
%-------------------------------------------------------------------------
function set_Q_m(h, v)
    h.Q_m = v;
end

function set_rv_idx(h, v)
    h.rv_idx = v;
end
