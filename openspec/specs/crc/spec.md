# crc Specification

## Purpose
TBD - created by archiving change backport-3gpp-turbo-baseline. Update Purpose after archive.
## Requirements
### Requirement: 3GPP CRC polynomial selection

The system SHALL expose the four 3GPP CRC polynomials defined in §5.1.1 of TS36.212 (`CRC24A`, `CRC24B`, `CRC16`, `CRC8`) and return each polynomial as a binary row vector of length `P + 1`, where `P` is the CRC length, with coefficients ordered from `D^P` (left) to `D^0 = 1` (right).

#### Scenario: CRC24A polynomial returned
- **WHEN** `get_3gpp_crc_polynomial('CRC24A')` is called
- **THEN** the result has length 25 and matches the binary representation of `D^24 + D^23 + D^18 + D^17 + D^14 + D^11 + D^10 + D^7 + D^6 + D^5 + D^4 + D^3 + D + 1`

#### Scenario: CRC24B polynomial returned
- **WHEN** `get_3gpp_crc_polynomial('CRC24B')` is called
- **THEN** the result has length 25 and matches the binary representation of `D^24 + D^23 + D^6 + D^5 + D + 1`

#### Scenario: CRC16 polynomial returned
- **WHEN** `get_3gpp_crc_polynomial('CRC16')` is called
- **THEN** the result has length 17 and matches the binary representation of `D^16 + D^12 + D^5 + 1`

#### Scenario: CRC8 polynomial returned
- **WHEN** `get_3gpp_crc_polynomial('CRC8')` is called
- **THEN** the result has length 9 and matches the binary representation of `D^8 + D^7 + D^4 + D^3 + D + 1`

#### Scenario: Unknown CRC identifier
- **WHEN** `get_3gpp_crc_polynomial` is called with an identifier outside the supported set
- **THEN** the call raises an error

### Requirement: CRC generator matrix construction

The system SHALL construct an `A × P` binary CRC generator matrix `G_P` from a CRC polynomial of length `P + 1` such that for any `A`-bit row vector `a`, the CRC bits are given by `mod(a * G_P, 2)`. The generator matrix MUST be constructed by initializing its bottom row to the lower `P` coefficients of the polynomial and recursing upward with the shift-register relation `G_P(k, :) = xor([G_P(k+1, 2:end), 0], G_P(k+1, 1) * polynomial(2:end))`.

#### Scenario: Generator matrix shape
- **WHEN** `get_crc_generator_matrix(A, polynomial)` is called with `A > 0` and a polynomial of length `P + 1`
- **THEN** the result is an `A × P` binary matrix

#### Scenario: Invalid polynomial
- **WHEN** `get_crc_generator_matrix` is called with a polynomial of length less than 2
- **THEN** the call raises an error

### Requirement: CRC calculation, append, and verify

The system SHALL provide three CRC operations on bit vectors that all use the same generator matrix `G_max`:

- `calculate_crc_bits(a, G_max)` returns the `L`-bit CRC of an `A`-bit information vector by computing `mod(a * G_max(end-A+1:end, :), 2)`, where `L = size(G_max, 2)`.
- `generate_and_append_crc_bits(a, G_max)` returns the `A + L` bit vector formed by concatenating the information bits with the calculated CRC bits.
- `check_and_remove_crc_bits(b, G_max)` accepts a `B = A + L` bit vector, recalculates the CRC over the leading `A` bits, returns the `A` information bits if the CRC matches, and returns an empty vector otherwise.

#### Scenario: CRC append round-trips with check
- **WHEN** an information vector `a` is passed through `generate_and_append_crc_bits` and the result is passed through `check_and_remove_crc_bits` using the same generator matrix
- **THEN** the returned vector equals `a`

#### Scenario: CRC failure returns empty
- **WHEN** any single bit of an output from `generate_and_append_crc_bits` is flipped and the corrupted vector is passed through `check_and_remove_crc_bits`
- **THEN** the result is an empty vector

#### Scenario: Generator matrix sized larger than input
- **WHEN** `calculate_crc_bits(a, G_max)` is called with `size(G_max, 1) > length(a)`
- **THEN** only the trailing `length(a)` rows of `G_max` are used, and the resulting CRC has length `size(G_max, 2)`

