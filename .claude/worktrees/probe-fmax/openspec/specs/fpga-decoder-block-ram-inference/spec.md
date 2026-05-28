# fpga-decoder-block-ram-inference Specification

## Purpose
Defines the Cyclone II (`EP2C35F672C6`) M4K block-RAM inference contract for the
decoder datapath (the on-chip-memory increment of the staged decoder roadmap):
the constituent decoder's `alpha_mem`/`xa_mem`/`za_mem` and the loop core's
`za_mem`/`zpa_mem`/`chs_mem`/`ca_mem`/`ce_mem`/`xpa_body`/`xpe_body` are coded so
Quartus II 13.0sp1 maps them to M4K block RAM (writes lifted out of the
synchronous-reset FSM body, registered reads, `ca_mem` as a simple-dual-port
scatter/read), letting the `K = 512` `turbo_decoder_top` fit the DE2 EP2C35
without LE register banks or multipliers; validated by a two-tier gate — the
bit-exact decoder cocotb/GHDL lanes with golden vectors unchanged and the
Quartus fit report as the synthesis oracle.
## Requirements
### Requirement: Decoder memories infer Cyclone II M4K block RAM

The `turbo_decoder_top`-path memories SHALL be implemented so that they infer as
Cyclone II (`EP2C35F672C6`) M4K block RAM under Quartus II 13.0sp1, rather than
as LE register / distributed-RAM fabric, while remaining bit-for-bit equal to
the fixed-point reference for every supported parameter set. The memories in
scope are the constituent decoder's `alpha_mem`, `xa_mem`, and `za_mem`, and the
loop core's `za_mem`, `zpa_mem`, `chs_mem`, `ca_mem`, `ce_mem`, `xpa_body`, and
`xpe_body`. The `turbo_decoder_term_top` HARQ buffer and `crc24_check` matrices
are explicitly out of scope.

#### Scenario: Memory write is outside the synchronous-reset FSM body

- **WHEN** a decoder-path memory is written
- **THEN** the array write statement is at the top level of an unconditional
  clocked memory process (the synchronous reset touches only address / index /
  control registers, never the array body), so Quartus 13.0sp1 maps it to an
  M4K write port instead of reset-gated registers

#### Scenario: Synchronous registered read, no async clear on contents

- **WHEN** a decoder-path memory is read
- **THEN** the read uses a registered address with the read data appearing one
  cycle later (synchronous read), there is no asynchronous clear on the array
  contents, and the read-during-write path never reads an address in the same
  cycle it is written — matching the M4K template

#### Scenario: Inference confirmed by the Quartus fit report

- **WHEN** a `turbo_decoder_top` build is compiled under Quartus II 13.0sp1
- **THEN** the synthesis/fit report shows `Total memory bits > 0` and an
  inferred M4K block-RAM count greater than zero for the decoder memories (not
  `Total memory bits : 0`)

### Requirement: `turbo_decoder_top` board build fits the EP2C35 and closes 50 MHz

A `turbo_decoder_top` build SHALL fit the DE2 `EP2C35F672C6` and close timing at
50 MHz because the memories infer M4K, not because the memory depths are
parameterized down. The board demo target is code-block length `K = 512`; the
inference property is also demonstrated at the cores' default `K_MAX` (or a
documented intermediate maximum, since the full-block α store exceeds on-chip
RAM near `K ≈ 2700`).

#### Scenario: Device fits at the board-demo K

- **WHEN** the `K = 512` build is compiled
- **THEN** logic-element usage is well within the 33,216 available (the α / LLR
  / extrinsic stores occupy M4K, not LE register banks), the M4K count is within
  the 105 available, and multiplier usage is zero

#### Scenario: Timing closes at 50 MHz

- **WHEN** TimeQuest analyzes the `CLOCK_50` domain of the `K = 512` build
- **THEN** setup and hold slacks are positive and `Fmax ≥ 50 MHz`

### Requirement: `ca_mem` deinterleave scatter is a simple-dual-port M4K

The loop core's `ca_mem` SHALL be implemented as a simple-dual-port M4K block
RAM — one write port driven at the data-dependent QPP-deinterleave scatter
index, one sequential read port for the accumulate and final-decision reads —
with read-during-write semantics that match the fixed-point reference, while
remaining bit-for-bit equal to the reference for every supported parameter set.

#### Scenario: Scatter write and sequential read on disjoint ports

- **WHEN** the deinterleave scatter `ca_mem(pi_idx) <= xpe_body(pi_k)` runs in
  the lower half-iteration
- **THEN** the write uses the simple-dual-port write port at the data-dependent
  `pi_idx`, the accumulate (`ca_mem(feed_idx)`) and final-decision
  (`ca_mem(out_idx)`) reads use the registered read port, and the scatter and
  read phases stay disjoint so no address is read in the same cycle it is
  written

#### Scenario: Read-during-write semantics match the reference

- **WHEN** the inferred `ca_mem` SDP is compiled under Quartus II 13.0sp1
- **THEN** its `READ_DURING_WRITE_MODE` (OLD_DATA / don't-care) produces decoded
  bits bit-identical to the GHDL behavioural model, confirmed by the
  `turbo_decoder_top` cocotb lane with golden vectors unchanged

### Requirement: Bit-exactness preserved by the two-tier gate

The M4K-inference rework SHALL be validated by a two-tier gate — the decoder
cocotb / GHDL functional lanes (bit-exact, the functional oracle) AND the
Quartus II 13.0sp1 fit report (the synthesis oracle) — and SHALL change no
committed golden vector. The functional gate includes the
`turbo_decoder_term_top` lane because it instantiates the reworked
`constituent_decoder` and `turbo_decoder_top` cores.

#### Scenario: Decoder lanes stay bit-exact with vectors unchanged

- **WHEN** the `constituent_decoder`, `turbo_decoder_top`, and
  `turbo_decoder_term_top` cocotb lanes are re-run after the rework
- **THEN** every decoded / extrinsic value matches the committed golden vectors,
  and those vector files are byte-identical to before

#### Scenario: Synthesis oracle recorded alongside the functional gate

- **WHEN** the change is delivered
- **THEN** the `K = 512` `turbo_decoder_top` Quartus fit report (M4K count,
  memory bits, LE, multiplier count, `Fmax`) is recorded as a deliverable,
  demonstrating `M4K > 0` and a fitting device against the as-is LE-banked
  decoder

