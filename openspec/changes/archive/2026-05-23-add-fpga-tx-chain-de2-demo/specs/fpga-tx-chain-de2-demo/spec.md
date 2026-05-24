## ADDED Requirements

### Requirement: TX chain runs self-checked on the DE2

The system SHALL provide a DE2 (`EP2C35F672C6`, Quartus II 13.0sp1) demonstration
that runs the simulator-verified `tx_chain_top` core, clocked by `CLOCK_50`, and
self-checks its streamed length-`E` output against a committed golden vector for
a fixed small `K`, without any host link (no UART / no screen).

#### Scenario: Demo reuses the verified core unmodified

- **WHEN** the DE2 TX demo is added
- **THEN** the board top entity instantiates `tx_chain_top` from
  `hdl/rtl/tx_chain_top.vhdl` as a component, wiring only board I/O (`CLOCK_50`,
  a start key, LEDs, seven-segment displays)
- **AND** `hdl/rtl/tx_chain_top.vhdl` is not edited by the board layer

#### Scenario: On-chip golden vector is the oracle

- **WHEN** the demo runs
- **THEN** an on-chip ROM under `hdl/boards/de2/` holds one row of
  `hdl/vectors/tx_chain.csv` for the chosen small `K` — its `(K, N_ref, I_LBRM,
  rv, E)` parameters, the `K` input bits `c`, and the `E` expected output bits
  `e`
- **AND** the expected `e` bits come from the same MATLAB/Octave-derived golden
  vectors the simulator uses

### Requirement: Self-check FSM compares output to the golden vector

The demo SHALL include a self-check FSM that drives the core's run handshake,
streams the stored input, and compares every streamed output bit (and the
end-of-stream position) against the stored expected output, latching a sticky
pass/fail result.

#### Scenario: Pass when every output bit matches

- **WHEN** the FSM clocks the core through the stored input and the streamed
  output equals the stored expected `e` for all `E` bits with `last` asserted at
  bit `E−1`
- **THEN** the pass result is latched and shown on a pass LED and a pass code on
  the seven-segment display

#### Scenario: Fail on any mismatch

- **WHEN** any streamed output bit differs from the expected `e`, or the output
  length / `last` position differs from `E`
- **THEN** the fail result is latched and shown on a fail LED and a fail code on
  the seven-segment display

### Requirement: Demo is clocked and constrained at 50 MHz

The demo SHALL be a synchronous design driven by `CLOCK_50`, with timing
constraints that define the 50 MHz clock and close timing under Quartus II
13.0sp1.

#### Scenario: Clock is defined and timing closes

- **WHEN** the DE2 TX-demo project is compiled with Quartus II 13.0sp1
- **THEN** the `.sdc` declares a 50 MHz clock on `CLOCK_50` (with
  `derive_clock_uncertainty`) and false-paths the asynchronous key input and the
  LED/seven-segment outputs
- **AND** TimeQuest closes setup and hold for the `CLOCK_50` domain with no
  unconstrained-path warnings beyond the intentionally false-pathed async I/O

#### Scenario: Fit reports headroom on the EP2C35

- **WHEN** the project is fitted
- **THEN** the design uses no multipliers and a small fraction of the M4K block
  RAM (the hardened TX chain ≈ 12 of 105 M4K), recorded in the build notes

### Requirement: Board constraints isolated and artifacts ignored

The demo SHALL keep its Quartus project, pin assignments, timing constraints,
on-chip ROM, and presentation logic under `hdl/boards/de2/`, separate from the
board-neutral `hdl/rtl/` core, and SHALL keep Quartus build outputs out of
version control.

#### Scenario: Demo sources live under the board path

- **WHEN** the demo is delivered
- **THEN** the `.qpf`, `.qsf`, `.sdc`, board wrapper, on-chip ROM, and self-check
  logic reside under `hdl/boards/de2/` (reusing the shared
  `hdl/boards/hex7seg.vhdl`)
- **AND** no pin or board assignment appears in `hdl/rtl/`

#### Scenario: Build outputs are ignored

- **WHEN** the demo project is compiled
- **THEN** generated outputs (`db/`, `incremental_db/`, `output_files/`,
  `*.sof`, `*.pof`, `*.qws`, reports) are ignored by git and `git status` is
  clean aside from intentionally tracked sources

### Requirement: On-board validation against the golden vector is hardware-gated

The demo SHALL define a manual program-and-observe step whose pass criterion is
the on-chip self-check agreeing with the committed golden vector; the change
SHALL NOT require physical hardware for the hardening, simulation gate, fit, or
timing closure to be considered complete.

#### Scenario: Programmed board self-reports pass

- **WHEN** the DE2 is programmed with the demo `.sof` and the self-check is
  triggered
- **THEN** the pass LED and pass seven-segment code indicate the on-board
  `tx_chain_top` reproduced the committed `tx_chain` golden output bit-for-bit
  for the chosen `K`

#### Scenario: Completion does not depend on hardware

- **WHEN** the cocotb gate is green, the project fits, and timing closes under
  13.0sp1
- **THEN** the hardening and demo build are complete regardless of whether the
  physical program-and-observe step has been run
