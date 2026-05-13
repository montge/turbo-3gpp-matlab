## Why

The OpenSpec baseline records what the code does in WHEN/THEN scenarios, and the upcoming test suite (`add-test-suite-with-coverage`) verifies behavior on sampled inputs. Neither closes the gap of mathematical correctness across the full input space: the QPP interleaver table has 188 entries, the four CRC polynomials each have ≤ 2²⁴ possible inputs, the 8-state trellis terminates in zero only if the math is right, and the HARQ retransmission protocol is a state machine with safety/liveness properties no test can exhaust.

Formal verification raises those gaps from "tested on N samples" to "proved over all inputs" (Lean 4, Cryptol/SAW) or "model-checked over all interleavings" (TLA+). It also gives downstream consumers — research papers, conformance reports, certifications — a citable correctness statement tied directly to the OpenSpec requirements.

## What Changes

- Add a `proofs/lean/` directory containing Lean 4 modules that prove three mathematical claims:
  1. **CRC equivalence**: `mod(a * G_max, 2)` produces the same bit vector as polynomial division by `crc_polynomial_pattern` for all four 3GPP polynomials and any input `A`.
  2. **QPP interleaver bijection**: for each of the 188 supported `K` values, `pi(i) = mod(f1*i + f2*i², K)` is a bijection from `{0, …, K-1}` to itself. This is decidable by direct computation per `K`; Lean reflects the table and discharges each case.
  3. **Constituent encoder zero-state termination**: starting from `(s1, s2, s3) = (0, 0, 0)` and applying the three termination steps (`s1' = 0; s2' = s1; s3' = s2`) drives the shift register to `(0, 0, 0)` regardless of prior state.
- Add a `proofs/tla/` directory containing a TLA+ / TLC model `harq.tla` for the HARQ retransmission protocol, with:
  - State variables for `rv_idx`, the decoder LLR buffer, the CRC status, and the retransmission counter.
  - Actions for "encode-and-transmit", "channel-noise", "decode-and-check", "advance-rv_idx".
  - **Safety**: if `decoder` declares success at iteration `i`, then the CRC of the decoded transport block is zero.
  - **Bounded liveness**: every information block either decodes within `length(rv_idx_sequence)` retransmissions or terminates with an explicit failure (no infinite retransmission).
- Add a `proofs/cryptol/` directory containing a Cryptol spec `crc_3gpp.cry` for all four 3GPP CRCs and a SAW proof script `crc_3gpp.saw` that establishes bit-level equivalence between the Cryptol spec and a translated form of `calculate_crc_bits.m` (via SAW's `mir_*` or `llvm_*` interfaces, depending on the translation pipeline).
- Add a `proofs/traceability.md` mapping every formal proof obligation to the OpenSpec requirement / scenario it discharges, so reviewers can confirm coverage at a glance.
- Add a `verify` CI job that compiles and checks each of the three proof artifacts using the toolchain pinned in `proofs/<tool>/<lockfile>`.

## Capabilities

### New Capabilities

- `formal-verification`: The Lean 4 proof modules, the TLA+ HARQ model and TLC invariants, the Cryptol/SAW CRC equivalence proof, the traceability matrix from proof obligations to OpenSpec scenarios, and the CI verification job.

### Modified Capabilities

None. Formal proofs do not change runtime behavior; they ratify it.

## Impact

- New top-level `proofs/` directory with three tool-specific subdirectories.
- New `.github/workflows/ci.yml` job `verify` that installs Lean 4 (via `elan`), TLA+ tools (via the official `tla2tools.jar`), and Cryptol/SAW (via a pinned binary release), then checks each proof.
- New documentation `proofs/README.md` explaining how to run each tool locally.
- No changes to any existing `.m` source file.
- Per-tool lockfiles: `proofs/lean/lean-toolchain` and `proofs/lean/lakefile.lean`, `proofs/cryptol/cryptol-version`, `proofs/tla/tla-version` (or similar) so the proofs are bit-reproducible.
