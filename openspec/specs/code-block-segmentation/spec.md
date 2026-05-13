# code-block-segmentation Specification

## Purpose
TBD - created by archiving change backport-3gpp-turbo-baseline. Update Purpose after archive.
## Requirements
### Requirement: Code block segment lengths follow TS36.212 §5.1.2

The system SHALL compute the per-segment lengths `K_r` for a transport block of size `B` bits according to §5.1.2 of TS36.212. The supported segment lengths SHALL be drawn from the set `{40, 48, …, 504, 512, 528, …, 1008, 1024, 1056, …, 2016, 2048, 2112, …, 6144}` (i.e. step 8 up to 511, step 16 up to 1023, step 32 up to 2047, step 64 up to 6144). When `B ≤ 6144` the result MUST be a single segment; when `B > 6144` the result MUST be `C = ceil(B / (6144 - 24))` segments whose lengths combine a `K_minus` and a `K_plus` from the supported set such that `C_minus * K_minus + C_plus * K_plus ≥ B + C * 24` with the minimum admissible `K_plus`.

#### Scenario: Single-segment small transport block
- **WHEN** `get_3gpp_code_block_segment_lengths(40)` is called
- **THEN** the result is `[40]`

#### Scenario: Single-segment up to Z
- **WHEN** `get_3gpp_code_block_segment_lengths(B)` is called with `1 ≤ B ≤ 6144`
- **THEN** the result has exactly one element, drawn from the supported `K` set, and that element is the smallest supported value `≥ B`

#### Scenario: Multi-segment over Z
- **WHEN** `get_3gpp_code_block_segment_lengths(B)` is called with `B > 6144`
- **THEN** the result has `C = ceil(B / 6120)` elements, each drawn from the supported `K` set, with at most two distinct values

#### Scenario: Invalid transport block size
- **WHEN** `get_3gpp_code_block_segment_lengths(B)` is called with `B ≤ 0`
- **THEN** the call raises an error

### Requirement: Encoded code block segment lengths follow TS36.212 §5.1.4.1.2

The system SHALL compute the per-segment encoded lengths `E_r` for a total encoded transport block length `G`, segment count `C`, layer count `N_L`, and modulation order `Q_m` such that `sum(E_r) = G`, each `E_r` is a multiple of `N_L * Q_m`, and the last `gamma = mod(G/(N_L*Q_m), C)` segments are one `N_L*Q_m` step longer than the first `C - gamma` segments.

#### Scenario: Equal-length encoded segments
- **WHEN** `get_3gpp_encoded_code_block_segment_lengths(G, C, N_L, Q_m)` is called with `mod(G/(N_L*Q_m), C) == 0`
- **THEN** every element of `E_r` equals `G / C`

#### Scenario: Unequal-length encoded segments
- **WHEN** `get_3gpp_encoded_code_block_segment_lengths(G, C, N_L, Q_m)` is called with `gamma = mod(G/(N_L*Q_m), C) > 0`
- **THEN** the first `C - gamma` elements equal `N_L*Q_m*floor(G/(N_L*Q_m*C))` and the remaining `gamma` elements equal `N_L*Q_m*ceil(G/(N_L*Q_m*C))`

### Requirement: Transport block segmentation with filler bits and code block CRC

The system SHALL segment a `B`-bit transport block `b` into `C` code blocks of lengths `K_r` by:

1. Setting the filler-bit count `F = sum(K_r) - B_prime`, where `B_prime = B` for `C = 1` and `B_prime = B + C*L` for `C > 1` (with `L = size(G_max, 2)`).
2. Prepending `F` filler bits (represented as `NaN`) to the first code block.
3. Filling the remaining bits of each code block with successive bits from `b`.
4. When `C > 1`, computing a `L`-bit CRC of each code block (treating filler bits as zero) using `G_max` and appending the CRC to that code block.

Desegmentation SHALL invert this operation, returning the empty vector if the CRC of any code block does not match.

#### Scenario: Round-trip single-segment
- **WHEN** a transport block `b` is passed through `code_block_segmentation(b, K_r, G_max)` and the resulting cell array is passed through `code_block_desegmentation(c_r, length(b), G_max)`
- **THEN** the recovered vector equals `b`

#### Scenario: Round-trip multi-segment with CRC
- **WHEN** a transport block of size `B > 6144` is segmented and then desegmented using `G_max = get_crc_generator_matrix(6144, get_3gpp_crc_polynomial('CRC24B'))`
- **THEN** the recovered vector equals the original transport block

#### Scenario: Desegmentation rejects corrupted segment
- **WHEN** any bit of any segment in a multi-segment desegmentation input is flipped
- **THEN** `code_block_desegmentation` returns an empty vector

### Requirement: Code block concatenation and deconcatenation

The system SHALL concatenate an ordered cell array of `C` encoded code blocks (with lengths `E_r`) into a single row vector `f` of length `G = sum(E_r)` and SHALL provide an inverse `code_block_deconcatenation(f, E_r)` that returns the original cell array, raising an error if `sum(E_r) != length(f)`.

#### Scenario: Concatenation round-trip
- **WHEN** an encoded code block cell array is concatenated and then deconcatenated using the original `E_r`
- **THEN** the recovered cell array elementwise equals the original

#### Scenario: Deconcatenation length mismatch
- **WHEN** `code_block_deconcatenation(f, E_r)` is called with `sum(E_r) != length(f)`
- **THEN** the call raises an error

