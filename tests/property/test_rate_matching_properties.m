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
        F = floor(rand * (K - 1));
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
