function test_suite = test_rate_matching_properties
    % Property-based tests for the `rate-matching` capability.
    try
        test_functions = localfunctions(); %#ok<NASGU>
    catch
    end
    initTestSuite;

function test_derate_maps_each_e_index_back_to_a_unique_d_index
    rand('state', 5);
    sample_count = 16;
    supported_K = [40:8:511, 512:16:1023, 1024:32:2047, 2048:64:6144];
    for ii = 1:sample_count
        % Pick a random supported K, a random F < K, and a random rv_idx.
        K = supported_K(floor(rand * numel(supported_K)) + 1);
        % Include the F = K-1 edge case (only one non-filler slot in rows 1-2).
        F = floor(rand * K);
        rv_idx = floor(rand * 4);
        D = K + 4;
        % Build the canonical rate-matching pattern via the index-matrix recipe.
        d_idx = reshape(0:3 * D - 1, 3, D);
        d_idx(1:2, 1:F) = NaN;
        E_min = 3 * D;
        E = E_min + ii;   % vary E across the sweep
        pi_rm = rate_matching(d_idx, 0, 0, rv_idx, E);
        % Every pi entry must point at a non-filler position in d_idx.
        d_vec = reshape(d_idx, 1, numel(d_idx));
        selected = d_vec(pi_rm + 1);
        assertEqual(numel(pi_rm), E);
        assertFalse(any(isnan(selected)));
    end

function test_matches_legacy_lte_puncturer_reference
    % Backfills the old test_rate_matching branch's independent LTE
    % puncturer comparison without carrying over its infinite fuzz loop.
    cases = [
        1, 1, 0;
        40, 80, 1;
        100, 180, 2;
        511, 700, 3;
        1024, 1600, 0;
        6144, 9000, 2
    ];
    for ii = 1:size(cases, 1)
        K = cases(ii, 1);
        E = cases(ii, 2);
        rv_idx = cases(ii, 3);
        D = K + 4;
        d_idx = reshape(0:3 * D - 1, 3, D);
        actual = rate_matching(d_idx, 0, 0, rv_idx, E);
        expected = reference_lte_puncturer(K, E, rv_idx);
        assertEqual(actual, expected, ...
            sprintf('K=%d E=%d rv_idx=%d mismatch', K, E, rv_idx));
    end

function puncturer = reference_lte_puncturer(K, E, rv_idx)
    D = K + 4;
    d = reshape(0:3 * D - 1, 3, D);
    v0 = reference_subblock_interleaver(d(1, :), 0);
    v1 = reference_subblock_interleaver(d(2, :), 1);
    v2 = reference_subblock_interleaver(d(3, :), 2);
    w = [v0, reshape([v1; v2], 1, 2 * length(v1))];
    K_w = length(w);
    N_cb = K_w;
    C_TC_subblock = 32;
    R_TC_subblock = ceil(D / C_TC_subblock);
    k_0 = R_TC_subblock * (2 * ceil(N_cb / (8 * R_TC_subblock)) * rv_idx + 2);
    puncturer = zeros(1, E);
    k = 0;
    j = 0;
    while k < E
        candidate = w(mod(k_0 + j, N_cb) + 1);
        if ~isnan(candidate)
            puncturer(k + 1) = candidate;
            k = k + 1;
        end
        j = j + 1;
    end

function v = reference_subblock_interleaver(d, idx)
    D = length(d);
    C_TC_subblock = 32;
    R_TC_subblock = ceil(D / C_TC_subblock);
    N_D = R_TC_subblock * C_TC_subblock - D;
    y = [nan(1, N_D), d];
    matrix = reshape(y, C_TC_subblock, R_TC_subblock)';
    P = [0 16 8 24 4 20 12 28 2 18 10 26 6 22 14 30 ...
         1 17 9 25 5 21 13 29 3 19 11 27 7 23 15 31];
    K_Pi = R_TC_subblock * C_TC_subblock;
    if idx < 2
        matrix = matrix(:, P + 1);
        v = reshape(matrix, 1, K_Pi);
    else
        k = 0:K_Pi - 1;
        pi = mod(P(floor(k / R_TC_subblock) + 1) + ...
                 C_TC_subblock * mod(k, R_TC_subblock) + 1, K_Pi);
        v = y(pi + 1);
    end
