# fpga-constituent-decoder Specification

## Purpose
Defines the board-neutral fixed-point Max-Log-MAP constituent Log-BCJR HDL core
(the P1 keystone of the staged decoder roadmap): an Octave fixed-point reference
model that fixes the exact quantization, saturation, per-step max-normalization,
and operation order; the synthesizable VHDL core (γ branch metrics, α/β
recursions, extrinsic `x_e = max(δ|x=0) − max(δ|x=1)`) with a K-agnostic
streaming `(x_a,z_a)` → `x_e` interface; and the two-tier verification it
requires — an inner cocotb/GHDL golden-vector lane that is bit-exact to the
fixed-point reference, and an outer numerical-equivalence characterization of the
reference against the float `constituent_decoder.m`.
## Requirements
### Requirement: Fixed-point Max-Log-MAP reference model

The system SHALL provide an Octave fixed-point Max-Log-MAP reference for the
constituent Log-BCJR that defines the exact quantization, saturation,
per-step max-normalization, and operation order the HDL reproduces, and
SHALL be the inner bit-exact oracle for the HDL core.

#### Scenario: Reference is the bit-exact oracle

- **WHEN** golden vectors are generated
- **THEN** they are produced by the fixed-point reference (not the raw float
  model), and the HDL core is required to match them bit-for-bit

#### Scenario: Reference is numerically equivalent to the float model

- **WHEN** the characterization harness runs the fixed-point reference and the
  float `constituent_decoder.m` over the **same** encode→BPSK+AWGN→LLR frames
- **THEN** their extrinsic-LLR error statistics and hard-decision agreement on
  those identical inputs stay within the band documented in the change design
- **AND** this is an equivalence check, NOT a communications-BER check (a
  single non-iterative constituent decoder has poor BER by design; BER is a
  later turbo-loop oracle)

### Requirement: Board-neutral constituent Log-BCJR core (Max-Log-MAP)

The system SHALL provide a synthesizable, board-neutral VHDL core under
`hdl/rtl/` that computes the constituent Log-BCJR of TS36.212 §5.1.3.2 in
fixed-point Max-Log-MAP: branch metrics from the 16 trellis transitions,
α forward and β backward recursions with per-step max-normalization, and the
extrinsic `x_e = max(δ | x=0) − max(δ | x=1)`, for length `K+3` LLR
sequences, equal to the fixed-point reference.

#### Scenario: Extrinsic output matches the fixed-point reference

- **WHEN** the core is driven with quantized `(x_a, z_a)` of length `K+3`
- **THEN** every `x_e` output value equals the fixed-point reference output
  bit-for-bit

#### Scenario: Max-normalization does not change the extrinsic

- **WHEN** per-step max-normalization is applied to α and β
- **THEN** the extrinsic `x_e` is identical to the un-normalized computation
  (the normalization constant cancels in `max(δ|x=0) − max(δ|x=1)`)

#### Scenario: Zero a-priori information

- **WHEN** the core is driven with all-zero `(x_a, z_a)`
- **THEN** the output equals the fixed-point reference for that input
  (degenerate but well-defined)

### Requirement: K-agnostic streaming interface

The core SHALL accept `K` at run time via a start handshake, consume `K+3`
`(x_a, z_a)` LLR pairs, and stream `K+3` `x_e` values with valid/last; it
SHALL NOT require `K` fixed at synthesis time and SHALL NOT include the
iterative loop, interleaver, CRC, HARQ, or filler handling.

#### Scenario: Varied K without resynthesis

- **WHEN** different representative `K` are run via the handshake
- **THEN** each produces the correct `K+3` `x_e` with no compile-time `K`

#### Scenario: Scope boundary

- **WHEN** the core is delivered
- **THEN** it implements only the single constituent Log-BCJR (no iterative
  turbo loop, interleaver, CRC early-termination, HARQ, or filler/`NaN`)

### Requirement: Verification and additive placement

The change SHALL provide a cocotb/GHDL lane checking the HDL bit-exact vs the
fixed-point reference over a representative `K`/SNR set, keep the core under
`hdl/rtl/` and the lane under `hdl/sim/constituent_decoder/`, reuse the
cross-platform HDL flow, keep generated artifacts out of version control, and
modify no existing cores or specs.

#### Scenario: Inner gate is bit-exact and green

- **WHEN** the constituent-decoder lane runs
- **THEN** every HDL `x_e` equals the fixed-point reference golden vector

#### Scenario: No regression

- **WHEN** the change is delivered
- **THEN** all prior HDL lanes and the Octave suite still pass, and simulator
  build products are gitignored

### Requirement: Constituent metric memories infer M4K block RAM, bit-exact preserved

The constituent decoder's metric memories SHALL infer Cyclone II M4K block RAM
under Quartus II 13.0sp1 — `alpha_mem` (full-block α storage), `xa_mem`, and
`za_mem` (input LLR storage), with the array writes lifted out of the
synchronous-reset FSM body into an unconditional clocked memory process and the
reads registered (synchronous) — while remaining bit-for-bit equal to the
fixed-point Max-Log-MAP reference for every supported `K`.

#### Scenario: Metric-memory writes are outside the reset-guarded FSM body

- **WHEN** `alpha_mem` is initialized/written during `S_LOAD`/`S_FWD` and
  `xa_mem`/`za_mem` are loaded during `S_LOAD`
- **THEN** the array write statements live at the top level of an unconditional
  clocked memory process (the synchronous reset touches only the step / column /
  control registers, never the arrays), so each array infers an M4K write port
  rather than reset-gated LE registers

#### Scenario: Registered reads and absorbed latency keep the extrinsic identical

- **WHEN** the forward recursion reads the previous α column and the
  `(x_a, z_a)` codes, and the backward sweep re-reads α for the δ computation
- **THEN** those reads use registered (synchronous) addresses, the added
  one-cycle read latency is absorbed inside `S_FWD`/`S_BWD` (prefetch /
  forward-the-just-written-column), the per-step max-normalization still reads
  the whole prior column, and every emitted `x_e` value is identical to the
  pre-rework core

#### Scenario: Hardening preserves the golden output and its lane

- **WHEN** the reworked core is run against the existing
  `hdl/sim/constituent_decoder/` cocotb lane
- **THEN** every `x_e` value matches the committed fixed-point golden vectors,
  the vectors are byte-identical, and the inferred memories carry
  `ramstyle = "M4K"` with no asynchronous clear on the array bodies

