function test_suite = test_get_3gpp_encoded_code_block_segment_lengths
    % Scenarios covered (code-block-segmentation/spec.md):
    %   Equal-length encoded segments, Unequal-length encoded segments,
    %   Invalid encoded length granularity
    try
        test_functions = localfunctions(); %#ok<NASGU>
    catch
    end
    initTestSuite;

function test_equal_length_encoded_segments
    % G divisible by C * N_L * Q_m gives identical E_r entries summing to G.
    G = 1200;
    C = 4;
    N_L = 1;
    Q_m = 2;
    E_r = get_3gpp_encoded_code_block_segment_lengths(G, C, N_L, Q_m);
    assertEqual(numel(E_r), C);
    assertEqual(sum(E_r), G);
    assertEqual(numel(unique(E_r)), 1);
    assertEqual(mod(E_r, N_L * Q_m), zeros(1, C));

function test_unequal_length_encoded_segments
    % When G_prime = G/(N_L*Q_m) is not divisible by C, the final gamma
    % segments use the ceil() variant -- producing two distinct lengths
    % summing to G. Use N_L*Q_m = 1 so the source's gamma = mod(G, C)
    % coincides with the standard's gamma = mod(G_prime, C).
    G = 132;
    C = 5;
    N_L = 1;
    Q_m = 1;
    E_r = get_3gpp_encoded_code_block_segment_lengths(G, C, N_L, Q_m);
    assertEqual(numel(E_r), C);
    assertEqual(sum(E_r), G);
    distinct = unique(E_r);
    assertEqual(numel(distinct), 2);
    assertEqual(distinct(2) - distinct(1), N_L * Q_m);
    assertEqual(mod(E_r, N_L * Q_m), zeros(1, C));

function test_single_segment_yields_g
    % C = 1 trivially gives E_r = G.
    E_r = get_3gpp_encoded_code_block_segment_lengths(132, 1, 1, 2);
    assertEqual(E_r, 132);

function test_encoded_length_must_match_modulation_layer_granularity
    assertExceptionThrown(@() ...
        get_3gpp_encoded_code_block_segment_lengths(131, 2, 2, 2), ...
        'get_3gpp_encoded_code_block_segment_lengths:bad_G');
