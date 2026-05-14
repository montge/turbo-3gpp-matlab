## Why

GitHub issue #3 tracks validation gaps where root-level object setters or happy-path callers already enforce preconditions, but individual helper functions can still fail implicitly or with inconsistent errors when called directly. That makes failures harder to diagnose and leaves some invalid-input OpenSpec scenarios enforced only by upstream callers.

## What Changes

- Catalogue every root-level `.m` helper and record whether it performs direct leaf-level validation for its documented preconditions.
- Add or refine invalid-input scenarios in the relevant canonical OpenSpec capability specs.
- Add explicit helper-level validation with consistent, function-scoped error identifiers.
- Add MOxUnit tests for every new error path.
- Keep simulation/plotting scripts out of scope unless they already participate in automated tests.

## Capabilities

### Modified Capabilities

- `crc`: `calculate_crc_bits` must reject a generator matrix with fewer rows than the information vector length.
- `code-block-segmentation`: encoded code-block segment length calculation must reject `G` values that are not multiples of `N_L * Q_m`.
- Additional capability deltas will be added as the helper catalogue identifies missing direct checks.

## Impact

- More direct, consistent errors from helper functions when they are called outside the high-level chain objects.
- Additional negative-path tests under `tests/`.
- No intended change to valid-input DSP behavior.

## References

- GitHub issue: #3
- Originating review thread: https://github.com/montge/turbo-3gpp-matlab/pull/2#discussion_r3235104104
