## ADDED Requirements

### Requirement: Fixed-point reference with termination, filler, and HARQ

The system SHALL extend the P2 fixed-point full-loop turbo-decoder reference to
model the deferred `turbo_decoder.m` / `turbo_decoding_chain.m` behaviours —
CRC-aided early termination (returning `iterations_performed`), filler-bit
handling (`NaN → +inf → MAX_SENT` reusing the P1 ±inf sentinel), and HARQ soft
accumulation of the channel-LLR matrix across retransmissions — and SHALL be the
inner bit-exact oracle for the HDL, with no new fixed-point format for the decode
datapath (only a HARQ accumulator width is newly pinned).

#### Scenario: Reference is the bit-exact oracle for bits and iteration count

- **WHEN** golden vectors are generated
- **THEN** they are produced by the extended fixed-point reference (not the raw
  float model), and the HDL is required to match the decoded hard bits AND the
  `iterations_performed` value bit-for-bit

#### Scenario: Filler reuses the P1 ±inf sentinel unchanged

- **WHEN** the reference de-muxes a code block with filler bits (`F_r > 0`)
- **THEN** it maps the filler-marked positions to the `+inf` token equal to the
  P1-pinned `MAX_SENT = +16383` at the core input format, decodes them as
  known bits, and forces them to the model's `NaN`/known value on output —
  introducing no new sentinel or fixed-point format

#### Scenario: Outer check extended to early-stop and CRC-pass rate

- **WHEN** the bounded characterization harness runs the fixed-point reference
  and float `turbo_decoder.m` / `turbo_decoding_chain.m` over the **same**
  bounded encode→BPSK+AWGN→LLR grid
- **THEN** the fixed-point reference's BER-vs-SNR tracks the float decoder within
  the documented dB margin, AND the early-stop `iterations_performed`
  distribution and CRC-pass rate track the float model, AND a HARQ
  retransmission improves BER as the float predicts

### Requirement: CRC-aided early termination, deterministic and bit-exact

The system SHALL add CRC-aided early termination to the iterative loop: after a
pre-loop hard decision and after each half-iteration the decoder SHALL compute
the code-block CRC on the current hard decision and stop as soon as it checks,
otherwise running to `max_iterations`, returning `iterations_performed`. The
early-stop schedule SHALL be deterministic (a pure function of the quantized
inputs) so the inner bit-exact lane is preserved.

#### Scenario: Stops early with the correct iteration count

- **WHEN** the decoder is driven with a CRC generator and a block that converges
  before `max_iterations`
- **THEN** it stops at the first check point whose CRC passes and outputs
  `iterations_performed` equal to the float model's value (`0` pre-loop,
  `iteration_index − 0.5` after an upper half, `iteration_index` after a lower
  half)

#### Scenario: Runs to max_iterations when the CRC never passes

- **WHEN** no check point's CRC passes
- **THEN** the decoder runs all `H` half-iterations and returns
  `iterations_performed = max_iterations`, exactly as the P2 fixed-iteration
  loop would

#### Scenario: Early termination is deterministic

- **WHEN** the same quantized `d_a`, `K`, `max_iterations`, and CRC polynomial
  are decoded by the reference and the HDL
- **THEN** both check the CRC at identical check points in identical order and
  produce identical `iterations_performed` and identical decoded bits — the
  inner gate remains a strict bit-exact check

#### Scenario: No-CRC path is byte-for-byte P2

- **WHEN** no CRC generator is supplied (early termination disabled)
- **THEN** the decoder behaves exactly like the P2 fixed-iteration loop (the
  pre-loop and per-half CRC steps are bypassed)

### Requirement: CRC24 check core (CRC24A and CRC24B)

The system SHALL provide a synthesizable, board-neutral VHDL CRC24 check core
under `hdl/rtl/` that computes the LTE code-block / transport-block CRC over a
variable-length hard-decision bit sequence using the generator-matrix algebra of
`calculate_crc_bits` (rows from `get_crc_generator_matrix`), supporting both the
transport-block polynomial (CRC24A, used when `C == 1`) and the code-block
polynomial (CRC24B, used when `C > 1`), and asserting a single `crc_ok` when the
remainder is zero.

#### Scenario: CRC matches the float calculate_crc_bits

- **WHEN** the core is driven with a `K`-bit hard-decision sequence and a
  selected CRC polynomial
- **THEN** its `crc_ok` equals `sum(calculate_crc_bits(c, G_max)) == 0` for the
  matching generator matrix, bit-for-bit, with the generator rows tail-indexed
  for length `K` exactly as the float slices `G_max`

#### Scenario: Polynomial selection follows the chain convention

- **WHEN** the CRC select chooses CRC24A versus CRC24B
- **THEN** the core uses the transport-block generator matrix (CRC24A) or the
  code-block generator matrix (CRC24B) respectively, matching
  `turbo_decoding_chain.m`'s use of `CRC_generator_matrix_TB` (`C == 1`) versus
  `CRC_generator_matrix_CB` (`C > 1`)

### Requirement: Filler-bit handling reusing the ±inf sentinel

The HDL SHALL map filler-bit positions (the first `F_r` systematic LLRs,
signalled upstream as `NaN`) to the `+inf` fixed-point token equal to the
P1-pinned `MAX_SENT` saturating sentinel at LLR load, decode them as known bits,
and present them as the model's known/`NaN`-equivalent value on output, computing
the early-termination CRC on the hard decision before that overwrite — reusing
the P1 sentinel without introducing a new value or format.

#### Scenario: Filler decodes as a known bit

- **WHEN** a code block with `F_r > 0` is decoded
- **THEN** each filler position is loaded as `MAX_SENT` (`+inf` ⇒ hard `0`),
  never spuriously losing a `max` in the constituent core, and the decoded
  output matches the fixed-point reference for those positions

#### Scenario: CRC sees the pre-overwrite hard decision

- **WHEN** the early-termination CRC is computed for a block with filler
- **THEN** it is computed on the hard decision before the filler positions are
  forced to the model's `NaN`/known output value, matching the float ordering

### Requirement: HARQ soft accumulation

The system SHALL add an optional HARQ soft-combining stage that accumulates the
incoming `3×(K+4)` channel-LLR matrix into a per-code-block soft buffer
(`buffer ← buffer + d`) before decoding and supports a reset/clear between
information blocks, mirroring `turbo_decoding_chain.m`'s `obj.buffers` behaviour,
using a saturating accumulator sized for a pinned maximum number of
retransmissions.

#### Scenario: Accumulated LLRs match the float buffer

- **WHEN** HARQ is enabled and a sequence of retransmissions of the same block is
  applied
- **THEN** the soft buffer equals the float `obj.buffers{r+1}` accumulation
  (saturating) at each step, and the decode of the accumulated buffer matches the
  fixed-point reference

#### Scenario: Reset clears the buffer between blocks

- **WHEN** the reset/clear control is asserted
- **THEN** the soft buffer is zeroed and a subsequent transmission is decoded as a
  fresh block, matching the float `reset` semantics

#### Scenario: Filler is idempotent under accumulation

- **WHEN** a filler position (`MAX_SENT`) is accumulated across retransmissions
- **THEN** it stays saturated at the sentinel (a known bit stays known), matching
  the reference

### Requirement: Verification, scope boundary, and additive placement

The change SHALL provide a cocotb/GHDL lane checking the HDL bit-exact (decoded
bits AND `iterations_performed`) vs the extended fixed-point reference over a
suite that exercises early termination (varying `iterations_performed`), filler,
and a HARQ retransmission case; keep the new cores under `hdl/rtl/` and the lane
under `hdl/sim/turbo_decoder_termination/`; reuse the P2 loop, P1 constituent
core, and `qpp` cores unmodified; keep generated artifacts out of version
control; and implement only the P3 behaviours (CRC early termination, HARQ,
filler), excluding the deferred maturation work (exact Log-MAP LUT + extrinsic
scaling, sliding-window/BRAM, width tightening, RX integration, board demo).

#### Scenario: Inner gate is bit-exact and green

- **WHEN** the termination lane runs
- **THEN** every HDL decoded bit and every `iterations_performed` value equals
  the extended fixed-point reference golden vector, including the early-stop,
  filler, and HARQ cases

#### Scenario: No regression and unmodified reuse

- **WHEN** the change is delivered
- **THEN** all prior HDL lanes (including the P2 `turbo_decoder_top`, P1
  `constituent_decoder`, `qpp_rom`, `qpp_interleaver`, and `crc8_parallel`) and
  the Octave suite still pass, the reused cores are unchanged, and simulator
  build products are gitignored

#### Scenario: Scope boundary (P3 only; maturation deferred)

- **WHEN** the change is delivered
- **THEN** it implements only CRC-aided early termination, HARQ accumulation, and
  filler handling layered on the P2 loop (no exact Log-MAP correction LUT,
  inter-half extrinsic scaling, sliding-window/BRAM, fixed-point width
  tightening, RX-chain integration, or board demo)
