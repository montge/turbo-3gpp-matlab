## ADDED Requirements

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
