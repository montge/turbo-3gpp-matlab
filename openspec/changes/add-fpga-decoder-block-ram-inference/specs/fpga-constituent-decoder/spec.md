## ADDED Requirements

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
