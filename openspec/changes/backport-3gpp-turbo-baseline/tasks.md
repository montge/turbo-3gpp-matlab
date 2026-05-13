## 1. Install and initialize OpenSpec

- [x] 1.1 Add `@fission-ai/openspec` as a dev dependency and create `package.json`
- [x] 1.2 Run `openspec init --tools claude --force` to scaffold `openspec/` and the Claude Code skills/commands
- [x] 1.3 Confirm the schema is `spec-driven` and the workflow exposes `proposal`, `design`, `specs`, `tasks`

## 2. Backport baseline specs

- [x] 2.1 Read every `.m` file in the repository to identify the implicit contract
- [x] 2.2 Group behavior into nine capabilities: `crc`, `code-block-segmentation`, `internal-interleaver`, `turbo-encoder`, `rate-matching`, `turbo-decoder`, `coding-chain`, `simulation`, `octave-compatibility`
- [x] 2.3 Write `proposal.md`, `design.md`, and the nine capability spec files under `openspec/changes/backport-3gpp-turbo-baseline/`
- [x] 2.4 Run `openspec validate backport-3gpp-turbo-baseline` and confirm it passes

## 3. Build the Octave compatibility shim

- [ ] 3.1 Create `+matlab/System.m` with `setProperties`, `step`, `reset`, `release`, callable forwarding, and lazy `setupImpl` dispatch
- [ ] 3.2 Verify Octave can resolve `classdef turbo_coding_chain < matlab.System` against the shim with no edits to existing files
- [ ] 3.3 Run a smoke construction (`turbo_coding_chain('A', 16)`) under Octave and confirm derived properties (`B`, `C`, `K_r`, `D_r`, `E_r`) compute correctly

## 4. Write the Octave smoke test

- [ ] 4.1 Add `test_octave_smoke.m` that encodes a random `A = 16` block, applies the noiseless LLR mapping (`0 → +1`, `1 → -1`), decodes, and asserts bit-exact recovery
- [ ] 4.2 Make the script exit with status 0 on success and a non-zero status on failure
- [ ] 4.3 Print `OCTAVE SMOKE TEST PASSED` on success

## 5. Validate the chain on Octave

- [ ] 5.1 Run `octave --no-gui test_octave_smoke.m` and confirm bit-exact recovery
- [ ] 5.2 Capture the Octave version, exit status, and any warnings into the PR description
- [ ] 5.3 If failures surface, root-cause and either (a) extend the shim or (b) record an Octave-incompatibility note in the `octave-compatibility` spec — never edit DSP behavior to "fix" Octave

## 6. Land the change

- [ ] 6.1 Commit specs + shim + smoke test on `claude/install-fusion-ai-openspec-xTOao`
- [ ] 6.2 Push the branch
- [ ] 6.3 Open a draft pull request
- [ ] 6.4 After review, archive the change with `openspec archive backport-3gpp-turbo-baseline` to promote the deltas into `openspec/specs/`
