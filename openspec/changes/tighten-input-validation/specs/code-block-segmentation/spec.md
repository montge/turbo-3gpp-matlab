## MODIFIED Requirements

### Requirement: Encoded code block segment lengths follow TS36.212 §5.1.4.1.2

The encoded segment length helper SHALL validate that the total encoded transport block length can be evenly partitioned into modulation-layer symbols before computing per-segment lengths.

#### Scenario: Invalid encoded length granularity
- **WHEN** `get_3gpp_encoded_code_block_segment_lengths(G, C, N_L, Q_m)` is called with `mod(G, N_L * Q_m) != 0`
- **THEN** the call raises `get_3gpp_encoded_code_block_segment_lengths:bad_G`
