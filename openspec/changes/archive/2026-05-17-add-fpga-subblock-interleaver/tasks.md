## 1. Golden-Vector Generator

- [x] 1.1 `scripts/generate_hdl_subblock_interleaver_vectors.m`: calls `subblock_interleaver(0:D-1, idx)`; maps `NaN → -1`.
- [x] 1.2 CSV `D,idx,pat` (pat = space-separated `K_Pi` ints, `-1`=filler) documented in the generator + README.
- [x] 1.3 Suite: `D ∈ {44,64,100,516,6148}` (encoder-relevant + exact-multiple + non-multiple), idx `{0,2}`, plus `D=44 idx=1`. Sanity-checked (D=64→0,32,16; idx0==idx1; idx2=idx0+1; filler=K_Pi−D).
- [x] 1.4 Uses only `subblock_interleaver`; no MATLAB/Octave sources changed.

## 2. Sub-block Interleaver Core

- [x] 2.1 `hdl/rtl/subblock_interleaver.vhdl`: local 32-entry `P` ROM, nested counters; `R=(D+31)>>5`, `K_Pi=R<<5`, `N_D=K_Pi-D` (no divider).
- [x] 2.2 `pi_y=(r0<<5)+P[c0]` (idx 0/1); idx 2 `+1` + single conditional subtract of `K_Pi`; `filler = pi_y<N_D`; `idx_o = pi_y-N_D`.
- [x] 2.3 Streaming K-agnostic: `start` latches `D/idx`; `valid`/`filler`/`idx_o`/`last` stream `K_Pi` elements.

## 3. Simulation Lane

- [x] 3.1 `hdl/sim/subblock_interleaver/` (Makefile + cocotb) mirrors the established lanes.
- [x] 3.2 Driver latches `D/idx`, collects `K_Pi` `(filler, d-index)` pairs.
- [x] 3.3 Asserts every element vs golden + filler count `= K_Pi - D`.
- [x] 3.4 Artifacts covered by existing `.gitignore`.

## 4. Verification

- [x] 4.1 Lane PASS for all 11 `(D,idx)` incl. D=6148 and idx=1==idx=0 (`TESTS=1 PASS=1 FAIL=0`).
- [x] 4.2 No regression: crc8 / turbo_encoder / internal_interleaver / qpp_rom / turbo_encode_top HDL lanes PASS; Octave `OK (passed=102)`.
- [x] 4.3 Recorded here: 11 cases bit-exact incl. filler; regression green.

## 5. Validation and Docs

- [x] 5.1 `hdl/sim/subblock_interleaver/README.md` documents schema, regeneration, run, design.
- [x] 5.2 `npx openspec validate add-fpga-subblock-interleaver --strict` — passes.
- [x] 5.3 `npx openspec validate --all --strict` — no regression.

## 6. Follow-on Note (not required for completion)

- [x] 6.1 §5.1.4.1.2 circular buffer (bit collection, rv, LBRM, `E`/bit selection, filler-skip) recorded as the explicit next follow-on; out of scope here.
