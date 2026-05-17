## 1. Golden-Vector Generator

- [ ] 1.1 Add a MATLAB/Octave script that, for a given `K`, builds a code block `c`, gets `pi` from the existing `internal-interleaver` helper, computes `d = turbo_encoder(c, pi)`, and derives `c_prime = c(pi)`.
- [ ] 1.2 Define and document the `hdl/vectors/turbo_encoder*.csv` schema: `K`, `c` bits, `c_prime` bits, flattened `3×(K+4)` `d` (fixed bit ordering that round-trips exactly).
- [ ] 1.3 Generate the representative suite: `K ∈ {40, 512, 6144}` (LTE min, mid, max) with ≥4 random blocks per `K`, all non-filler.
- [ ] 1.4 Confirm the generator uses only existing public helpers (no changes to MATLAB/Octave sources).

## 2. Constituent Encoder Core

- [ ] 2.1 Add `hdl/rtl/rsc_constituent_encoder.vhdl`: 3 FFs `(s1,s2,s3)`, recurrence `s1'=c⊕s2⊕s3`, `x=c`, `z=s1'⊕s1⊕s3`, with a framed streaming interface.
- [ ] 2.2 Implement the 3-step trellis termination (feedback forced to 0, `x=s2⊕s3`) emitting the final 3 `(x,z)` pairs; assert end state `(0,0,0)`.
- [ ] 2.3 Add a focused cocotb test for the constituent encoder alone (zero-input→zero, random blocks vs a Python reference of the recurrence).

## 3. Turbo Encoder Core

- [ ] 3.1 Add `hdl/rtl/turbo_encoder.vhdl` instantiating two constituent encoders (natural + interleaved input streams) — no QPP/interleaver logic in the core.
- [ ] 3.2 Add the output-assembly stage: stream body columns `[x;z;z']` for `k=0..K-1`, then the four termination columns exactly per TS36.212 §5.1.3.2.
- [ ] 3.3 Define the top-level streaming interface (`start`/`valid`/`last` in; column `(d0,d1,d2)`+`valid` out); K-agnostic, no compile-time `K`.

## 4. Simulation Lane

- [ ] 4.1 Add `hdl/sim/turbo_encoder/` (Makefile + cocotb test) mirroring `hdl/sim/crc8/`, picked up by `scripts/run_hdl_tests.sh`.
- [ ] 4.2 Implement a reusable cocotb driver/monitor that streams `c`/`c_prime` and captures the `K+4` output columns.
- [ ] 4.3 Compare every output bit against the expected `d` for each golden case; fail on any mismatch.
- [ ] 4.4 Ensure simulator build products / waveforms are gitignored (extend patterns only if needed).

## 5. Verification

- [ ] 5.1 Run the new lane (`npm run test:hdl` path or the turbo_encoder sim target) and confirm all representative `K` cases pass.
- [ ] 5.2 Run the existing `npm test` (Octave) and the existing CRC HDL lane to confirm no regression.
- [ ] 5.3 Record the pass results (vectors, `K` set, counts) in the change.

## 6. Optional Board Smoke (deferred, hardware-gated)

- [ ] 6.1 Define (do not require) a minimal DE2 wrapper concept: a small fixed `K` block run on reset, a signature of `d` shown on `HEX`/`LEDR`, switches/keys only, no screen.
- [ ] 6.2 Mark on-board execution explicitly out of scope for completion; leave wrapper/Quartus work as a follow-on note.

## 7. Validation and Docs

- [ ] 7.1 Add a short `hdl/sim/turbo_encoder/README` (or section) documenting the vector schema, how to regenerate vectors, and how to run the lane cross-platform.
- [ ] 7.2 Run `npx openspec validate add-fpga-turbo-encoder --strict` and confirm it passes.
- [ ] 7.3 Run `npx openspec validate --all --strict` and confirm no regression across specs/changes.
