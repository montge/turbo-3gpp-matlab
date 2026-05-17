## 1. Golden-Vector Generator

- [ ] 1.1 Add `scripts/generate_hdl_subblock_interleaver_vectors.m`: for each `(D, idx)` call `subblock_interleaver(0:D-1, idx)`; map `NaN → -1`.
- [ ] 1.2 CSV schema `D,idx,pat` (pat = space-separated `K_Pi` ints, `-1`=filler) documented in the generator header.
- [ ] 1.3 Suite: encoder-relevant `D ∈ {44, 516, 6148}` plus a non-multiple-of-32 `D` exercising filler; indices `{0,2}`; plus an `idx=1` row to spot-check it equals `idx=0`.
- [ ] 1.4 Uses only `subblock_interleaver`; no MATLAB/Octave sources changed.

## 2. Sub-block Interleaver Core

- [ ] 2.1 Add `hdl/rtl/subblock_interleaver.vhdl` with the local 32-entry `P` ROM and nested counters (`r0=k mod R`, `c0=⌊k/R⌋`); `R=(D+31)>>5`, `K_Pi=R<<5`, `N_D=K_Pi-D`.
- [ ] 2.2 `pi_y = (r0<<5)+P[c0]` for idx 0/1; `+1` then single conditional subtract of `K_Pi` for idx 2; `filler = pi_y < N_D`; `d`-index `= pi_y - N_D`.
- [ ] 2.3 Streaming K-agnostic interface: `start` latches `D/idx`; `valid`/`filler`/`idx_o`/`last` stream `K_Pi` elements.

## 3. Simulation Lane

- [ ] 3.1 Add `hdl/sim/subblock_interleaver/` (Makefile + cocotb) mirroring the established lanes.
- [ ] 3.2 Driver latches `D/idx`, collects `K_Pi` (filler, d-index) pairs.
- [ ] 3.3 Assert every element matches the golden pattern; assert filler count `= K_Pi - D`.
- [ ] 3.4 Artifacts covered by existing `.gitignore`.

## 4. Verification

- [ ] 4.1 Lane PASS for all representative `(D, idx)` incl. D=6148; idx=1==idx=0 spot-check.
- [ ] 4.2 Regression: turbo / interleaver / qpp_rom / turbo_encode_top / CRC HDL lanes + Octave suite still pass.
- [ ] 4.3 Record pass results.

## 5. Validation and Docs

- [ ] 5.1 Add `hdl/sim/subblock_interleaver/README.md` (schema, regeneration, run).
- [ ] 5.2 `npx openspec validate add-fpga-subblock-interleaver --strict` passes.
- [ ] 5.3 `npx openspec validate --all --strict` — no regression.

## 6. Follow-on Note (not required for completion)

- [ ] 6.1 Record the §5.1.4.1.2 circular buffer (rv, LBRM, `E`/bit selection, filler-skip) as the explicit next follow-on; out of scope here.
