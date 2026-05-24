## ADDED Requirements

### Requirement: Turbo decoder runs self-checked on the DE2

The system SHALL provide a DE2 (`EP2C35F672C6`, Quartus II 13.0sp1)
demonstration that runs the simulator-verified iterative `turbo_decoder_top`
core at `K = 512`, decodes a committed channel-LLR golden vector to `K`
hard-decision bits, and self-checks those bits against the committed golden
decoded bits, without any host link (no UART / no screen).

#### Scenario: Demo reuses the verified decoder core unmodified

- **WHEN** the DE2 turbo-decoder demo is added
- **THEN** the board top entity instantiates `turbo_decoder_top` from
  `hdl/rtl/turbo_decoder_top.vhdl` as a component, with only generic overrides
  (`K_MAX = 512`, `MAX_ITERATIONS` set to the golden row's `max_iter`) and board
  I/O wiring (the PLL clock, a start key, LEDs, seven-segment displays)
- **AND** `hdl/rtl/turbo_decoder_top.vhdl` and its sub-cores
  (`constituent_decoder`, `qpp_rom`, `qpp_interleaver`) are not edited by the
  board layer

#### Scenario: On-chip golden vector is the oracle

- **WHEN** the demo runs
- **THEN** an on-chip ROM under `hdl/boards/de2/` holds the `K = 512` row of
  `hdl/vectors/turbo_decoder_top.csv` — its `K` and `max_iter`, the `3×(K+4)`
  channel-LLR matrix `d_a` as signed `W_EXT`-wide codes in the column-major order
  the core consumes, and the `K` expected decoded bits `c`
- **AND** the expected `c` bits come from the same MATLAB/Octave-derived
  fixed-point reference golden vectors the simulator uses

### Requirement: Demo runs on a PLL-derived slow clock

The demo SHALL clock the decoder and self-check logic from a PLL-derived clock
(Option A) at a frequency at or below the decoder's α-recurrence Fmax of
15.43 MHz, derived from the 50 MHz `CLOCK_50` board oscillator via an `altpll`
megafunction, because the constituent core's forward α recurrence is a
pre-existing combinational feedback cone that cannot run at 50 MHz and cannot be
naively pipelined.

#### Scenario: PLL derives the functional clock

- **WHEN** the demo is built
- **THEN** an `altpll` instance derives a single ~12.5 MHz output (50 MHz ÷4,
  with margin over 15.43 MHz) from `CLOCK_50`, and the `turbo_decoder_top`
  instance plus the self-check FSM are clocked by that PLL output
- **AND** `CLOCK_50` feeds only the PLL

#### Scenario: Timing closes on the derived clock

- **WHEN** the DE2 decoder-demo project is compiled with Quartus II 13.0sp1
- **THEN** the `.sdc` declares the 50 MHz `CLOCK_50`, creates the PLL-derived
  clock (via `derive_pll_clocks` or an explicit generated clock) with
  `derive_clock_uncertainty`, and false-paths the asynchronous key input and the
  LED/seven-segment outputs
- **AND** TimeQuest closes setup and hold for the PLL-derived domain with the
  ~64.8 ns α-recurrence cone met inside the derived-clock period, with no
  unconstrained-path warnings beyond the intentionally false-pathed async I/O

### Requirement: Self-check FSM compares decoded bits to the golden vector

The demo SHALL include a self-check FSM that drives the decoder's load and run
handshake, streams the stored channel-LLR matrix, and compares every streamed
decoded bit (and the end-of-stream position) against the stored expected decoded
bits, latching a sticky pass/fail result.

#### Scenario: Load, decode, and compare

- **WHEN** the FSM resets the core, pulses `in_start` with `K = 512`, streams the
  `K+4` `d_a` column beats on `da_valid` (`da1_in`/`da2_in`/`da3_in`), waits out
  the iterative decode, and captures each `out_valid` `c_out` bit
- **THEN** it compares each captured bit to the expected `c` bit at the same
  index and requires `out_last` to coincide with bit `K−1`

#### Scenario: Pass when every decoded bit matches

- **WHEN** the streamed decoded output equals the stored expected `c` for all `K`
  bits with `out_last` asserted at bit `K−1`
- **THEN** the pass result is latched and shown on a pass LED (`LEDG[0]`) and a
  pass code ("A5") on the seven-segment displays

#### Scenario: Fail on any mismatch

- **WHEN** any streamed decoded bit differs from the expected `c`, or the output
  length / `out_last` position differs from `K`
- **THEN** the fail result is latched and shown on a fail LED (`LEDR[0]`) and a
  fail code ("FF") on the seven-segment displays

### Requirement: Board constraints isolated and artifacts ignored

The demo SHALL keep its Quartus project, pin assignments, timing constraints,
`altpll` megafunction, on-chip ROM, and presentation logic under
`hdl/boards/de2/`, separate from the board-neutral `hdl/rtl/` core, and SHALL
keep Quartus build outputs out of version control.

#### Scenario: Demo sources live under the board path

- **WHEN** the demo is delivered
- **THEN** the `.qpf`, `.qsf`, `.sdc`, board wrapper, `altpll` wrapper, on-chip
  ROM, and self-check logic reside under `hdl/boards/de2/` (reusing the shared
  `hdl/boards/hex7seg.vhdl` and the verified `tx_chain_de2.qsf` pin table)
- **AND** no pin or board assignment appears in `hdl/rtl/`

#### Scenario: Build outputs are ignored

- **WHEN** the demo project is compiled
- **THEN** generated outputs (`db/`, `incremental_db/`, `output_files/`,
  `*.sof`, `*.pof`, `*.qws`, reports) are ignored by git and `git status` is
  clean aside from intentionally tracked sources

### Requirement: On-board validation against the golden vector is hardware-gated

The demo SHALL define a manual program-and-observe step whose pass criterion is
the on-chip self-check agreeing with the committed golden vector; the change
SHALL NOT require physical hardware for the GHDL self-check, fit, or timing
closure at the PLL clock to be considered complete.

#### Scenario: Programmed board self-reports pass

- **WHEN** the DE2 is programmed with the demo `.sof` and the self-check is
  triggered
- **THEN** the pass LED (`LEDG[0]`) and the pass seven-segment code ("A5")
  indicate the on-board `turbo_decoder_top` decoded the committed K=512
  channel-LLR golden vector to the expected K hard bits bit-for-bit

#### Scenario: Completion does not depend on hardware

- **WHEN** the GHDL self-check lane is green (PASS on golden, FAIL on a corrupted
  bit), the project fits, and timing closes on the PLL-derived clock under
  13.0sp1
- **THEN** the demo build is complete regardless of whether the physical
  program-and-observe step has been run
