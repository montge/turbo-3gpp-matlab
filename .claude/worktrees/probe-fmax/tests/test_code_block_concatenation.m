function test_suite = test_code_block_concatenation
    % Scenarios covered (code-block-segmentation/spec.md):
    %   Concatenation round-trip (concatenation side)
    try
        test_functions = localfunctions(); %#ok<NASGU>
    catch
    end
    initTestSuite;

function test_concatenation_round_trip
    e_r = {[1 0 1 1], [0 0 1], [1 1 0 1 0]};
    f = code_block_concatenation(e_r);
    assertEqual(f, [1 0 1 1 0 0 1 1 1 0 1 0]);
    e_back = code_block_deconcatenation(f, [4 3 5]);
    assertEqual(numel(e_back), 3);
    for r = 1:3
        assertEqual(e_back{r}, e_r{r});
    end

function test_single_block_passthrough
    f = code_block_concatenation({[1 0 1]});
    assertEqual(f, [1 0 1]);

function test_total_length_equals_sum_of_segments
    e_r = {[1 1], [0 0 0], [1]};
    f = code_block_concatenation(e_r);
    assertEqual(numel(f), 2 + 3 + 1);
