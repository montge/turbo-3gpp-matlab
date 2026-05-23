# fpga-turbo-decode-loop Specification

## Purpose
Defines the board-neutral fixed-point iterative turbo-decode loop (the P2
increment of the staged decoder roadmap): an Octave fixed-point full-loop
reference that wraps the P1 constituent reference in the exact `turbo_decoder.m`
loop algebra (LLR de-mux, `c_a=0` init, the half-iteration
`upper → interleave → lower → de-interleave` schedule, hard decision
`(c_a+c_e)<0`) and pins the extrinsic-exchange Q-format; the synthesizable VHDL
`turbo_decoder_top` core that reproduces it bit-exactly by reusing the P1
`constituent_decoder`, `qpp_rom`, and `qpp_interleaver` unmodified; and its
two-tier verification — an inner cocotb/GHDL golden-vector lane bit-exact to the
fixed-point reference and an outer bounded BER-vs-SNR check against float
`turbo_decoder.m`.

## Requirements
### Requirement: Fixed-point full-loop turbo-decoder reference model

The system SHALL provide an Octave fixed-point full-loop turbo-decoder
reference that wraps the P1 fixed-point constituent reference in the exact
`turbo_decoder.m` loop algebra (de-mux of the `3×(K+4)` LLR matrix into upper
`(x_a, z_a)` / lower `(x'_a, z'_a)` and `ch_sys`, `c_a = 0` init, the
half-iteration `upper → interleave → lower → de-interleave` schedule, and the
hard decision `(c_a + c_e) < 0`), defining the extrinsic-exchange quantization
and operation order the HDL reproduces, and SHALL be the inner bit-exact oracle
for the HDL loop core.

#### Scenario: Reference is the bit-exact oracle

- **WHEN** golden vectors are generated
- **THEN** they are produced by the fixed-point full-loop reference (not the
  raw float `turbo_decoder.m`), and the HDL loop core is required to match the
  decoded hard bits bit-for-bit

#### Scenario: Reference reuses the P1 constituent reference and core widths

- **WHEN** the full-loop reference invokes the constituent decoder for an
  upper or lower half-iteration
- **THEN** it calls the P1 fixed-point constituent reference with its pinned
  α/β/γ/δ widths and ±inf sentinel unchanged, and only the surrounding
  extrinsic-exchange format is newly pinned in this change

#### Scenario: Outer check is bounded communications BER vs the float model

- **WHEN** the characterization harness runs the fixed-point full-loop
  reference and float `turbo_decoder.m` over the **same** bounded
  encode→BPSK+AWGN→LLR grid (few SNR points, modest frame counts, shallow
  target BER)
- **THEN** the fixed-point reference's BER-vs-SNR tracks the float decoder
  within the dB margin documented in the change design
- **AND** this is a communications-BER check (the loop iterates, so BER is now
  meaningful), shifted from the P1 numerical-equivalence check

### Requirement: Board-neutral iterative turbo-decode loop core

The system SHALL provide a synthesizable, board-neutral VHDL core
(`turbo_decoder_top`) under `hdl/rtl/` that implements the TS36.212 §5.1.3.2
iterative turbo-decode loop in fixed-point: de-mux of the `3×(K+4)` LLR input,
a fixed number of half-iterations (`H = round(2·max_iterations)`, even = upper
decoder, odd = lower decoder) exchanging extrinsic information, and the final
hard decision `c[k] = (c_a[k] + c_e[k]) < 0` over the `K` systematic bits,
equal to the fixed-point full-loop reference.

#### Scenario: Decoded bits match the fixed-point reference

- **WHEN** the core is driven with quantized `d_a` (`3×(K+4)`), `K`, and
  `max_iterations`
- **THEN** every one of the `K` decoded hard-decision bits equals the
  fixed-point full-loop reference output bit-for-bit

#### Scenario: Half-iteration schedule and final half handling

- **WHEN** `2·max_iterations` is odd (the final lower half is skipped)
- **THEN** the core stops after `H` half-iterations and produces the hard
  decision exactly as the reference's half-iteration framing dictates, with no
  float `ceil`/`floor` logic

#### Scenario: Persistent versus cyclic data

- **WHEN** the loop iterates
- **THEN** `z_a`, `z'_a`, the termination triplets, and `ch_sys` remain
  constant across all half-iterations while only the systematic a-priori body
  (`c_a`, `c_e`) changes, matching the reference

### Requirement: Reuse of verified sub-cores unmodified

The loop core SHALL instantiate the P1 `constituent_decoder` core, the
`qpp_rom`, and the `qpp_interleaver` **without modification**, using a single
constituent instance invoked sequentially (upper then lower) per full
iteration and regenerating the QPP interleaver pattern `pi` from
`qpp_interleaver` for each interleave read and deinterleave scatter.

#### Scenario: Constituent core reused unmodified, output truncated to K

- **WHEN** the loop invokes the constituent core for a half-iteration
- **THEN** it drives the muxed `(x_a, z_a)` / `(x'_a, z'_a)` of length `K+3`,
  consumes `x_e[0..K-1]`, and discards the 3 termination extrinsics — with no
  change to the constituent core's interface

#### Scenario: Interleave and deinterleave via the reused QPP cores

- **WHEN** a lower half-iteration runs
- **THEN** the interleave read `x'_a = c_e[pi[k]]` and the deinterleave scatter
  `c_a[pi[k]] = x'_e[k]` use the `pi[k]` stream from the unmodified
  `qpp_interleaver` (addressed via `qpp_rom`), the same interleaver-address →
  buffer pattern as `rate_matching_top`

### Requirement: K-agnostic streaming interface and scope boundary

The core SHALL accept `K` and `max_iterations` at run time via a start
handshake, consume the `3×(K+4)` LLR input, and stream the `K` decoded bits
with valid/last; it SHALL NOT require `K` fixed at synthesis time and SHALL NOT
include CRC-aided early termination, HARQ accumulation, filler/`NaN` handling,
an exact Log-MAP correction LUT, inter-half extrinsic scaling, or
sliding-window memory.

#### Scenario: Varied K and iteration count without resynthesis

- **WHEN** different representative `K` and `max_iterations` are run via the
  handshake
- **THEN** each produces the correct `K` decoded bits with no compile-time `K`
  or fixed iteration count

#### Scenario: Scope boundary (P2 only; P3 deferrals)

- **WHEN** the core is delivered
- **THEN** it implements only the fixed-iteration loop wrapping the constituent
  core (no CRC early-termination, HARQ, filler/`NaN`, exact Log-MAP LUT,
  extrinsic scaling, sliding-window/BRAM, or board demo)

### Requirement: Verification and additive placement

The change SHALL provide a cocotb/GHDL lane checking the HDL loop core
bit-exact vs the fixed-point full-loop reference over a representative
`K`/SNR/iteration set (keeping large-`K` cases few per the `~4·H·K` cycle
budget), keep the core under `hdl/rtl/` and the lane under
`hdl/sim/turbo_decoder_top/`, reuse the cross-platform HDL flow, keep generated
artifacts out of version control, and modify no existing cores or specs.

#### Scenario: Inner gate is bit-exact and green

- **WHEN** the turbo-decoder-loop lane runs
- **THEN** every HDL decoded bit equals the fixed-point full-loop reference
  golden vector

#### Scenario: No regression and unmodified reuse

- **WHEN** the change is delivered
- **THEN** all prior HDL lanes and the Octave suite still pass, the reused
  `constituent_decoder`, `qpp_rom`, and `qpp_interleaver` cores are unchanged,
  and simulator build products are gitignored

