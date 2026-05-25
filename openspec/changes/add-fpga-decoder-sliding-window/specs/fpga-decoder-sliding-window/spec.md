## ADDED Requirements

### Requirement: Loop-LLR-memory wall is the binding on-chip constraint, not α
The system SHALL document that windowing the constituent α RAM delivers no M4K
benefit in `turbo_decoder_top` and does not make K = 6144 fit, because α is not
the binding constraint; the binding constraint is the QPP-globally-permuted loop
LLR memories plus the K-deep input buffers, quantified per memory at K = 512 and
K = 6144.

#### Scenario: α windowing yields zero M4K benefit in the integrated decoder

- **WHEN** `turbo_decoder_top` is fit under Quartus II 13.0sp1 (EP2C35F672C6)
  with a short α window versus full-block α at the same K
- **THEN** the recorded M4K counts are identical (~61/105 at K = 512), confirming
  α is not the binding M4K constraint
- **AND** the design records that there is no `WINDOW_LEN`/`ACQ_LEN` generic in
  the HDL, so the identical result is genuine and not a non-propagation artifact

#### Scenario: loop-LLR-memory wall quantified

- **WHEN** the loop LLR memories (`ca_mem`, `ce_mem`, `chs_mem`, `za_mem`,
  `zpa_mem`, `xpa_body`, `xpe_body`) and the constituent input buffers
  (`xa_mem`, `za_mem`) are sized at K = 512 and K = 6144
- **THEN** the design records each memory's depth × width and M4K cost calibrated
  to the recorded `ca_mem = 4 M4K` data point
- **AND** the K = 6144 loop-memory total is ~264 M4K and the full-decoder total is
  several times the device's 105 M4K, so K = 6144 does not fit on-chip

#### Scenario: K = 6144 does not fit on-chip under any α scheme

- **WHEN** the full K = 6144 decoder is fit on the EP2C35
- **THEN** it does not fit (it needs far more than 105 M4K)
- **AND** windowing α (≈ 24 M4K freed at K = 512, ≈ 204 at K = 6144) leaves a
  residual still far over budget, so α windowing cannot make K = 6144 fit

### Requirement: On-chip maximum-K cap for the EP2C35 is pinned
The system SHALL pin the maximum block length K that fits entirely on-chip on the
EP2C35, given that the loop LLR memories and input buffers are K-deep and cannot
be windowed.

#### Scenario: on-chip maximum K is documented

- **WHEN** the maximum on-chip K is derived from the per-memory M4K model against
  the 105-M4K budget
- **THEN** the design pins K ≤ 1008 (next standard LTE K below the ~1024 knee)
  with full-block α, and K ≤ 1536 if windowed-α is later wired into the constituent
- **AND** the existing board demo at K = 512 is recorded as well inside this cap

### Requirement: Loop LLR memories cannot be windowed on-chip due to global QPP access
The system SHALL document that the loop LLR memories cannot be sliding-windowed or
streamed on-chip, because the QPP interleaver accesses them in a globally permuted
pattern over the entire K-bit block with no local window.

#### Scenario: QPP gather/scatter spans the whole block

- **WHEN** a lower half-iteration reads `x'_a[k] = c_e[π[k]]` and scatters
  `c_a[π[k]] = x'_e[k]` through the QPP interleaver π
- **THEN** consecutive bit indices k map to scattered, non-local addresses across
  all of `[0, K)`, so a window of source indices touches destination indices
  spread across the whole block
- **AND** the full `c_e`/`c_a` (and the other loop and input arrays) must be
  randomly addressable each half-iteration, so no on-chip checkpoint/streaming
  scheme reduces their live footprint the way it does for α

### Requirement: External SRAM is the specified route to full K = 6144
The system SHALL specify external memory as the only realistic route to a full
K = 6144 decode on the EP2C35, with the DE2's 512 KB asynchronous SRAM (not the
SDRAM) as the target, including the latency-versus-decode-budget verdict.

#### Scenario: SRAM holds the full working set within the latency budget

- **WHEN** the loop LLR arrays and constituent input buffers (~73 KB at K = 6144)
  are placed in the DE2 512 KB async SRAM
- **THEN** the working set fits (≈ 14 % of SRAM) and the ~10 ns async access
  serves the per-recurrence-step reads/writes within one core cycle at the demo
  clock (≈ 1× latency), even under the random QPP access pattern
- **AND** the design records this as feasible but a large increment (SRAM
  controller, board pinout, reworking every loop-mem/input access off-chip while
  preserving the bit-exact contract)

#### Scenario: SDRAM is rejected as random-latency-hostile

- **WHEN** the SDRAM option is assessed against the QPP random access pattern
- **THEN** the design records that SDRAM bandwidth is adequate but each random
  access pays a full row activate/CAS latency (~100–150 ns) that exceeds a core
  cycle and stalls the recurrence (~3–5× slower), plus a heavy refresh/row
  controller
- **AND** SRAM is selected as the external-memory target instead of SDRAM

### Requirement: Windowed-α reference is retained as a shelved validated artifact
The system SHALL retain the stage-1 windowed fixed-point reference and its
characterization as a documented, validated artifact, while shelving the windowed
α HDL because it delivers no board M4K benefit; the prior full-block golden
vectors and the existing decoder lanes remain unchanged.

#### Scenario: reference retained, HDL shelved

- **WHEN** the windowed Octave reference (`fixedpoint_constituent_decoder_sw.m`,
  `W = 64`, `L = 48`) and its characterization are reviewed for salvage
- **THEN** they are retained as correct and reusable for a constituent-standalone
  on-chip-K lift (≈ 1016 → ≈ 1536) and a future ASIC/larger-FPGA target
- **AND** the windowed α HDL is not implemented for this board, because it yields
  0 M4K in `turbo_decoder_top` and cannot make K = 6144 fit

#### Scenario: no code change and existing contract preserved

- **WHEN** this re-scoped change is applied
- **THEN** no `hdl/`, `scripts/`, `.qsf`, or `.m` files are edited and the
  existing golden vectors, decoder cocotb lanes, and recorded fits are unchanged
- **AND** any future windowed-α or external-SRAM work is tracked as its own change
