## Overview

This change treats input validation as part of the helper contract, not only as a property of high-level chain setters. Each helper should reject invalid direct inputs before MATLAB/Octave reaches an indexing, shape, or arithmetic failure that would be harder to connect to the public precondition.

## Validation Style

- Prefer function-scoped error identifiers such as `calculate_crc_bits:generator_too_short`.
- Error text should name the expected condition and the observed value where practical.
- Preserve existing identifiers when tests or callers already depend on them.
- Add validation before derived indexing or allocation that assumes the precondition.

## Catalogue Process

For each root-level source `.m` helper, record:

- Public preconditions documented in comments and OpenSpec scenarios.
- Existing direct checks and their error identifiers.
- Gaps where invalid input currently relies on upstream validation or implicit MATLAB/Octave failures.
- Required test additions.

Simulation/plotting drivers are out of scope for this pass unless a test already invokes them as helpers.

## Initial Findings

- `calculate_crc_bits` documents that `size(G_max, 1) >= length(a)` and the canonical CRC spec already has an invalid scenario for the undersized case, but the implementation currently indexes from a negative/zero row range instead of raising a deliberate helper-level error.
- `get_3gpp_encoded_code_block_segment_lengths` now checks that `G` is a multiple of `N_L * Q_m`, but the canonical spec and tests should include that invalid scenario explicitly.
- `turbo_decoder` and the encoding/decoding chain `stepImpl` length checks were already added before this change and should be marked as done during the catalogue sweep.
