function test_suite = test_internal_interleaver
    % Scenarios covered (internal-interleaver/spec.md):
    %   Supported short block, Supported largest block,
    %   Permutation is a bijection, Unsupported block length
    try
        test_functions = localfunctions(); %#ok<NASGU>
    catch
    end
    initTestSuite;

function test_supported_short_block
    % Smallest supported K is 40.
    K = 40;
    pi = internal_interleaver(0:K - 1);
    assertEqual(numel(pi), K);
    assertEqual(sort(pi), 0:K - 1);

function test_supported_largest_block
    % Largest supported K is 6144.
    K = 6144;
    pi = internal_interleaver(0:K - 1);
    assertEqual(numel(pi), K);
    assertEqual(sort(pi), 0:K - 1);

function test_permutation_is_a_bijection
    % Pick K values from across the table and confirm c -> c_prime is a bijection.
    Ks = [40, 64, 128, 200, 512, 1024, 2048, 4096, 6144];
    for K = Ks
        pi = internal_interleaver(0:K - 1);
        assertEqual(numel(unique(pi)), K);
        assertEqual(min(pi), 0);
        assertEqual(max(pi), K - 1);
        % Round-trip check: interleave a sequence and confirm uniqueness preserved.
        c = (1:K) * 7 + 3;
        c_prime = internal_interleaver(c);
        assertEqual(sort(c_prime), sort(c));
    end

function test_unsupported_block_length
    % K = 41 (or any non-tabulated value) must raise.
    assertExceptionThrown(@() internal_interleaver(0:40), '');
    assertExceptionThrown(@() internal_interleaver(0:9), '');
