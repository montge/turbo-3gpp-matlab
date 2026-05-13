# coding-chain Specification

## Purpose
TBD - created by archiving change backport-3gpp-turbo-baseline. Update Purpose after archive.
## Requirements
### Requirement: turbo_coding_chain base class owns derived parameters

The system SHALL provide a `turbo_coding_chain` base class that exposes:

- **Nontunable input parameters**: `A` (information block length, default 16, must be ≥ 0), `I_LBRM` (limited-buffer rate matching flag, default 0), `N_IR` (circular buffer limit, default `inf`, must be ≥ 0).
- **Tunable parameters**: `rv_idx` (redundancy version, default 0, must be in `{0,1,2,3}`), `G` (encoded transport block length, default 132, must be ≥ 0), `N_L` (number of layers, default 1, must be ≥ 1), `Q_m` (modulation order, default 1, must be in `{1, 2, 4, 6, 8, 10}`).
- **Dependent derived parameters** (computed on each read): `CRC_polynomial_TB = get_3gpp_crc_polynomial('CRC24A')`; `CRC_polynomial_CB = get_3gpp_crc_polynomial('CRC24B')` when `C > 1` else the scalar `1`; `L_TB = length(CRC_polynomial_TB) - 1`; `L_CB = length(CRC_polynomial_CB) - 1`; `B = A + L_TB`; `K_r = get_3gpp_code_block_segment_lengths(B)`; `C = length(K_r)`; `B_prime = B` when `B ≤ 6144` else `B + C * L_CB`; `F_r` a length-`C` row vector with `F_r(1) = sum(K_r) - B_prime` and zeros elsewhere; `D_r = K_r + 4`; `E_r = get_3gpp_encoded_code_block_segment_lengths(G, C, N_L, Q_m)`; `N_ref = floor(N_IR / C)`.
- **Hidden public properties** populated by `setupImpl`: `CRC_generator_matrix_TB`, `CRC_generator_matrix_CB`, `internal_interleaver_patterns` (a `1 × C` cell), `rate_matching_patterns` (a `1 × C` cell).

#### Scenario: Default construction
- **WHEN** `turbo_coding_chain` is constructed with no arguments
- **THEN** the object exposes `A = 16`, `G = 132`, `N_L = 1`, `Q_m = 1`, `I_LBRM = 0`, `N_IR = inf`, `rv_idx = 0`

#### Scenario: Name-value pair construction
- **WHEN** `turbo_coding_chain('A', 40, 'G', 132, 'Q_m', 2)` is called
- **THEN** the constructed object has `A = 40`, `G = 132`, `Q_m = 2`

#### Scenario: Decoding-chain constructor accepts name-value pairs
- **WHEN** `turbo_decoding_chain('A', 8000, 'G', 24000, 'Q_m', 2, 'iterations', 16, 'I_HARQ', 1)` is called
- **THEN** the constructed object has `A = 8000`, `G = 24000`, `Q_m = 2`, `iterations = 16`, `I_HARQ = 1` (this guards against re-introducing the historical `NRLDPCDecoder` typo that silently dropped construction arguments under Octave)

#### Scenario: Reject unsupported Q_m
- **WHEN** `Q_m` is set to a value outside `{1, 2, 4, 6, 8, 10}`
- **THEN** the assignment raises an error

#### Scenario: Reject rv_idx outside 0..3
- **WHEN** `rv_idx` is set to a value outside `{0, 1, 2, 3}`
- **THEN** the assignment raises an error

#### Scenario: Single segment for small A
- **WHEN** `A = 16` (default)
- **THEN** `C = 1` and `K_r` has a single element

#### Scenario: Multiple segments for large A
- **WHEN** `A = 8000`
- **THEN** `C ≥ 2` and `length(K_r) = C` with all elements drawn from the supported `K` set

### Requirement: Encoding chain composes segmentation, encoding, and rate matching

The system SHALL provide `turbo_encoding_chain`, a subclass of `turbo_coding_chain`, whose `step(obj, a)` operation:

1. Appends the transport-block CRC to `a` using `CRC_generator_matrix_TB` to produce `b`.
2. Segments `b` into `C` code blocks `c_r` of lengths `K_r` using `CRC_generator_matrix_CB` (only used when `C > 1`).
3. For each segment `r`: encodes with `turbo_encoder(c_r{r}, internal_interleaver_patterns{r})` to produce a `3 × D_r` matrix `d`, then rate-matches by selecting `d_vec(rate_matching_patterns{r} + 1)`.
4. Concatenates the resulting `C` segments into a length-`G` output `f`.

#### Scenario: Default-size encode produces G bits
- **WHEN** `step(obj, a)` is called on a default-constructed `turbo_encoding_chain` with `a` a row vector of length `A = 16`
- **THEN** the result is a row vector of length `G = 132`

#### Scenario: Encode is deterministic
- **WHEN** `step(obj, a)` is called twice with the same `a` on the same configured object
- **THEN** both calls return identical row vectors

### Requirement: Decoding chain composes deconcatenation, dematching, decoding, and CRC

The system SHALL provide `turbo_decoding_chain`, a subclass of `turbo_coding_chain`, with two additional properties:

- `iterations` (tunable, default 8): the maximum number of decoder iterations per segment.
- `I_HARQ` (nontunable, default 0): when non-zero, the decoder accumulates successive blocks of input LLRs in a per-segment buffer before decoding; the buffer is reset by `reset(obj)` and after `setup`/`release`.

Its `step(obj, f)` operation SHALL:

1. Deconcatenate the length-`G` LLR vector `f` into `C` segments using `E_r`.
2. For each segment: rate-dematch by accumulating LLRs into a `3 × D_r` matrix according to `rate_matching_patterns{r}`, set filler positions of rows 1 and 2 to `NaN`, optionally add to the HARQ buffer, and decode with `turbo_decoder` using either `CRC_generator_matrix_CB` (when `C > 1`) or `CRC_generator_matrix_TB` (when `C = 1`) for early termination.
3. Desegment the decoded segments into a `B`-bit transport block (returning `[]` on any CRC failure when `C > 1`).
4. Verify and remove the transport-block CRC, returning either the `A`-bit information vector `a` or `[]` on CRC failure.

The decoder SHALL also return `iterations_performed`, a length-`C` row vector of per-segment iteration counts.

#### Scenario: Noise-free round trip recovers information bits
- **WHEN** a default-constructed `turbo_encoding_chain` encodes a random `A`-bit vector `a`, the encoded bits are mapped to `+1`/`-1` LLRs (`0 → +1`, `1 → -1`), and `turbo_decoding_chain` decodes them
- **THEN** the recovered vector equals `a`

#### Scenario: HARQ accumulation
- **WHEN** `I_HARQ = 1` and `step(obj, f1)`, `step(obj, f2)` are called in sequence with `f1` and `f2` representing different redundancy versions of the same information block
- **THEN** the second `step` decodes the *sum* of the two received segments' LLRs and the HARQ buffer is reset by `reset(obj)`

#### Scenario: CRC failure returns empty
- **WHEN** the LLR input is sufficiently corrupted that the transport-block CRC fails after decoding
- **THEN** the decoder returns `[]`

