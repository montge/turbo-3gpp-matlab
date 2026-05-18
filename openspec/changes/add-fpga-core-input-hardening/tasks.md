## 1. Input-Validity Guards (no behaviour change for valid inputs)

- [ ] 1.1 `circular_buffer.vhdl`: gate `K_Pi`/`N_cb`/`E = 0` before `S_COMPUTE`/`S_READ` (no div/mod-by-zero, defined abort).
- [ ] 1.2 `rate_matching_top.vhdl`: validate `d_len` (`0` / `> DMAX`) before `S_LOADD`.
- [ ] 1.3 `subblock_interleaver.vhdl`: defined no-op/abort for `d_in = 0`.
- [ ] 1.4 `turbo_encode_top.vhdl`: honour `rom_sup` on `S_LOOKUP`; unsupported `K` → surfaced, not encoded with invalid `(d0,step)`.

## 2. Interface / Generator / Docs

- [ ] 2.1 `qpp_rom.vhdl`: make `done` a clean one-cycle pulse (or document level semantics) — chosen against actual consumers.
- [ ] 2.2 `generate_hdl_qpp_rom.m`: create `hdl/vectors/` before `fopen` (sibling-generator pattern).
- [ ] 2.3 Add language identifiers to the CodeRabbit-flagged doc code fences (READMEs/roadmap) — no content change.

## 3. Verification (the acceptance gate)

- [ ] 3.1 Re-run every affected HDL lane (`circular_buffer`, `rate_matching_top`, `subblock_interleaver`, `turbo_encode_top`, `qpp_rom`, `tx_chain_top`) — all PASS **bit-exact** with **unchanged** committed vectors.
- [ ] 3.2 Add directed cocotb cases for the invalid inputs (zero/over-range/unsupported-K) asserting the defined safe path.
- [ ] 3.3 Full regression: all HDL lanes + Octave `OK (passed=102)`; `npx openspec validate --all --strict`.

## 4. Validation and Docs

- [ ] 4.1 Resolve the corresponding CodeRabbit threads on the PR with the rationale (out-of-contract hardening, behaviour preserved).
- [ ] 4.2 `npx openspec validate add-fpga-core-input-hardening --strict` passes.
- [ ] 4.3 `npx openspec validate --all --strict` — no regression.

## 5. Non-Goals (record, do not implement here)

- [ ] 5.1 Sliding-window / divider-free / BRAM synthesis hardening remain the separate documented follow-ons; this change is ONLY the CodeRabbit items.
