function test_suite = test_circular_buffer
    % Scenarios covered (rate-matching/spec.md):
    %   Redundancy versions select different starting offsets (no LBRM),
    %   Redundancy version offset matches the standard formula,
    %   Filler bits are skipped, Invalid rv_idx
    try
        test_functions = localfunctions(); %#ok<NASGU>
    catch
    end
    initTestSuite;

function test_invalid_rv_idx
    K_Pi = 64;
    v = zeros(3, K_Pi);
    assertExceptionThrown(@() circular_buffer(v, 0, 0, -1, 10), '*');
    assertExceptionThrown(@() circular_buffer(v, 0, 0,  4, 10), '*');

function test_rejects_wrong_row_count
    v_bad = zeros(2, 64);
    assertExceptionThrown(@() circular_buffer(v_bad, 0, 0, 0, 10), '*');

function test_rejects_non_multiple_of_32_columns
    v_bad = zeros(3, 33);
    assertExceptionThrown(@() circular_buffer(v_bad, 0, 0, 0, 10), '*');

function test_redundancy_versions_select_different_starting_offsets
    % No-LBRM mode and a buffer large enough that the four rv_idx values
    % give four distinct k_0 modulo N_cb. Tag bit-0 onward so the start
    % position of each rv slice is identifiable.
    K_Pi = 64;
    v = zeros(3, K_Pi);
    v(1, :) = 1:K_Pi;                          % distinctive row-1 values
    v(2, :) = (1:K_Pi) + 100;
    v(3, :) = (1:K_Pi) + 200;
    E = 4;
    starts = zeros(1, 4);
    for rv_idx = 0:3
        e = circular_buffer(v, 0, 0, rv_idx, E);
        starts(rv_idx + 1) = e(1);
    end
    assertEqual(numel(unique(starts)), 4);

function test_redundancy_version_offset_matches_the_standard_formula
    % Reproduce the same first-emitted symbol using the spec's k_0 formula.
    K_Pi = 64;
    v = zeros(3, K_Pi);
    v(1, :) = 1:K_Pi;
    v(2, :) = (1:K_Pi) + 100;
    v(3, :) = (1:K_Pi) + 200;
    R = K_Pi / 32;
    N_cb = 3 * K_Pi;                           % I_LBRM = 0
    w = zeros(1, N_cb);
    w(1:K_Pi) = v(1, :);
    for k = 0:K_Pi - 1
        w(K_Pi + 2 * k + 1) = v(2, k + 1);
        w(K_Pi + 2 * k + 2) = v(3, k + 1);
    end
    for rv_idx = 0:3
        k0 = R * (2 * ceil(N_cb / (8 * R)) * rv_idx + 2);
        expected_first = w(mod(k0, N_cb) + 1);
        e = circular_buffer(v, 0, 0, rv_idx, 4);
        assertEqual(e(1), expected_first);
    end

function test_filler_bits_are_skipped
    % Put NaN fillers into v and check the output contains exactly E finite
    % entries (no NaN passes through).
    K_Pi = 64;
    v = zeros(3, K_Pi);
    v(1, 1:5) = NaN;        % typical filler-placement
    v(2, 1:5) = NaN;
    E = 50;
    e = circular_buffer(v, 0, 0, 0, E);
    assertEqual(numel(e), E);
    assertFalse(any(isnan(e)));
