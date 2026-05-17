## 1. Generated ROM Package + Golden List

- [x] 1.1 `scripts/generate_hdl_qpp_rom.m` parses the `parameters` table out of `internal_interleaver.m`; computes `d0=mod(f1+f2,K)`, `step=mod(2*f2,K)`.
- [x] 1.2 Emits committed `hdl/rtl/qpp_rom_pkg.vhd` (188-entry `QPP_TABLE`) + `hdl/vectors/qpp_rom.csv` (`K,d0,step`). (Constant named `QPP_TABLE` — `QPP_ROM` collided case-insensitively with the entity in GHDL.)
- [x] 1.3 Generator reads only the existing helper's embedded table; no MATLAB/Octave sources changed.

## 2. ROM Lookup Core

- [x] 2.1 `hdl/rtl/qpp_rom.vhdl`: sequential scan over `QPP_TABLE`, `start`/`k_in` → `d0/step/supported/done` (≤188 cycles).
- [x] 2.2 Unsupported `K` deasserts `supported` (verified for 41/100/6143).

## 3. Integrated Datapath

- [x] 3.1 `hdl/rtl/turbo_encode_top.vhdl`: input buffer (1 write, 2 async read) + `qpp_rom` + `qpp_interleaver` + `turbo_encoder`, all sub-cores unmodified.
- [x] 3.2 FSM: LOAD → ROM lookup → per step `i` feed `buf(i)`/`buf(pi(i))` to the encoder data phase → 3 term → 4 emit. Control signals are combinational (Mealy) so sub-cores sample aligned.
- [x] 3.3 Interface `(K, c stream)` → streamed `3×(K+4)` `d`; K-agnostic.

## 4. Simulation Lanes

- [x] 4.1 `hdl/sim/qpp_rom/` — every `K` in `qpp_rom.csv` → correct `d0/step/supported`; unsupported → `supported=0`. PASS.
- [x] 4.2 `hdl/sim/turbo_encode_top/` — reuses `hdl/vectors/turbo_encoder.csv`, drives only `K`+`c`, asserts produced `d`. PASS (all 18 cases).
- [x] 4.3 Artifacts covered by existing `.gitignore` (`sim_build/`, `*.vcd`, `results.xml`).

## 5. Verification

- [x] 5.1 Both new lanes PASS incl. K=6144 (`TESTS=1 PASS=1 FAIL=0`).
- [x] 5.2 No regression: turbo `PASS`, interleaver `PASS`, CRC8 `PASS`, Octave `OK (passed=102)`.
- [x] 5.3 Recorded here: ROM 188/188 + 3 unsupported; end-to-end 18/18 bit-exact; regression green.

## 6. Validation and Docs

- [x] 6.1 `hdl/sim/turbo_encode_top/README.md` documents the integration, ROM regeneration, and runs.
- [x] 6.2 `npx openspec validate add-fpga-qpp-rom --strict` — passes.
- [x] 6.3 `npx openspec validate --all --strict` — no regression.

## 7. Follow-on Note (not required for completion)

- [x] 7.1 BRAM/true-dual-port + pipelined lookup (throughput) and an optional DE2 demo recorded as the explicit next follow-on; out of scope here.
