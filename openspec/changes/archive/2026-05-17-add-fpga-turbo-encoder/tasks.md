## 1. Golden-Vector Generator

- [x] 1.1 `scripts/generate_hdl_turbo_encoder_vectors.m`: builds `c`, gets `pi = internal_interleaver(0:K-1)`, computes `d = turbo_encoder(c, pi)`, derives `c_prime = c(pi+1)`.
- [x] 1.2 CSV schema documented in the generator header and `hdl/sim/turbo_encoder/README.md`: `K,c,cprime,d` with `d` flattened **column-major** (`3*(K+4)` chars) — round-trips exactly against the model.
- [x] 1.3 Suite generated: `K ∈ {40, 512, 6144}`, each with all-zeros, all-ones, and 4 seeded-random blocks (18 cases). `K` validated by `internal_interleaver` (errors on unsupported sizes), closing the open question from the authority, not a guess.
- [x] 1.4 Uses only existing public helpers; no MATLAB/Octave sources modified.

## 2. Constituent Encoder Core

- [x] 2.1 `hdl/rtl/rsc_constituent_encoder.vhdl`: 3 FFs `(s1,s2,s3)`, `s1'=din⊕s2⊕s3`, `x=din`, `z=s1'⊕s1⊕s3`, framed streaming (`clk/rst/en/term/din → x_o/z_o`).
- [x] 2.2 3-step trellis termination (`term='1'` → `s1'=0`, `x=s2⊕s3`); verified the final 3 `(x,z)` pairs and zero end-state via golden + unit tests.
- [x] 2.3 Focused unit lane `hdl/sim/rsc_constituent_encoder/` vs a Python port of `constituent_encoder.m` (zeros/ones/random, K∈{1,2,8,40,97}) — PASS.

## 3. Turbo Encoder Core

- [x] 3.1 `hdl/rtl/turbo_encoder.vhdl` instantiates two constituent encoders (natural + interleaved streams); no QPP/interleaver logic in the core.
- [x] 3.2 Output-assembly: body columns `[x;z;z']` for `k=0..K-1`, then the four termination columns exactly per `turbo_encoder.m` (`[x(K+1);z(K+1);x(K+2)]`, `[z(K+2);x(K+3);z(K+3)]`, `[x'(K+1);z'(K+1);x'(K+2)]`, `[z'(K+2);x'(K+3);z'(K+3)]`).
- [x] 3.3 Streaming interface is K-agnostic with a framing handshake — final shape is `rst`/`in_valid`/`in_term`/`emit` (refined from the initial `start/valid/last` sketch; satisfies the spec's K-agnostic + externally-supplied-interleave requirements). No compile-time `K`.

## 4. Simulation Lane

- [x] 4.1 `hdl/sim/turbo_encoder/` (Makefile + cocotb test) mirrors `hdl/sim/crc8/`; runs under the same cross-platform GHDL/cocotb flow.
- [x] 4.2 Reusable `step()` driver/monitor streams `c`/`c_prime`, runs the term + emit phases, captures `K+4` columns.
- [x] 4.3 Compares the full column-major bitstring against expected `d`; any mismatch fails.
- [x] 4.4 Simulator build products / waveforms covered by existing `.gitignore` patterns (`sim_build/`, `*.vcd`, `results.xml`); no new patterns needed.

## 5. Verification

- [x] 5.1 Turbo lane PASS — all 18 cases (K∈{40,512,6144} × {zeros,ones,4×random}) bit-exact vs `turbo_encoder.m` (`TESTS=1 PASS=1 FAIL=0`).
- [x] 5.2 No regression: CRC8 HDL lane `PASS=1 FAIL=0`; Octave software suite `OK (passed=102)`.
- [x] 5.3 Recorded here: 18 turbo cases + constituent unit lane PASS; CRC + Octave regression green.

## 6. Optional Board Smoke (deferred, hardware-gated)

- [x] 6.1 Concept documented (README + design): a DE2 wrapper would reuse the verified core and show a signature of `d` on `HEX`/`LEDR`, switches/keys only, no screen.
- [x] 6.2 Explicitly out of scope for completion; left as a follow-on note (no wrapper/Quartus work in this change).

## 7. Validation and Docs

- [x] 7.1 `hdl/sim/turbo_encoder/README.md` documents the vector schema, regeneration, and cross-platform run.
- [x] 7.2 `npx openspec validate add-fpga-turbo-encoder --strict` — passes.
- [x] 7.3 `npx openspec validate --all --strict` — no regression across specs/changes.
