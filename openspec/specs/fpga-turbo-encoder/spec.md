# fpga-turbo-encoder Specification

## Purpose
Defines the board-neutral HDL implementation of the TS36.212 §5.1.3.2 rate-1/3
turbo encoder: a recursive-systematic constituent encoder with 3-step trellis
termination, a K-agnostic streaming turbo-encoder core that assembles the
`3 × (K+4)` systematic/parity layout (with the interleaved order supplied
externally), its cocotb/GHDL golden-vector simulation against the MATLAB/Octave
model, and an optional deferred board demonstration.
## Requirements
### Requirement: Board-neutral recursive-systematic constituent encoder

The system SHALL provide a synthesizable, board-neutral VHDL constituent
encoder under `hdl/rtl/` implementing the TS36.212 §5.1.3.2 recursive
systematic convolutional code: 3 memory elements, generator `[1,1,0,1]`,
feedback `[1,0,1,1]`, with the 3-step trellis termination that forces the
shift-register state to zero.

#### Scenario: Recurrence and termination match the standard

- **WHEN** a `K`-bit stream is encoded by the constituent-encoder core
- **THEN** for each input bit it produces systematic `x=c` and parity
  `z = s1' ⊕ s1 ⊕ s3` with `s1' = c ⊕ s2 ⊕ s3`
- **AND** after the three termination steps it has emitted `K+3` `(x,z)` pairs
  and the register state is `(0,0,0)`

#### Scenario: Zero input produces zero output

- **WHEN** the constituent-encoder core processes an all-zero `K`-bit block
- **THEN** both the systematic and parity outputs are all-zero of length `K+3`

### Requirement: Turbo-encoder core reproduces the rate-1/3 layout bit-for-bit

The system SHALL provide a board-neutral VHDL turbo-encoder core that, given
the code block in natural order and in interleaved order, produces the
`3 × (K+4)` systematic/parity1/parity2 layout of TS36.212 §5.1.3.2 — including
the four trellis-termination columns — identical to the software
`turbo_encoder(c, pi)`.

#### Scenario: Systematic/parity body columns

- **WHEN** the core encodes a `K`-bit block
- **THEN** for `k = 0..K-1` the emitted column `k` equals
  `[x(k); z(k); z_prime(k)]`

#### Scenario: Trellis-termination columns

- **WHEN** the core finishes the body and emits the final four columns
- **THEN** they equal, in order, `[x(K+1);z(K+1);x(K+2)]`,
  `[z(K+2);x(K+3);z(K+3)]`, `[x'(K+1);z'(K+1);x'(K+2)]`,
  `[z'(K+2);x'(K+3);z'(K+3)]`

#### Scenario: Output size

- **WHEN** the core encodes a `K`-bit block
- **THEN** it emits exactly `K+4` column triples

### Requirement: K-agnostic streaming interface

The turbo-encoder core SHALL accept the code block as a bit stream with an
explicit framing handshake and SHALL NOT require the block length to be fixed
at synthesis time; the interleaved order is supplied externally (the core does
not generate the QPP/interleaver pattern).

#### Scenario: Framed streaming for varied block sizes

- **WHEN** blocks of different `K` are streamed in with the framing handshake
- **THEN** the core encodes each correctly without resynthesis or a
  compile-time `K` parameter

#### Scenario: Interleaved order is an input, not generated

- **WHEN** the core is driven
- **THEN** it consumes the natural-order and interleaved-order code-block bits
  as inputs and contains no QPP/interleaver address generator

### Requirement: Simulation is verified against the software golden model

The system SHALL provide a cocotb/GHDL simulation lane that drives the
turbo-encoder core with golden vectors generated from the existing
MATLAB/Octave `turbo_encoder` and `internal-interleaver` helpers and SHALL
compare every output column bit.

#### Scenario: Every output bit matches the golden vector

- **WHEN** the simulation runs a golden case `(c, c_prime)` with expected
  `d = turbo_encoder(c, pi)`
- **THEN** every bit of the core's `3 × (K+4)` output equals the expected `d`

#### Scenario: Representative block-size coverage

- **WHEN** the vector suite is generated
- **THEN** it spans a representative set of `K` values including the LTE
  minimum and maximum and at least one mid value, with multiple blocks per `K`

### Requirement: Reuse of the board-neutral HDL layout and harness

The system SHALL place the new cores under the board-neutral `hdl/rtl/` path
and its simulation under `hdl/sim/turbo_encoder/`, reuse the existing
cross-platform HDL test script, and keep generated artifacts out of version
control, without modifying existing cores or specs.

#### Scenario: Additive, board-neutral placement

- **WHEN** the change is delivered
- **THEN** the new synthesizable sources live under `hdl/rtl/`, the sim under
  `hdl/sim/turbo_encoder/`, and `hdl/rtl/crc8_parallel.vhdl` and the existing
  specs are unchanged

#### Scenario: Generated artifacts are ignored

- **WHEN** the simulation is run
- **THEN** simulator build products and waveforms are excluded from version
  control

### Requirement: On-board demonstration is optional and hardware-gated

Any DE2 demonstration of the turbo encoder SHALL reuse a simulator-verified
core via a board wrapper, use only switches/keys and LEDs/seven-segment
displays, and SHALL NOT be required for this change to be considered complete.

#### Scenario: Board smoke reuses the verified core

- **WHEN** an optional DE2 demonstration is added
- **THEN** it instantiates the simulator-verified turbo-encoder core unmodified
  and shows a status/signature of the encoded output on LEDs or seven-segment
  displays, with no screen/VGA dependency

#### Scenario: Completion does not depend on hardware

- **WHEN** the simulation lane passes for the representative vector suite
- **THEN** the change is complete regardless of whether the optional board
  demonstration has been run

### Requirement: Encoder `buf` infers M4K block RAM, bit-exact preserved

The `turbo_encode_top` input block buffer `buf` SHALL infer Cyclone II M4K block
RAM under Quartus II 13.0sp1 — synchronous registered reads, the array write
lifted out of the synchronous-reset FSM body, and the one-write/two-read access
served by two simple-dual-port M4K copies — while remaining bit-for-bit equal to
the `turbo_encode_top` and `tx_chain` golden output.

#### Scenario: One-write/two-read served by dual M4K copies

- **WHEN** the encoder reads the natural-order (`buf(didx)`) and interleaved-order
  (`buf(pi_idx)`) taps
- **THEN** `buf` is implemented as two simple-dual-port (1-write/1-read) copies
  written identically — one read by `didx`, one by `pi_idx` — so each is a clean
  M4K (a single 1-write/2-read array cannot map to one M4K)

#### Scenario: `buf` write is outside the reset-guarded FSM body

- **WHEN** `buf` is loaded during `S_LOAD`
- **THEN** the array write statements live at the top level of an unconditional
  clocked memory process (the synchronous reset touches only the load address /
  control registers, not the arrays), and the registered read taps plus the
  prefetch latency-absorb beat keep the encoder feed identical cycle-for-cycle

#### Scenario: Hardening preserves the golden output and its lanes

- **WHEN** the reworked core is run against the existing `turbo_encode_top` and
  `tx_chain_top` cocotb lanes
- **THEN** every streamed output bit matches `hdl/vectors/turbo_encoder.csv` and
  `hdl/vectors/tx_chain.csv`, and the committed golden vectors are byte-identical

### Requirement: Encoder block buffer is synthesis-hardened, bit-exact preserved

The `turbo_encode_top` core SHALL hold its code-block buffer as synchronous-read,
block-RAM-inferable (M4K) storage with two read taps (natural and interleaved
order) so the encode datapath is implementable on Cyclone II (`EP2C35F672C6`),
while remaining bit-for-bit equal to its software model.

#### Scenario: Block buffer infers dual-port synchronous-read RAM

- **WHEN** the encoder reads the natural-order tap `buf(didx)` and the
  interleaved-order tap `buf(pi_idx)`
- **THEN** both read addresses are registered (synchronous read) so the buffer
  infers a true-dual-port (or duplicated single-port) M4K block RAM rather than
  distributed/LUT RAM
- **AND** the resulting one-cycle read latency is realigned inside the encode
  FSM so `turbo_encoder` samples the same `(c, c')` bit pair on the same beat

#### Scenario: Hardening preserves the golden output and lane

- **WHEN** the hardened `turbo_encode_top` is run against its existing
  `hdl/sim/turbo_encode_top/` cocotb lane
- **THEN** every emitted column triple matches `hdl/vectors/turbo_encoder.csv`
  and the committed golden vectors are unchanged

