## 1. Golden-Vector Generator

- [x] 1.1 `scripts/generate_hdl_internal_interleaver_vectors.m`: gets `pi = internal_interleaver(0:K-1)`; derives `d0` and `step` from the golden `pi` (constant 2nd difference) so the helper is the sole dependency.
- [x] 1.2 CSV schema `K,d0,step,pi` (pi = space-separated ints) documented in the generator header + README; round-trips exactly.
- [x] 1.3 Suite generated for `K ∈ {40, 512, 6144}`; values cross-checked vs the standard table (K=40→d0=13,step=20; K=6144→d0=743,step=960).
- [x] 1.4 Uses only `internal_interleaver`; no MATLAB/Octave sources changed.

## 2. QPP Address-Generator Core

- [x] 2.1 `hdl/rtl/qpp_interleaver.vhdl`: add-only incremental recurrence, single conditional subtract of `K` (`reduce()`), state all `< K`.
- [x] 2.2 Streaming, K-agnostic: `start` latches `K/d0/step`; `valid`/`last`/`pi_o` stream `pi(0..K-1)`; 13-bit datapath sized for `K ≤ 6144`.
- [x] 2.3 No `(K,f1,f2)` table in the core — constants are inputs.

## 3. Simulation Lane

- [x] 3.1 `hdl/sim/internal_interleaver/` (Makefile + cocotb test) mirrors the established lanes.
- [x] 3.2 Driver latches `K/d0/step`, collects `K` streamed indices.
- [x] 3.3 Asserts every index == golden `pi` and the sequence is a permutation of `0..K-1`.
- [x] 3.4 Artifacts covered by existing `.gitignore` (`sim_build/`, `*.vcd`, `results.xml`); no new patterns.

## 4. Verification

- [x] 4.1 Lane PASS — `K ∈ {40,512,6144}` all bit-exact vs `internal_interleaver` incl. K=6144 (`TESTS=1 PASS=1 FAIL=0`).
- [x] 4.2 No regression: turbo HDL `PASS`, CRC8 HDL `PASS`, Octave suite `OK (passed=102)`.
- [x] 4.3 Recorded here: 3 K cases bit-exact + bijective; regression green.

## 5. Validation and Docs

- [x] 5.1 `hdl/sim/internal_interleaver/README.md` documents schema, regeneration, run.
- [x] 5.2 `npx openspec validate add-fpga-internal-interleaver --strict` — passes.
- [x] 5.3 `npx openspec validate --all --strict` — no regression.

## 6. Follow-on Note (not required for completion)

- [x] 6.1 `K→(f1,f2)` ROM (core derives own constants) + optional DE2 demo recorded as the explicit next follow-on; out of scope here.
