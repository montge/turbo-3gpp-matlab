function test_suite = test_maxstar
%TEST_MAXSTAR
%   Covers openspec/specs/turbo-decoder/spec.md "Requirement: maxstar
%   Jacobian logarithm".
    try
        test_functions = localfunctions();
    catch
    end
    initTestSuite;
end

function test_exact_maxstar_identity
    global approx_star;
    approx_star = false;
    a = [1, 2, 3];
    b = [2, 1, 4];
    c = maxstar(a, b);
    expected = max(a, b) + log(1 + exp(-abs(a - b)));
    assertElementsAlmostEqual(c, expected, 'absolute', 1e-12);
end

function test_approx_maxstar_uses_plain_max
    global approx_star;
    approx_star = true;
    a = [1, 2, 3];
    b = [2, 1, 4];
    c = maxstar(a, b);
    assertEqual(c, max(a, b));
    approx_star = false;
end

function test_column_reduction_exact
    global approx_star;
    approx_star = false;
    a = [1, 2, 3; 4, 5, 6];
    c = maxstar(a);
    % Reduce row-by-row: maxstar(a(1,:), a(2,:))
    expected = max(a(1,:), a(2,:)) + log(1 + exp(-abs(a(1,:) - a(2,:))));
    assertElementsAlmostEqual(c, expected, 'absolute', 1e-12);
end
