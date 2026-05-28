## Scope

Catalogue covers root-level source helpers that participate in canonical specs or tests. Simulation drivers (`plot_BLER_vs_SNR.m`, `plot_SNR_vs_A.m`) and `test_octave_smoke.m` are out of scope because they are drivers rather than reusable helpers.

## Helper Validation Catalogue

| Helper | Spec area | Direct validation state | Gap status |
| --- | --- | --- | --- |
| `calculate_crc_bits` | `crc` | Rejects undersized `G_max` with `calculate_crc_bits:generator_too_short`; larger matrices use trailing rows. | Closed in this change. |
| `check_and_remove_crc_bits` | `crc` | CRC failure is represented by returning `[]`; CRC calculation preconditions delegate to `calculate_crc_bits`. | No additional spec-backed gap found. |
| `generate_and_append_crc_bits` | `crc` | CRC calculation preconditions delegate to `calculate_crc_bits`. | No additional spec-backed gap found. |
| `get_3gpp_crc_polynomial` | `crc` | Rejects unsupported CRC names. | Covered by existing invalid-polynomial scenario/tests. |
| `get_crc_generator_matrix` | `crc` | Rejects polynomial patterns shorter than 2. | Covered by existing invalid-polynomial scenario/tests. |
| `get_3gpp_code_block_segment_lengths` | `code-block-segmentation` | Rejects unsupported transport block sizes including `B <= 0`. | Covered by existing invalid-size scenario/tests. |
| `get_3gpp_encoded_code_block_segment_lengths` | `code-block-segmentation` | Rejects `G` values that are not multiples of `N_L * Q_m` with `get_3gpp_encoded_code_block_segment_lengths:bad_G`. | Check already existed; spec/test coverage added in this change. |
| `code_block_segmentation` | `code-block-segmentation` | Uses `K_r` and CRC generator contracts; CRC generator sizing delegates through CRC helpers. | No additional spec-backed gap found. |
| `code_block_desegmentation` | `code-block-segmentation` | CRC failure is represented by returning `[]`; CRC generator sizing delegates through CRC helpers. | No additional spec-backed gap found. |
| `code_block_concatenation` | `code-block-segmentation` | Computes lengths from the provided cell array; no invalid scenario in canonical spec. | No additional spec-backed gap found. |
| `code_block_deconcatenation` | `code-block-segmentation` | Rejects `sum(E_r) != length(f)`. | Covered by existing mismatch scenario/tests. |
| `internal_interleaver` | `internal-interleaver` | Rejects unsupported block lengths. | Covered by existing unsupported-length scenario/tests. |
| `constituent_encoder` | `turbo-encoder` | No invalid-input scenario in canonical spec. | No additional spec-backed gap found. |
| `turbo_encoder` | `turbo-encoder` | Rejects `length(pi) != length(c)`. | Covered by existing mismatch scenario/tests. |
| `subblock_interleaver` | `rate-matching` | Rejects unsupported interleaver indices. | Covered by existing unsupported-index scenario/tests. |
| `circular_buffer` | `rate-matching` | Rejects non-3-row `v`, non-multiple-of-32 `K_Pi`, and unsupported `rv_idx`. | Covered by existing invalid scenarios/tests. |
| `rate_matching` | `rate-matching` | Now rejects inputs where `d` does not have exactly 3 rows. | Closed in this change. |
| `maxstar` | `turbo-decoder` | No invalid-input scenario in canonical spec; supports binary and column-reduction forms. | No additional spec-backed gap found. |
| `constituent_decoder` | `turbo-decoder` | Rejects unequal LLR sequence lengths. | Covered by existing mismatch scenario/tests. |
| `turbo_decoder` | `turbo-decoder` | Rejects non-3-row `d_a`, `pi` length mismatch, non-real/non-finite/non-scalar iteration counts, non-half-multiple iteration counts, and negative iteration counts. | Issue seed item already closed before this change. |
| `turbo_coding_chain` | `coding-chain` | Setters reject negative `A`, negative `N_IR`, unsupported `rv_idx`, negative `G`, `N_L < 1`, and unsupported `Q_m`. | Existing tests cover representative invalid chain parameters. |
| `turbo_encoding_chain` | `coding-chain` | Rejects `step` inputs whose length does not match `A`. | Issue seed item already closed before this change. |
| `turbo_decoding_chain` | `coding-chain` | Rejects `step` inputs whose length does not match `G`. | Issue seed item already closed before this change. |

## Issue Seed Items

- `get_3gpp_encoded_code_block_segment_lengths`: `G % (N_L * Q_m) == 0` direct guard exists; this change adds the missing spec/test coverage.
- `calculate_crc_bits`: undersized `G_max` direct guard and test added in this change.
- `turbo_decoder`: negative `max_iterations` direct guard and tests already exist on `master`.
- `turbo_encoding_chain.stepImpl` / `turbo_decoding_chain.stepImpl`: wrong-length direct guards and tests already exist on `master`.
- Remaining helper sweep: `rate_matching` row-count guard identified and added in this change; no other spec-backed direct-validation gaps found in this pass.
