function test_suite = test_turbo_coding_chain
    % Scenarios covered (coding-chain/spec.md):
    %   Default construction, Name-value pair construction,
    %   Reject unsupported Q_m, Reject rv_idx outside 0..3,
    %   Single segment for small A, Multiple segments for large A
    try
        test_functions = localfunctions(); %#ok<NASGU>
    catch
    end
    initTestSuite;

function test_default_construction
    obj = turbo_coding_chain();
    assertEqual(obj.A, 16);
    assertEqual(obj.G, 132);
    assertEqual(obj.N_L, 1);
    assertEqual(obj.Q_m, 1);
    assertEqual(obj.I_LBRM, 0);
    assertEqual(obj.N_IR, inf);
    assertEqual(obj.rv_idx, 0);

function test_name_value_pair_construction
    obj = turbo_coding_chain('A', 40, 'G', 132, 'Q_m', 2);
    assertEqual(obj.A, 40);
    assertEqual(obj.G, 132);
    assertEqual(obj.Q_m, 2);

function test_reject_unsupported_q_m
    obj = turbo_coding_chain();
    assertExceptionThrown(@() set_qm(obj, 3), '*');
    assertExceptionThrown(@() set_qm(obj, 0), '*');

function test_reject_rv_idx_outside_0_3
    obj = turbo_coding_chain();
    assertExceptionThrown(@() set_rv(obj, -1), '*');
    assertExceptionThrown(@() set_rv(obj,  4), '*');

function test_single_segment_for_small_a
    obj = turbo_coding_chain('A', 16);
    assertEqual(obj.C, 1);
    assertEqual(numel(obj.K_r), 1);

function test_multiple_segments_for_large_a
    obj = turbo_coding_chain('A', 8000);
    assertTrue(obj.C >= 2);
    assertEqual(numel(obj.K_r), obj.C);
    supported = [40:8:511, 512:16:1023, 1024:32:2047, 2048:64:6144];
    for v = obj.K_r
        assertFalse(isempty(find(supported == v, 1)));
    end

function set_qm(obj, v)
    obj.Q_m = v;

function set_rv(obj, v)
    obj.rv_idx = v;
