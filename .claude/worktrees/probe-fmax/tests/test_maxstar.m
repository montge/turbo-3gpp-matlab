function test_suite = test_maxstar
    % Scenarios covered (turbo-decoder/spec.md):
    %   Exact maxstar identity, Approximate maxstar uses plain max,
    %   Column-reduction form
    try
        test_functions = localfunctions(); %#ok<NASGU>
    catch
    end
    initTestSuite;

function test_exact_maxstar_identity
    global approx_star;
    approx_star = false;
    a = [-2.0, 0.5, 1.0; 3.0, -1.5, 0.2];
    b = [ 1.0, 0.5, 0.0; 0.0, -1.5, 4.0];
    expected = max(a, b) + log(1 + exp(-abs(a - b)));
    actual = maxstar(a, b);
    assertElementsAlmostEqual(actual, expected, 'absolute', 1e-12);

function test_approximate_maxstar_uses_plain_max
    global approx_star;
    approx_star = true;
    a = [-2.0, 0.5, 1.0; 3.0, -1.5, 0.2];
    b = [ 1.0, 0.5, 0.0; 0.0, -1.5, 4.0];
    assertEqual(maxstar(a, b), max(a, b));
    approx_star = false;   % restore for downstream tests

function test_column_reduction_form
    global approx_star;
    approx_star = false;
    a = [-2.0, 0.5, 1.0;
          3.0, -1.5, 0.2;
          0.0, 1.0,  -3.0];
    % Reduce row-by-row using two-argument maxstar to derive the expected value.
    expected = a(1, :);
    for index = 2:size(a, 1)
        sub = expected - a(index, :);
        sub(isnan(sub)) = 0;
        expected = max(expected, a(index, :)) + log(1 + exp(-abs(sub)));
    end
    actual = maxstar(a);
    assertEqual(numel(actual), size(a, 2));
    assertElementsAlmostEqual(actual, expected, 'absolute', 1e-12);

function test_approximate_column_reduction
    global approx_star;
    approx_star = true;
    a = [-2.0, 0.5, 1.0;
          3.0, -1.5, 0.2];
    assertEqual(maxstar(a), max(a));
    approx_star = false;
