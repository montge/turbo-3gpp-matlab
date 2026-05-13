function test_suite = test_code_block_deconcatenation
    % Scenarios covered (code-block-segmentation/spec.md):
    %   Deconcatenation length mismatch (and the deconcatenation round trip)
    try
        test_functions = localfunctions(); %#ok<NASGU>
    catch
    end
    initTestSuite;

function test_deconcatenation_length_mismatch
    % sum(E_r) must equal length(f), otherwise the function errors.
    assertExceptionThrown(@() code_block_deconcatenation([1 0 1 1], [3 2]), '');

function test_round_trip_with_unequal_segments
    e_r = {[1 0 0 1 1], [1], [0 1 0]};
    f = code_block_concatenation(e_r);
    e_back = code_block_deconcatenation(f, [5 1 3]);
    for r = 1:3
        assertEqual(e_back{r}, e_r{r});
    end
