function test_suite = test_code_block_deconcatenation
%TEST_CODE_BLOCK_DECONCATENATION
%   Covers deconcatenation error path.
    try
        test_functions = localfunctions();
    catch
    end
    initTestSuite;
end

function test_deconcatenation_length_mismatch
    f = round(rand(1, 100));
    E_r = [50, 60];  % sums to 110, not 100
    assertExceptionThrown(@() code_block_deconcatenation(f, E_r), '');
end

function test_deconcatenation_correct_split
    E_r = [10, 20, 30];
    f = round(rand(1, sum(E_r)));
    e_r = code_block_deconcatenation(f, E_r);
    assertEqual(numel(e_r), 3);
    assertEqual(length(e_r{1}), 10);
    assertEqual(length(e_r{2}), 20);
    assertEqual(length(e_r{3}), 30);
    assertEqual([e_r{1}, e_r{2}, e_r{3}], f);
end
