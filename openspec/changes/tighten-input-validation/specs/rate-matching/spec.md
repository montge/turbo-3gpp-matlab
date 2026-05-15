## MODIFIED Requirements

### Requirement: Combined rate matching produces invertible bit-position pattern

The combined rate-matching helper SHALL validate that the encoded input matrix has the three rows expected by TS36.212 before indexing the systematic and parity streams.

#### Scenario: Invalid rate-matching input row count
- **WHEN** `rate_matching(d, N_ref, I_LBRM, rv_idx, E)` is called with `size(d, 1) != 3`
- **THEN** the call raises `rate_matching:bad_d_rows`
