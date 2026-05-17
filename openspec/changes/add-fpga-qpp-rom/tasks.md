## 1. Generated ROM Package + Golden List

- [ ] 1.1 Add `scripts/generate_hdl_qpp_rom.m`: read `internal_interleaver.m`'s `parameters` table, compute `d0=mod(f1+f2,K)`, `step=mod(2*f2,K)` per row.
- [ ] 1.2 Emit committed `hdl/rtl/qpp_rom_pkg.vhd` (188-entry constant table) and a `hdl/vectors/qpp_rom.csv` golden list (`K,d0,step`).
- [ ] 1.3 Generator uses only the existing helper's table; no MATLAB/Octave sources changed.

## 2. ROM Lookup Core

- [ ] 2.1 Add `hdl/rtl/qpp_rom.vhdl`: sequential scan over the 188-entry package, `start`/`K` in → `d0,step,supported,done` out (≤188 cycles).
- [ ] 2.2 Unsupported `K` deasserts `supported`.

## 3. Integrated Datapath

- [ ] 3.1 Add `hdl/rtl/turbo_encode_top.vhdl`: block buffer (1 write, 2 async read ports) + `qpp_rom` + `qpp_interleaver` + `turbo_encoder`, all sub-cores unmodified.
- [ ] 3.2 FSM: load `K` bits → ROM lookup → run interleaver, per step `i` feed `buf(i)`/`buf(pi(i))` to the encoder data phase → 3 term steps → 4 emit cycles.
- [ ] 3.3 Interface: `(K, c stream)` in → streamed `3×(K+4)` `d` out; K-agnostic.

## 4. Simulation Lanes

- [ ] 4.1 `hdl/sim/qpp_rom/` (Makefile + cocotb): every `K` in `qpp_rom.csv` → correct `d0/step/supported`; a couple unsupported `K` → `supported=0`.
- [ ] 4.2 `hdl/sim/turbo_encode_top/` (Makefile + cocotb): reuse `hdl/vectors/turbo_encoder.csv`, drive only `K`+`c`, assert produced `d` equals expected.
- [ ] 4.3 Simulator artifacts covered by existing `.gitignore`.

## 5. Verification

- [ ] 5.1 Run both new lanes; confirm PASS incl. K=6144.
- [ ] 5.2 Regression: turbo, interleaver, CRC HDL lanes + Octave suite still pass.
- [ ] 5.3 Record pass results in the change.

## 6. Validation and Docs

- [ ] 6.1 Add `hdl/sim/turbo_encode_top/README.md` (integration overview, regeneration, run).
- [ ] 6.2 `npx openspec validate add-fpga-qpp-rom --strict` passes.
- [ ] 6.3 `npx openspec validate --all --strict` — no regression.

## 7. Follow-on Note (not required for completion)

- [ ] 7.1 Record BRAM/true-dual-port + pipelined lookup (throughput) and an optional DE2 demo as the explicit next follow-on; out of scope here.
