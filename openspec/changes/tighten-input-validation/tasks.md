## 1. Catalogue helper validation state

- [ ] 1.1 List every root-level source `.m` helper that participates in specs or tests.
- [ ] 1.2 Record current direct validation checks and error identifiers for each helper.
- [ ] 1.3 Mark already-complete issue seed items: encoded segment `G` multiple check, `turbo_decoder` negative iteration check, and chain `stepImpl` length checks.

## 2. Add missing OpenSpec invalid scenarios

- [x] 2.1 Add a `crc` delta for undersized CRC generator matrices.
- [x] 2.2 Add a `code-block-segmentation` delta for encoded block length `G` not divisible by `N_L * Q_m`.
- [ ] 2.3 Add deltas for any additional helper validation gaps discovered during the catalogue sweep.

## 3. Implement validation checks

- [x] 3.1 Add an explicit `calculate_crc_bits` guard for `size(G_max, 1) < length(a)`.
- [x] 3.2 Confirm `get_3gpp_encoded_code_block_segment_lengths` rejects non-multiple `G` directly.
- [ ] 3.3 Implement additional missing helper-level checks discovered during the catalogue sweep.

## 4. Add tests

- [x] 4.1 Add a MOxUnit test for undersized `G_max` in `calculate_crc_bits`.
- [x] 4.2 Add a MOxUnit test for non-multiple `G` in `get_3gpp_encoded_code_block_segment_lengths`.
- [ ] 4.3 Add tests for each additional helper-level check.

## 5. Verify and land

- [ ] 5.1 Run `npx openspec validate --all --strict`.
- [ ] 5.2 Run `npm test`.
- [ ] 5.3 Confirm CI is green on the PR.
- [ ] 5.4 Archive after merge.
