function test_suite = test_code_block_concatenation
%TEST_CODE_BLOCK_CONCATENATION
%   Covers concat/deconcat invariants from openspec/specs/code-block-segmentation/spec.md.
    try
        test_functions = localfunctions();
    catch
    end
    initTestSuite;
end

function test_concatenation_round_trip
    E_r = [20, 30, 40];
    e_r = cell(1, length(E_r));
    for r = 1 : length(E_r)
        e_r{r} = round(rand(1, E_r(r)));
    end
    f = code_block_concatenation(e_r);
    assertEqual(length(f), sum(E_r));
    recovered = code_block_deconcatenation(f, E_r);
    for r = 1 : length(E_r)
        assertEqual(recovered{r}, e_r{r});
    end
end

function test_single_segment_concatenation
    e_r = {round(rand(1, 132))};
    f = code_block_concatenation(e_r);
    assertEqual(f, e_r{1});
end
