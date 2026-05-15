# crc Specification

## Purpose
Defines the four 3GPP CRC polynomials (CRC24A, CRC24B, CRC16, CRC8) from TS36.212 §5.1.1, generator-matrix construction from those polynomials, and the calculate / generate-and-append / check-and-remove operations used at both the transport-block and code-block layers.

## Formal Verification
CRC proof obligations are mapped in [`proofs/traceability.md`](../../../proofs/traceability.md#lean-4-pr-1), including the Lean CRC equivalence proof and the independent Cryptol/SAW bit-level equivalence proof.
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

The CRC helper functions SHALL reject direct invalid inputs with deliberate helper-level errors before reaching implicit indexing failures.

#### Scenario: Generator matrix smaller than input
- **WHEN** `calculate_crc_bits(a, G_max)` is called with `size(G_max, 1) < length(a)`
- **THEN** the call raises `calculate_crc_bits:generator_too_short`

