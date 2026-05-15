## MODIFIED Requirements

### Requirement: CRC calculation, append, and verify

The CRC helper functions SHALL reject direct invalid inputs with deliberate helper-level errors before reaching implicit indexing failures.

#### Scenario: Generator matrix smaller than input
- **WHEN** `calculate_crc_bits(a, G_max)` is called with `size(G_max, 1) < length(a)`
- **THEN** the call raises `calculate_crc_bits:generator_too_short`
