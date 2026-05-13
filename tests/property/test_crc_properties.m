function test_suite = test_crc_properties
    % Property-based tests for the `crc` capability.
    % All tests seed rand(...) so two runs on the same commit are bit-exact.
    try
        test_functions = localfunctions(); %#ok<NASGU>
    catch
    end
    initTestSuite;

function test_round_trip_for_random_a_on_all_four_polynomials
    rand('state', 1);
    names = {'CRC24A', 'CRC24B', 'CRC16', 'CRC8'};
    for i = 1:numel(names)
        pgen = get_3gpp_crc_polynomial(names{i});
        L = numel(pgen) - 1;
        % Use a fixed mid-range A and several random information vectors.
        for trial = 1:8
            A = 8 + trial * 4;
            G = get_crc_generator_matrix(A, pgen);
            a = double(rand(1, A) > 0.5);
            b = generate_and_append_crc_bits(a, G);
            assertEqual(numel(b), A + L);
            a_back = check_and_remove_crc_bits(b, G);
            assertEqual(a_back, a);
        end
    end
