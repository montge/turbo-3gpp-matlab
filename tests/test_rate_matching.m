function test_suite = test_rate_matching
    % Scenarios covered (rate-matching/spec.md):
    %   Encode -> derate matches round-trip in the noise-free case,
    %   Invalid rate-matching input row count
    try
        test_functions = localfunctions(); %#ok<NASGU>
    catch
    end
    initTestSuite;

function test_encode_derate_matches_round_trip_in_the_noise_free_case
    % Mirror the example in rate_matching.m's docstring: build the index
    % matrix, derive pi via rate_matching, apply 0->+1 / 1->-1, derate
    % through accumulation, and check every non-NaN entry is sign-correct.
    K = 40;
    F = 8;
    D = K + 4;
    rv_idx = 0;
    E = 132;

    % Construct an encoded matrix.
    c = double(rand(1, K) > 0.5);
    c(1:F) = NaN;
    pi_int = internal_interleaver(0:K - 1);
    d = turbo_encoder(c, pi_int);

    % Build the rate-matching pattern via the index-matrix recipe.
    d_idx = reshape(0:3 * D - 1, 3, D);
    d_idx(1:2, 1:F) = NaN;
    pi_rm = rate_matching(d_idx, 0, 0, rv_idx, E);

    % Rate-match the actual encoded matrix.
    d_vec = reshape(d, 1, numel(d));
    e = d_vec(pi_rm + 1);

    % LLR mapping 0 -> +1, 1 -> -1, then derate by accumulation.
    f_llr = 1 - 2 * e;
    d_vec_back = zeros(1, 3 * D);
    for k = 0:numel(pi_rm) - 1
        d_vec_back(pi_rm(k + 1) + 1) = d_vec_back(pi_rm(k + 1) + 1) + f_llr(k + 1);
    end
    d_back = reshape(d_vec_back, 3, D);
    d_back(1:2, 1:F) = NaN;

    % Every non-NaN entry in d_back must be sign-consistent with d.
    finite_mask = ~isnan(d) & ~isnan(d_back);
    assertTrue(any(finite_mask(:)));
    signs_match = sign(d_back(finite_mask)) == sign(1 - 2 * d(finite_mask));
    assertTrue(all(signs_match));

function test_output_length_equals_e
    K = 40;
    F = 0;
    D = K + 4;
    d_idx = reshape(0:3 * D - 1, 3, D);
    d_idx(1:2, 1:F) = NaN;
    E = 96;
    e = rate_matching(d_idx, 0, 0, 0, E);
    assertEqual(numel(e), E);

function test_rejects_wrong_row_count
    d_bad = zeros(2, 44);
    assertExceptionThrown(@() rate_matching(d_bad, 0, 0, 0, 96), ...
        'rate_matching:bad_d_rows');
