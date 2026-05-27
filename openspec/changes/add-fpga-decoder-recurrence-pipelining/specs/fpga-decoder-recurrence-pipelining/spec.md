## ADDED Requirements

### Requirement: Bounded, measurement-gated decoder throughput optimization

The system SHALL raise the decoder's achievable Fmax via a balanced-tree
extrinsic fold and cheaper recurrence normalization, gated by a stage-1 synthesis
measurement: the optimization proceeds only if the measured Fmax improves by at
least ~1.5× over the ~14.25 MHz baseline; otherwise the finding is documented and
the change is shelved. The target is the measured achievable clock (≈ 2×, not a
pre-committed 50 MHz).

#### Scenario: Stage-1 Fmax gate decides GO/NO-GO

- **WHEN** the balanced-tree fold + cheaper normalization (behind generics
  defaulting to current behavior) are synthesized into `turbo_decoder_top` under
  Quartus II 13.0sp1 and restricted Fmax is measured
- **THEN** the change proceeds only if Fmax improves ≥ ~1.5× over the ~14.25 MHz
  baseline; if not, the result is recorded in `decoder_roadmap.md` and the change
  is shelved (the M2 precedent)

#### Scenario: Faster board PLL after a GO

- **WHEN** the optimization clears the gate and `turbo_decoder_de2` is re-fit
- **THEN** it closes timing at the highest PLL the measured Fmax supports
  (e.g. ~25 MHz), faster than the 12.5 MHz Option-A workaround, and the recorded
  Fmax / LE / M4K are reported vs the baseline

### Requirement: Output-bit-exact in the board's Max-Log-MAP mode

The system SHALL keep the optimization output-bit-exact to the existing
Max-Log-MAP golden vectors in the board's default mode (`EXACT_LOGMAP=false`):
the balanced-tree fold relies on `max` associativity (exact for plain max), and
the cheaper normalization subtracts a common per-step offset that cancels in the
extrinsic difference. A new reference/vectors is required ONLY if exact-mode
re-association, an internally-checked normalization change, or a fold-pipeline
latency change forces it.

#### Scenario: Existing decoder lanes stay green, vectors byte-identical

- **WHEN** the optimized HDL (default Max-Log-MAP mode) is run through the
  `constituent_decoder`, `turbo_decoder_top`, and `turbo_decoder_term_top` cocotb
  lanes
- **THEN** all lanes pass and `hdl/vectors/*` remain byte-identical (no new
  reference in the common case)

#### Scenario: Exact-mode schedule is preserved

- **WHEN** `EXACT_LOGMAP=true` (the non-associative maxstar accuracy mode)
- **THEN** the balanced-tree fold is gated off so the pinned seed-from-first
  serial fold order (the M1 bit-exact contract) is preserved unchanged

#### Scenario: Decoded output / BER unchanged

- **WHEN** the optimization is characterized against the float model (or a new
  reference, if §3 of design.md forces one)
- **THEN** the decoded output / BER is unchanged within the documented band,
  confirming a throughput-only optimization
