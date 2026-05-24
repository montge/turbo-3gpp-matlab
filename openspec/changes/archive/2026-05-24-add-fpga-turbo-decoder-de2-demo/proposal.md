## Why

The complete LTE **transmit** chain now runs self-checked on real DE2 silicon
(`tx_chain_top`, archived `add-fpga-tx-chain-de2-demo`: HEX = A5 + green PASS on
the K=40 golden vector). The **receive** side has only ever been proven in
simulation. The iterative turbo decoder `turbo_decoder_top` (P2 of the decoder
roadmap — the real Max-Log-MAP loop that produces hard-decision decoded bits, NOT
the CRC/HARQ `turbo_decoder_term_top`) was the synthesis blocker: its full-block
α / LLR / extrinsic stores were huge LE register banks. The just-merged
`add-fpga-decoder-block-ram-inference` work (PR #56) fixed that — every decoder
memory now infers Cyclone II M4K block RAM, and `turbo_decoder_top` at the
board-demo **K = 512** (`K_MAX = 512` → `N_MAX = 515`) **FITS the EP2C35**:
**10,978 LE / 33,216 (33 %)**, **57 / 105 M4K (54 %)**, **0 multipliers**, 0
A&S / Fitter errors.

This change is the first turbo **DECODER** on real hardware: instantiate the
sim-verified `turbo_decoder_top` core UNMODIFIED on a DE2, feed it the quantized
channel LLRs of the committed K=512 golden vector from an on-chip ROM, run the
whole-block iterative decode, collect the K hard-decision decoded bits, and
self-check them bit-for-bit against the golden decoded bits — driving LED + 7-seg
pass/fail with no host link. It complements the TX demo already on the board: a
genuine receive-path block decoding to hard bits, self-verifying against the
fixed-point reference oracle.

The one new board element versus the TX demo is the **clock**. The decoder's
forward α recurrence (a pre-existing Max-Log-MAP combinational feedback cone in
the constituent core, ~64.8 ns) caps Fmax at **15.43 MHz** — it cannot be
naively pipelined (it is a feedback recurrence). Per the user's **Option A**, the
demo therefore runs on a Cyclone II PLL-derived **~12.5 MHz** clock (`CLOCK_50`
÷4 via `altpll`), NOT 50 MHz. A K=512 whole-block decode is a few thousand to
~33k cycles depending on `MAX_ITERATIONS`, i.e. on the order of milliseconds at
12.5 MHz — instant to the eye and fine for a correctness self-check. Closing
50 MHz would require algorithmic α/β-recurrence pipelining (**Option B**, a
separate later increment, explicitly deferred here).

## What Changes

- **Add a DE2 board demo for `turbo_decoder_top`** under `hdl/boards/de2/`,
  mirroring the archived TX demo exactly:
  - a **board wrapper** (`turbo_decoder_de2_top.vhdl`) that instantiates
    `turbo_decoder_top` UNMODIFIED as a component with the generic overrides
    `K_MAX = 512`, `MAX_ITERATIONS` matching the golden row, wiring only board
    I/O (the PLL clock, a start KEY, LEDR/LEDG, HEX0/HEX1);
  - an **`altpll` instance** deriving ~12.5 MHz from `CLOCK_50` (50 MHz ÷4); the
    whole decoder + self-check FSM run on this derived clock;
  - an **on-chip golden-vector ROM** (`turbo_decoder_golden_pkg.vhdl`) holding
    the K=512 row of `hdl/vectors/turbo_decoder_top.csv`: K, `max_iter`, the
    3×(K+4) channel-LLR matrix `d_a` (W_EXT = 12 signed codes, column-major as the
    core consumes it), and the K expected decoded bits `c`;
  - a **self-check FSM** that resets the core, pulses `in_start` with K, streams
    the K+4 `d_a` column beats on `da_valid` (`da1/da2/da3_in`), waits for the
    core's `done`, captures the K `out_valid` `c_out` bits, compares each to the
    expected `c` bit at the same index, checks `out_last` lands at bit K−1, and
    latches a sticky pass / fail;
  - pass/fail/running indication on **LEDG[0]=pass / LEDR[0]=fail / LEDG[1]=run /
    LEDR[1]=done** plus a 7-seg status code (reuse the TX verdict map: pass="A5",
    fail="FF", running="00") via the shared `hdl/boards/hex7seg.vhdl`.
- **Add the Quartus project + constraints** under `hdl/boards/de2/`: `.qpf`,
  `.qsf` (device `EP2C35F672C6`, VHDL_2008, reuse the verified
  `tx_chain_de2.qsf` CLOCK_50 / KEY / LEDR / LEDG / HEX pin table, list the
  decoder RTL source files + the `altpll` megafunction), and `.sdc` that
  declares the 50 MHz `CLOCK_50`, **creates the PLL-derived ~12.5 MHz clock and
  constrains the design on it** (≥ the α-recurrence requirement, with margin over
  15.43 MHz), and false-paths the async KEY input + LED/HEX outputs.
- **Add a GHDL/cocotb self-check lane** under `hdl/sim/turbo_decoder_de2/`
  proving the wrapper reaches PASS on the genuine K=512 golden vector and FAIL on
  one corrupted expected bit (the `CORRUPT_IDX` generic, like the TX lane). The
  lane simulates at the functional clock; the multi-thousand-cycle whole-block
  decode makes it slower than the TX lane, so its cycle budget is sized
  accordingly.

All work is **proposal-only in this change** — no `hdl/`, `scripts/`, `.qsf`, or
`.m` edits land here. `turbo_decoder_top` and every sub-core
(`constituent_decoder`, `qpp_rom`, `qpp_interleaver`) are reused UNMODIFIED.

## Capabilities

### New Capabilities

- `fpga-turbo-decoder-de2-demo`: the on-chip golden-LLR ROM + self-check FSM +
  LED/7-seg pass/fail DE2 demonstration of the iterative `turbo_decoder_top` at
  K=512, clocked by a PLL-derived ~12.5 MHz domain (Option A, sized over the
  15.43 MHz α-recurrence Fmax), decoding the committed channel-LLR golden vector
  to K hard bits and self-checking them bit-for-bit against the golden decoded
  `c` — a genuinely new receive-path board behavior distinct from the TX-chain
  demo (new PLL-derived clock domain; soft-input → hard-bit decode rather than
  bit-in → bit-out encode).

### Modified Capabilities

None. `turbo_decoder_top` and its sub-cores are reused unmodified, and the
`fpga-tx-chain-de2-demo` capability is unaffected. The clocked, ROM-fed,
self-checking decoder demo on a PLL-derived domain is a new shape of board
behavior, so it gets its own capability rather than overloading the TX-demo spec.

## Impact

- **Planning only in this change** — no `hdl/`, `scripts/`, `.qsf`, or `.m`
  edits land here. This is the proposal; implementation follows in the staged
  `tasks.md`.
- When implemented: new files under `hdl/boards/de2/` (decoder demo wrapper,
  `altpll` megafunction, on-chip golden ROM `turbo_decoder_golden_pkg.vhdl`,
  `turbo_decoder_de2.qpf`/`.qsf`/`.sdc`, README) and a new GHDL self-check lane
  under `hdl/sim/turbo_decoder_de2/`. Nothing under `hdl/rtl/` changes.
- The decoder fit is already characterized (PR #56 / decoder roadmap §6):
  10,978 LE / 33 %, 57 M4K / 54 %, 0 DSP at K=512 — comfortable headroom on the
  EP2C35. The on-chip ROM (3×516×12 ≈ 18.5 Kbit of `d_a` + 512-bit `c`) adds a
  trivial amount of M4K.
- Depends on Quartus II 13.0sp1 on the existing Windows host; board
  synthesis/program remains a local/manual step, not CI. Requires physical DE2
  hardware only for the final program-and-observe step; the GHDL self-check, fit,
  and timing closure at the PLL clock are all verifiable without a board.

## Out of Scope (explicit)

- `turbo_decoder_term_top` (CRC-aided early termination / HARQ accumulation) —
  this demo runs the plain fixed-iteration `turbo_decoder_top`.
- Full K = 6144 on the board (needs the M2 sliding-window BCJR rework; this demo
  is the K=512 whole-block decode that fits today).
- α/β forward-recurrence pipelining to close 50 MHz (**Option B**, a separate
  algorithmic increment) — the demo uses the Option A PLL slow clock instead.
- UART or any host link (on-chip ROM + self-check is the only I/O).
- Multi-vector or parameter-swept on-board runs (the demo fixes the single
  committed K=512 vector); DE1 decoder demo.
