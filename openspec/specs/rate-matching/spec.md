# rate-matching Specification

## Purpose
TBD - created by archiving change backport-3gpp-turbo-baseline. Update Purpose after archive.
## Requirements
### Requirement: Subblock interleaving with three indices

The system SHALL implement subblock interleaving as specified in §5.1.4.1.1 of TS36.212. For an input row vector `d` of length `D`, the interleaver SHALL:

1. Choose the smallest `R_TC_subblock` such that `D ≤ R_TC_subblock * 32` and set `K_Pi = R_TC_subblock * 32`.
2. Left-pad `d` with `N_D = K_Pi - D` `NaN` entries.
3. For `subblock_interleaver_index ∈ {0, 1}`: reshape the padded sequence into a `R_TC_subblock × 32` row-major matrix, permute its columns using `P = [0, 16, 8, 24, 4, 20, 12, 28, 2, 18, 10, 26, 6, 22, 14, 30, 1, 17, 9, 25, 5, 21, 13, 29, 3, 19, 11, 27, 7, 23, 15, 31]`, and read out row-major.
4. For `subblock_interleaver_index = 2`: produce `pi(k) = mod(P(floor(k / R_TC_subblock) + 1) + 32 * mod(k, R_TC_subblock) + 1, K_Pi)` for `k = 0..K_Pi - 1` and read `y(pi + 1)`.

The returned vector SHALL have length `K_Pi`, with the `NaN` filler propagated to the interleaved positions.

#### Scenario: Output length is a multiple of 32
- **WHEN** `subblock_interleaver(d, idx)` is called with any input length `D` and any supported index `idx`
- **THEN** the returned vector has a length that is a multiple of 32 and is the smallest such length that is `≥ D`

#### Scenario: Unsupported index
- **WHEN** `subblock_interleaver` is called with `subblock_interleaver_index ∉ {0, 1, 2}`
- **THEN** the call raises an error

### Requirement: Circular buffer with redundancy versions and optional LBRM

The system SHALL implement the circular buffer of §5.1.4.1.2 of TS36.212. The buffer SHALL accept a `3 × K_Pi` interleaved matrix `v` (where `K_Pi` is a multiple of 32) and produce a length-`E` row vector `e` by:

1. Constructing `w` of length `K_w = 3 * K_Pi` by placing row 1 of `v` in positions `1..K_Pi` and interleaving rows 2 and 3 of `v` into the remaining positions (`w(K_Pi + 2k + 1) = v(2, k+1)`, `w(K_Pi + 2k + 2) = v(3, k+1)`).
2. Setting `N_cb = K_w` when `I_LBRM = 0` and `N_cb = min(N_ref, K_w)` otherwise.
3. Setting the starting offset `k_0 = R_TC_subblock * (2 * ceil(N_cb / (8 * R_TC_subblock)) * rv_idx + 2)`, where `R_TC_subblock = K_Pi / 32`.
4. Reading `E` non-`NaN` values from `w` starting at index `mod(k_0 + j, N_cb) + 1` and advancing `j`, skipping `NaN` filler entries.

The implementation SHALL raise an error if `v` does not have 3 rows, if `K_Pi` is not a multiple of 32, or if `rv_idx ∉ {0, 1, 2, 3}`.

#### Scenario: Redundancy versions select different starting offsets
- **WHEN** the circular buffer is invoked with the same `v`, `N_ref`, `I_LBRM`, and `E` but different `rv_idx` values
- **THEN** the four `rv_idx` values produce four distinct starting offsets `k_0` (modulo `N_cb`)

#### Scenario: Filler bits are skipped
- **WHEN** the circular buffer reads from a window that contains `NaN` filler entries
- **THEN** the output `e` has length exactly `E` and contains no `NaN` values

#### Scenario: Invalid rv_idx
- **WHEN** `circular_buffer` is called with `rv_idx ∉ {0, 1, 2, 3}`
- **THEN** the call raises an error

### Requirement: Combined rate matching produces invertible bit-position pattern

The system SHALL combine subblock interleaving and circular buffering into a `rate_matching(d, N_ref, I_LBRM, rv_idx, E)` operation that applies the three rows of `d` to the three subblock-interleaver indices `0`, `1`, `2` respectively before circular buffering. When `d` is the index matrix `reshape(0:3*D-1, 3, D)` with filler positions set to `NaN`, the operation SHALL return the rate-matching pattern `pi` such that rate matching is `e = d_vec(pi + 1)` and rate dematching of LLRs `e` is the accumulator `d_vec(pi(k) + 1) += e(k)`.

#### Scenario: Encode → derate matches round-trip in the noise-free case
- **WHEN** an encoded matrix `d` of dimension `3 × D` is rate-matched to produce a length-`E` vector, the LLR mapping `0 → +1, 1 → -1` is applied, and the inverse rate-dematching accumulates back into a `3 × D` matrix
- **THEN** the sign of every non-`NaN` entry in the recovered matrix matches the original encoded bit at the same position

