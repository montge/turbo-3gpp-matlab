## Context

The iterative turbo decoder is sim-complete and bit-exact in GHDL/cocotb:

```
turbo_decoder_top  =  constituent_decoder (UNMODIFIED, the P1 Max-Log-MAP BCJR)
                       + qpp_rom + qpp_interleaver (UNMODIFIED)
                       wrapped in the H = 2·MAX_ITERATIONS half-iteration loop
                       (even = UPPER, odd = LOWER), hard-decision over K bits.
```

Two things changed the calculus for a board target:

1. **It fits now.** `add-fpga-decoder-block-ram-inference` (PR #56, decoder
   roadmap §6) made every `turbo_decoder_top`-path memory infer Cyclone II M4K
   block RAM (write lifted out of the reset-guarded FSM, registered/synchronous
   read, `ramstyle = "M4K"`, `ca_mem` as a simple-dual-port scatter), bit-exact
   to the fixed-point reference. A Quartus II 13.0sp1 fit of `turbo_decoder_top`
   at the board-demo **K = 512** (`K_MAX = 512` → `N_MAX = 515`),
   `EP2C35F672C6`, VHDL_2008:

   | | value |
   |---|---|
   | Logic elements | 10,978 / 33,216 (33 %) |
   | M4K | 57 / 105 (54 %) |
   | Total memory bits | 162,206 / 483,840 (34 %) |
   | Registers | 1,404 |
   | Embedded multipliers | 0 / 70 |
   | Fit result | **FITS** (0 A&S / Fitter errors) |

2. **It is slow.** The sign-off slow-model **Fmax = 15.43 MHz**. The critical
   path is the constituent core's **forward α recurrence**
   (`constituent_decoder` `alpha_prev`: an 8-way saturating-add → max-norm →
   saturate combinational cone, ~64.8 ns). This cone is **pre-existing in the
   Max-Log-MAP algorithm** — it is NOT introduced by the M4K rework, and it is
   the same ~15 MHz limit the constituent core hits standalone. It is a
   **feedback recurrence** (αₖ depends on αₖ₋₁), so it cannot be naively
   pipelined; cutting it needs the algorithmic α/β-recurrence pipelining of a
   separate increment.

The user has locked **Option A: run the demo on a slower clock.** A
PLL-derived ~12.5 MHz domain (`CLOCK_50` ÷4 via `altpll`) clears the 15.43 MHz
requirement with margin, and a whole-block K=512 decode (~4·H·K cycles; with the
golden row's `max_iter = 2` → H = 4 this is on the order of a few thousand
constituent + interleave cycles, well under ~33k even at the H = 16 maximum) runs
in single-digit milliseconds — instant for a correctness self-check.

The archived `add-fpga-tx-chain-de2-demo` is the template for everything except
the clock: board wrapper instantiating the core unmodified, on-chip golden ROM
(`tx_chain_golden_pkg` pattern), self-check FSM, LEDR/LEDG/HEX verdict via
`hex7seg`, `.qsf`/`.sdc`/`.qpf`, and a GHDL self-check lane (PASS on golden /
FAIL on corrupt).

## Goals / Non-Goals

**Goals:**

- Demonstrate the iterative `turbo_decoder_top` on a real DE2 at K=512: feed the
  committed channel-LLR golden vector from an on-chip ROM, run the whole-block
  decode, self-check the K hard-decision bits bit-for-bit against the golden
  decoded `c`, and report pass/fail on LED + 7-seg with no host link.
- Run on a PLL-derived ~12.5 MHz clock (Option A) and constrain TimeQuest on that
  derived clock so timing closes over the 15.43 MHz α-recurrence requirement.
- Instantiate `turbo_decoder_top` and every sub-core UNMODIFIED (only generic
  overrides `K_MAX = 512`, `MAX_ITERATIONS` = the golden row's `max_iter`).
- Prove the verdict in GHDL (PASS on golden, FAIL on a corrupted bit) before any
  board step; report fit (LE / M4K) and timing closure at the PLL clock.

**Non-Goals:**

- No `turbo_decoder_term_top` (CRC/HARQ), no full K = 6144 (needs M2
  sliding-window), no α/β-recurrence pipelining (Option B), no UART, no DE1
  decoder demo, no multi-vector board run (see proposal Out of Scope).
- No RTL change to `turbo_decoder_top` or any sub-core; no fixed-point / width
  retuning (the pinned Q-formats are inherited).
- No CI synthesis lane; board synthesis/program stays local/manual (as the TX
  demo).

## Decisions

### 1. Option A — PLL-derived ~12.5 MHz clock (the one new board element)

- **`altpll` megafunction**, `CLOCK_50` (50 MHz, `PIN_N2`) in → one output at
  **12.5 MHz** (÷4). A PLL is preferred over a ripple counter-divider so Quartus
  TimeQuest analyzes a clean, named derived clock (the divider would create a
  gated/ripple clock TimeQuest cannot constrain cleanly).
- The **entire demo** (the `turbo_decoder_top` instance and the self-check FSM)
  is clocked by the PLL output. The 50 MHz `CLOCK_50` only feeds the PLL.
- **`.sdc`:** `create_clock` 20 ns on `CLOCK_50`; `derive_pll_clocks` (so the
  PLL output is auto-created from the megafunction parameters) **or** an explicit
  `create_generated_clock` on the PLL output net; `derive_clock_uncertainty`;
  `set_false_path` on the async KEY input and the LED/HEX outputs. TimeQuest must
  close setup/hold on the **PLL-derived domain** with margin (the 64.8 ns
  α-recurrence ≪ the 80 ns 12.5 MHz period).
- **Why 12.5 MHz / ÷4:** the first integer-friendly PLL ratio that clears
  15.43 MHz with comfortable margin (80 ns period vs the 64.8 ns critical cone =
  ~15 ns slack before uncertainty). Open question below: confirm the exact target
  MHz / ratio (e.g. ÷3 → 16.67 MHz is tighter; ÷4 → 12.5 MHz is safe).

### 2. Board wrapper instantiates `turbo_decoder_top` UNMODIFIED

- `turbo_decoder_de2_top.vhdl` declares `turbo_decoder_top` as a component and
  generic-maps **`K_MAX => 512`** (→ `N_MAX = 515` internally) and
  **`MAX_ITERATIONS => GV_MAX_ITER`** (the golden row's `max_iter`). All width
  generics (`W_IN`, `W_EXT`, `W_ACC`, …) keep their pinned defaults.
- Port wiring: `clk => pll_clk`, `rst`, `in_start`, `k_in => K=512`, the load
  stream `da_valid` / `da1_in` / `da2_in` / `da3_in` (W_EXT = 12 wide), and the
  outputs `out_valid` / `out_last` / `c_out` / `busy` / `done`.
- No file under `hdl/rtl/` is edited by the board layer (same discipline as the
  TX demo).

### 3. On-chip golden-vector ROM (`turbo_decoder_golden_pkg`)

- Holds the **K = 512** row of `hdl/vectors/turbo_decoder_top.csv`:
  - `GV_K = 512`, `GV_MAX_ITER = 2` (→ H = 4 half-iterations);
  - `GV_DA` — the **3×(K+4) = 3×516 = 1548** channel-LLR codes, stored as signed
    W_EXT (12-bit) constants in **column-major** order exactly as the core
    consumes them (each load beat presents `d_a(1,col)`/`d_a(2,col)`/`d_a(3,col)`
    on `da1/da2/da3_in`), so the ROM is naturally 516 columns × 3 rows;
  - `GV_C` — the **512** expected hard-decision decoded bits (index 0 = first
    `c_out` bit).
- Same provenance discipline as `tx_chain_golden_pkg`: board-presentation data
  only, lives under `hdl/boards/de2/`, copied verbatim from the committed CSV row
  that the `turbo_decoder_top` cocotb lane already checks; the RTL core is unaware
  of it.

### 4. Self-check FSM (mirror the TX verdict harness)

States (decoder-shaped variant of the TX FSM):

- `CH_RESET` — hold the core in reset one PLL cycle.
- `CH_START` — present `k_in = 512`, pulse `in_start` (core S_IDLE → S_LOAD_D).
- `CH_LOAD` — stream the 516 `d_a` column beats with `da_valid = '1'`, presenting
  `GV_DA` column `lcol` on `da1/da2/da3_in`; advance until `lcol = K+3`.
- `CH_RUN` — drop `da_valid`; wait for the core to iterate (H half-iterations)
  and assert `out_valid`. Capture each `c_out` bit, compare to `GV_C(cmp_idx)`;
  on mismatch → `CH_FAIL`; require `out_last` exactly at `cmp_idx = K−1`; on the
  matched last bit → `CH_PASS`. A `done` pulse with the wrong output length, or
  `out_last` early/late, is a FAIL (same length/last discipline as the TX FSM).
- `CH_PASS` / `CH_FAIL` — sticky verdict.

The core's `done` is a one-cycle pulse after the K-bit output stream; the FSM
keys off `out_valid` / `out_last` for the compare (the long ~thousands-of-cycles
decode latency between `CH_LOAD` finishing and the first `out_valid` is simply
waited out — no timeout in hardware; the GHDL lane sizes its loop budget to it).

**Verdict mapping (reuse the TX demo verbatim):** `LEDG[0] = pass`,
`LEDR[0] = fail`, `LEDG[1] = running` (= `not done`), `LEDR[1] = done`; HEX
`hex0/hex1` nibbles → pass = "A5", fail = "FF", running = "00" via two `hex7seg`
instances. A `CORRUPT_IDX` generic (default −1) flips one expected `c` bit for
the GHDL FAIL proof, exactly as `tx_chain_de2_top`.

### 5. Pins / device / project (reuse `tx_chain_de2`)

- Device `EP2C35F672C6`, `FAMILY "Cyclone II"`, `VHDL_INPUT_VERSION VHDL_2008`,
  Quartus 13.0sp1, top entity `turbo_decoder_de2_top`.
- Reuse the verified `tx_chain_de2.qsf` pin table verbatim: `CLOCK_50 = PIN_N2`,
  `KEY[0] = PIN_G26` (start/restart), `LEDR[1:0]`, `LEDG[1:0]`, `HEX0[6:0]`,
  `HEX1[6:0]`. `RESERVE_ALL_UNUSED_PINS "AS INPUT TRI-STATED"`,
  `STRATIX_DEVICE_IO_STANDARD "3.3-V LVTTL"`.
- Source list: the decoder RTL (`qpp_rom_pkg.vhd`, `qpp_rom.vhdl`,
  `qpp_interleaver.vhdl`, `constituent_decoder.vhdl`, `turbo_decoder_top.vhdl`),
  the `altpll` megafunction wrapper, `../hex7seg.vhdl`,
  `turbo_decoder_golden_pkg.vhdl`, and `turbo_decoder_de2_top.vhdl`.

## Risks / Trade-offs

- **PLL configuration correctness (top new risk).** The `altpll` must be
  parameterized for the Cyclone II PLL (50 MHz in, 12.5 MHz out, locked) and the
  `.sdc` must constrain the *derived* clock, not `CLOCK_50`. *Mitigation:* use
  `derive_pll_clocks` so TimeQuest takes the PLL parameters as the source of
  truth; report the PLL-output Fmax/slack as a task deliverable; the GHDL lane can
  drive the PLL output net directly (or model ÷4) since GHDL does not simulate the
  PLL hard block.
- **Long decode latency vs the self-check handshake.** Thousands of cycles elapse
  between the last `d_a` load beat and the first `out_valid`. *Mitigation:* the
  hardware FSM simply waits on `out_valid` (no timeout); the GHDL lane sizes its
  cycle-budget loop generously for the whole-block decode (slower than the TX
  lane — budget for it), and times out only as a test-harness guard.
- **Verifying the PLL-derived clock domain in GHDL.** GHDL will not elaborate the
  Cyclone II `altpll` hard block. *Mitigation:* the sim lane either drives the
  decoder/FSM from a behavioral ÷4 clock (or the functional clock directly — the
  decode is clock-rate-agnostic for a bit-exact check), keeping the GHDL gate
  purely functional; the PLL is exercised only by Quartus elaboration + the
  on-board run.
- **ROM size.** 3×516×12 ≈ 18.5 Kbit of `d_a` + 512-bit `c` is trivial — it fits
  in a couple of M4K, on top of the decoder's 57; no fit pressure.
- **Bit-exactness preserved.** The core is unmodified and the golden row is copied
  verbatim, so the on-board decode must reproduce the committed `c` exactly — the
  same contract the `turbo_decoder_top` cocotb lane already enforces.

## Open Questions

- **Exact PLL target MHz / ratio.** Default ÷4 → 12.5 MHz (80 ns period, ~15 ns
  raw slack over the 64.8 ns cone before uncertainty). Confirm, or pick ÷3 →
  16.67 MHz if more throughput is wanted and timing still closes after
  `derive_clock_uncertainty`. The locked decision is "slower clock with margin
  over 15.43 MHz"; the precise number is the main open question.
- **Show the iteration count on HEX?** Default: status only (pass/fail/running),
  matching the TX demo. Optionally HEX could show `MAX_ITERATIONS` or a small
  output signature — out of scope unless requested.
- **Single K=512 vector, or a couple?** Default: the one committed K=512 row
  (smallest decoder vector that exercises the full loop at a board-relevant size).
  A second vector would grow the ROM but is otherwise mechanical.
- **`MAX_ITERATIONS` source.** The golden K=512 row is `max_iter = 2` (H = 4);
  the wrapper sets `MAX_ITERATIONS => 2` to match. Confirm whether the board
  build should pin a different iteration count (would need a matching golden row).
