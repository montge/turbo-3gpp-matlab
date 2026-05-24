## 1. DE2 board demo — wrapper + altpll + golden-LLR ROM + self-check FSM

- [x] 1.1 Extract the **K=512** row of `hdl/vectors/turbo_decoder_top.csv` and
  record the exact `(K, max_iter, d_a, c)` values used: `K = 512`,
  `max_iter = 2` (→ H = 4), `d_a` = 3×516 = 1548 signed W_EXT (12-bit)
  channel-LLR codes (column-major), `c` = 512 expected hard-decision bits.
- [x] 1.2 Add an on-chip golden-vector ROM `hdl/boards/de2/turbo_decoder_golden_pkg.vhdl`
  holding that row as VHDL constants (board-presentation data, NOT under
  `hdl/rtl/`): `GV_K`, `GV_MAX_ITER`, `GV_DA` (the 3×(K+4) W_EXT codes in
  column-major load order), and `GV_C` (the K expected decoded bits, index 0 =
  first `c_out` bit). Mirror the `tx_chain_golden_pkg` provenance comment.
- [x] 1.3 Add an `altpll` megafunction (Cyclone II) deriving **~12.5 MHz** from
  `CLOCK_50` (50 MHz ÷4), with a `locked` output; store its generated wrapper
  under `hdl/boards/de2/`. (Prefer the PLL over a ripple divider so TimeQuest
  sees a clean derived clock.)
- [x] 1.4 Add the self-check FSM (in the wrapper): `CH_RESET` → `CH_START`
  (pulse `in_start`, `k_in = 512`) → `CH_LOAD` (stream the 516 `d_a` column
  beats on `da_valid` with `da1/da2/da3_in = GV_DA` column) → `CH_RUN` (wait for
  `out_valid`, capture each `c_out`, compare to `GV_C(cmp_idx)`, require
  `out_last` at `cmp_idx = K−1`) → sticky `CH_PASS` / `CH_FAIL`. Include the
  TEST-ONLY `CORRUPT_IDX` generic (default −1) that flips one expected bit.
- [x] 1.5 Add the DE2 board wrapper `hdl/boards/de2/turbo_decoder_de2_top.vhdl`
  instantiating `turbo_decoder_top` **UNMODIFIED** with generic overrides
  `K_MAX => 512`, `MAX_ITERATIONS => GV_MAX_ITER`; clock the core + FSM from the
  PLL output; drive `LEDG[0]=pass / LEDR[0]=fail / LEDG[1]=running / LEDR[1]=done`
  plus a 7-seg status code (pass="A5", fail="FF", running="00") via two shared
  `hdl/boards/hex7seg.vhdl` instances. Synchronize + edge-detect KEY[0] for
  restart (reuse the TX wrapper's KEY logic).
- [x] 1.6 Add the Quartus project + constraints under `hdl/boards/de2/`:
  `turbo_decoder_de2.qpf`; `.qsf` (device `EP2C35F672C6`, `FAMILY "Cyclone II"`,
  `VHDL_INPUT_VERSION VHDL_2008`, top `turbo_decoder_de2_top`, reuse the verified
  `tx_chain_de2.qsf` CLOCK_50/KEY/LEDR/LEDG/HEX pin table, source list = decoder
  RTL + altpll wrapper + hex7seg + golden pkg + wrapper); `.sdc` (`create_clock`
  20 ns on `CLOCK_50`, `derive_pll_clocks` for the PLL output,
  `derive_clock_uncertainty`, `set_false_path` on the async KEY input and
  LED/HEX outputs).

## 2. GHDL self-check lane (PASS on golden, FAIL on corrupt)

- [x] 2.1 Add `hdl/sim/turbo_decoder_de2/` (Makefile + test module +
  `test_runner.py`) mirroring `hdl/sim/tx_chain_de2/`: elaborate
  `turbo_decoder_de2_top` with the decoder RTL + golden pkg + wrapper sources,
  `--std=08`. Drive the decoder/FSM from a behavioral clock (the PLL hard block
  is not simulated by GHDL — drive the functional clock or a ÷4 model directly;
  the bit-exact check is clock-rate-agnostic).
- [x] 2.2 Assert the verdict: with `CORRUPT_IDX = -1` (real board behaviour) the
  self-check reaches **PASS** (LEDG[0] + HEX "A5") on the genuine K=512 golden
  vector; with `CORRUPT_IDX` = a valid index (one expected bit flipped) it
  reaches **FAIL** (LEDR[0] + HEX "FF"). Size the cocotb cycle-budget loop for
  the whole-block K=512 decode — it is markedly slower than the TX lane (the
  multi-thousand-cycle iterate-then-stream latency); budget for the long run.

## 3. Quartus fit + timing closure at the PLL clock (no board required)

- [x] 3.1 Compile the DE2 decoder-demo project under Quartus II 13.0sp1 — Full
  Compilation, 0 errors, no unsupported-family / unconstrained-device errors;
  the `altpll` elaborates for Cyclone II.
- [x] 3.2 Record the fit (LE / M4K / DSP / memory bits). Expectation from the
  characterized K=512 build (PR #56): ~10,978 LE / 33 %, ~57 M4K + the small
  golden ROM (~2 more M4K) / 105, 0 multipliers. Confirm 0 A&S / Fitter errors.
- [x] 3.3 Confirm TimeQuest closes setup and hold on the **PLL-derived ~12.5 MHz
  domain** (the 64.8 ns α-recurrence cone ≪ the 80 ns period). Report the
  derived-clock Fmax / setup-slack / hold-slack; confirm the ~12.5 MHz constraint
  is met over the 15.43 MHz core requirement; no unconstrained-path warnings
  beyond the intentionally false-pathed async I/O.
- [x] 3.4 Confirm `git status` after compile shows only intended sources (no
  `db/`, `incremental_db/`, `output_files/`, `*.sof`, `*.pof`, report artifacts)
  — `.gitignore` covers the new project.

## 4. On-board program-and-observe (hardware-gated — USER's board)

- [ ] 4.1 Program the DE2 (`quartus_pgm -c USB-Blaster -m jtag -o
  "p;output_files/turbo_decoder_de2.sof"`, 13.0sp1) — configuration succeeds.
- [ ] 4.2 Trigger the self-check (power-up free-run or KEY[0]); confirm the
  **pass** LED (LEDG[0]) lights and the 7-seg shows "A5" — i.e. the on-board
  `turbo_decoder_top` decoded the committed K=512 channel-LLR golden vector to
  the expected K hard bits bit-for-bit. Record the board, cable, device JTAG ID,
  and the observed pass/fail.

## 5. Documentation + validation

- [x] 5.1 Add an `hdl/boards/de2/turbo_decoder_de2_README.md` (mirror the TX
  demo README): the chosen K=512 / `max_iter` vector row, the Option-A PLL clock
  rationale (~12.5 MHz over the 15.43 MHz α-recurrence Fmax), build + program
  commands, what the LEDs / 7-seg mean, and how to read pass/fail.
- [x] 5.2 Run `npx openspec validate add-fpga-turbo-decoder-de2-demo --strict`
  and `npx openspec validate --all --strict` — both pass, no regression.
- [x] 5.3 Re-run the relevant GHDL lanes (`turbo_decoder_de2` self-check at
  minimum, plus `turbo_decoder_top` / `constituent_decoder` to confirm the core
  is untouched) — all green bit-for-bit, golden vectors byte-identical.

> **Dual gate:** the GHDL self-check (bit-exact PASS-on-golden / FAIL-on-corrupt
> verdict) + the Quartus fit and timing closure at the PLL clock complete the
> change without hardware; the on-board run (task 4) is the hardware oracle.
