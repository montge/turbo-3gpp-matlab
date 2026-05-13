function test_suite = test_placeholder
    % Placeholder test exercised during stage 1 to verify the MOxUnit runner
    % is wired correctly. Replaced by real test files in stage 2.
    try % assignment of 'localfunctions' is necessary in Matlab >= 2016
        test_functions = localfunctions(); %#ok<NASGU>
    catch % no problem; early Matlab versions can use initTestSuite fine
    end
    initTestSuite;

function test_two_plus_two_is_four
    assertEqual(2 + 2, 4);
