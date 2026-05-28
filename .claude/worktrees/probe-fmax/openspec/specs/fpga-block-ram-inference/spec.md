# fpga-block-ram-inference Specification

## Purpose
Defines how the board-neutral TX-chain HDL buffers (`turbo_encode_top` `buf`,
`rate_matching_top` `d1/d2/d3buf`, `circular_buffer` `w`) infer Cyclone II
(`EP2C35F672C6`) M4K block RAM under Quartus II 13.0sp1 — via outside-the-reset
clocked writes and synchronous registered reads — so the full-`K` `tx_chain_top`
fits the EP2C35 and closes 50 MHz, validated by the two-tier (cocotb bit-exact +
Quartus fit) gate with no committed golden vector changed.

## Requirements
### Requirement: TX-chain memories infer Cyclone II M4K block RAM

The TX-chain buffers SHALL be implemented so that they infer as Cyclone II
(`EP2C35F672C6`) M4K block RAM under Quartus II 13.0sp1, rather than as LE
register/distributed-RAM fabric, while remaining bit-for-bit equal to the
software model for every supported parameter set. The buffers in scope are
`turbo_encode_top` `buf`, `rate_matching_top` `d1/d2/d3buf`, and
`circular_buffer` `w_bit`/`w_fill`.

#### Scenario: Memory write is outside the synchronous-reset FSM body

- **WHEN** a TX-chain buffer is written
- **THEN** the array write statement is at the top level of an unconditional
  clocked memory process (the synchronous reset touches only address / index /
  control registers, never the array body), so Quartus 13.0sp1 maps it to an
  M4K write port instead of reset-gated registers

#### Scenario: Synchronous registered read, no async clear on contents

- **WHEN** a TX-chain buffer is read
- **THEN** the read uses a registered address with the read data appearing one
  cycle later (synchronous read), there is no asynchronous clear on the array
  contents, and the read-during-write path never reads an address in the same
  cycle it is written — matching the M4K template

#### Scenario: Inference confirmed by the Quartus fit report

- **WHEN** the full-`K` `tx_chain_top` build is compiled under Quartus II
  13.0sp1
- **THEN** the synthesis/fit report shows `Total memory bits > 0` and an
  inferred M4K block-RAM count greater than zero for the TX buffers (not
  `Total memory bits : 0`)

### Requirement: Full-`K` TX-chain build fits the EP2C35 and closes 50 MHz

A full-capacity `tx_chain_top` build SHALL fit the DE2 `EP2C35F672C6` and close
timing at 50 MHz because the buffers infer M4K, not because the buffer depths
are parameterized down. Full-capacity means code-block length `K` up to 6144 (or
a documented intermediate maximum).

#### Scenario: Device fits at full capacity

- **WHEN** the full-`K` build is compiled (`MAXK`/`DMAX`/`KW_MAX` at their
  TS36.212 maxima or the documented intermediate)
- **THEN** logic-element usage is well within the 33,216 available (the buffers
  occupy M4K, not LE register banks), the M4K count is within the 105 available,
  and multiplier usage is zero

#### Scenario: Timing closes at 50 MHz

- **WHEN** TimeQuest analyzes the `CLOCK_50` domain of the full-`K` build
- **THEN** setup and hold slacks are positive and `Fmax ≥ 50 MHz`

### Requirement: Bit-exactness preserved by the two-tier gate

The M4K-inference rework SHALL be validated by a two-tier gate — the cocotb /
GHDL functional lanes (bit-exact, the functional oracle) AND the Quartus II
13.0sp1 fit report (the synthesis oracle) — and SHALL change no committed golden
vector.

#### Scenario: cocotb lanes stay bit-exact with vectors unchanged

- **WHEN** the `circular_buffer`, `rate_matching_top`, `turbo_encode_top`, and
  `tx_chain_top` cocotb lanes are re-run after the rework
- **THEN** every streamed output bit matches the committed
  `circular_buffer.csv` / `rate_matching.csv` / `turbo_encoder.csv` /
  `tx_chain.csv`, and those vector files are byte-identical to before

#### Scenario: Synthesis oracle recorded alongside the functional gate

- **WHEN** the change is delivered
- **THEN** the full-`K` Quartus fit report (M4K count, memory bits, LE, `Fmax`)
  is recorded as a deliverable, demonstrating `M4K > 0` against the prior K=40
  demo's `M4K = 0`

