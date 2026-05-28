## 1. Input-Validity Guards (no behaviour change for valid inputs)

- [x] 1.1 `circular_buffer.vhdl`: S_IDLE guard — `K_Pi=0` / `E=0` / (`I_LBRM` & `N_ref=0`) → `S_DONE` safe abort (no div/mod-by-zero).
- [x] 1.2 `rate_matching_top.vhdl`: S_IDLE guard — `d_len=0` or `> DMAX` → `S_DONE` safe abort.
- [x] 1.3 `subblock_interleaver.vhdl`: `d_in=0` → defined no-op (stay idle).
- [x] 1.4 `turbo_encode_top.vhdl`: S_LOOKUP honours `rom_sup` — unsupported `K` → `S_DONE` safe halt (no new port → no `tx_chain_top` ripple); supported-K path byte-identical.

## 2. Interface / Generator / Docs

- [x] 2.1 `qpp_rom.vhdl`: kept `done` LEVEL semantics (zero bit-exact risk under the hard constraint; design.md's allowed alternative) and **corrected the misleading "pulses" header** to document the held-level contract consumers rely on. (A pulse was considered and rejected to avoid any timing change to the verified integrators.)
- [x] 2.2 `scripts/generate_hdl_qpp_rom.m`: `mkdir(hdl/vectors)` guard before `fopen` (sibling pattern); re-ran → `qpp_rom.csv` **byte-identical** and `qpp_rom_pkg.vhd` unchanged (guard is inert).
- [x] 2.3 Added `bash` language to the CodeRabbit-flagged fences in `hdl/boards/de1/README.md` and `de2/README.md` (content unchanged).

## 3. Verification (the acceptance gate)

- [x] 3.1 `scripts/run_all_hdl_lanes.sh`: **all 10 lanes PASS bit-exact**; `hdl/vectors/*` and `qpp_rom_pkg.vhd` unchanged (guards additive — valid-input behaviour preserved; `tx_chain_top` integration green).
- [x] 3.2 Directed cocotb cases added (zero/over-range/unsupported-K) in the 4 affected lanes, asserting the defined safe path; all PASS (each starts its own clock — fixed a no-clock stall).
- [x] 3.3 `npx openspec validate --all --strict` 22/22. Octave suite unaffected — no MOxUnit-discovered MATLAB sources changed (only the `generate_hdl_qpp_rom.m` script, not a tested unit); CI's Octave/MOxUnit jobs reconfirm on push.

## 4. Validation and Docs

- [x] 4.1 PR #19 comment already recorded the disposition rationale; this change implements it. CodeRabbit threads close when the follow-up PR lands.
- [x] 4.2 `npx openspec validate add-fpga-core-input-hardening --strict` — passes.
- [x] 4.3 `npx openspec validate --all --strict` — no regression.

## 5. Non-Goals (record, do not implement here)

- [x] 5.1 Sliding-window / divider-free / BRAM synthesis hardening remain the separate documented follow-ons; this change is ONLY the CodeRabbit items.
