## ADDED Requirements

### Requirement: QPP interleaver for all 188 supported block lengths

The system SHALL implement the Quadratic Permutation Polynomial (QPP) interleaver of TS36.212 §5.1.3.2.3 for every supported information-block length `K` in `{40, 48, 56, …, 6144}` (188 entries, matching Table 5.1.3-3 of TS36.212). For each supported `K` the interleaver SHALL look up the constants `f1(K)` and `f2(K)` from the standardized table and produce the permutation `pi(i) = mod(f1 * i + f2 * i^2, K)` for `i = 0, …, K - 1`. Invoking the interleaver with the index vector `0:K-1` SHALL return the permutation pattern itself.

#### Scenario: Supported short block
- **WHEN** `internal_interleaver(0:39)` is called (smallest supported `K = 40`, `f1 = 3`, `f2 = 10`)
- **THEN** the result is the row vector `mod(3*i + 10*i^2, 40)` for `i = 0..39`

#### Scenario: Supported largest block
- **WHEN** `internal_interleaver(0:6143)` is called (`K = 6144`, `f1 = 263`, `f2 = 480`)
- **THEN** the result is the row vector `mod(263*i + 480*i^2, 6144)` for `i = 0..6143`

#### Scenario: Permutation is a bijection
- **WHEN** the pattern `pi = internal_interleaver(0:K-1)` is computed for any supported `K`
- **THEN** the multiset of values in `pi` equals `{0, 1, …, K-1}`

#### Scenario: Unsupported block length
- **WHEN** `internal_interleaver` is called with an input whose length is not in the supported `K` set (e.g. 41)
- **THEN** the call raises an error
