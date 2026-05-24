## ADDED Requirements

### Requirement: Loop LLR/extrinsic memories infer M4K block RAM, bit-exact preserved

The `turbo_decoder_top` loop memories SHALL infer Cyclone II M4K block RAM under
Quartus II 13.0sp1 — `za_mem`, `zpa_mem`, `chs_mem`, `ca_mem`, `ce_mem`,
`xpa_body`, and `xpe_body`, with the array writes lifted out of the
synchronous-reset FSM body into an unconditional clocked memory process and the
reads registered (synchronous) — while remaining bit-for-bit equal to the
fixed-point full-loop reference for every supported `K` and iteration count.

#### Scenario: Loop-memory writes are outside the reset-guarded FSM body

- **WHEN** the loop memories are written (load of `za_mem`/`zpa_mem`/`chs_mem`,
  the `ce_mem`/`xpa_body`/`xpe_body` accumulate/capture, the `ca_mem` init and
  scatter)
- **THEN** the array write statements live at the top level of an unconditional
  clocked memory process (the synchronous reset touches only the index / phase /
  control registers, never the arrays), so each array infers an M4K write port
  rather than reset-gated LE registers, and each carries `ramstyle = "M4K"`

#### Scenario: Registered reads keep the decoded bits identical

- **WHEN** the loop reads `za_mem`/`zpa_mem` during core feed, `chs_mem` during
  accumulate/capture/decision, `ce_mem` during the interleave, and
  `xpa_body`/`xpe_body` during feed/scatter
- **THEN** those reads use registered (synchronous) addresses, the added
  one-cycle read latency is absorbed inside the owning FSM phase, and every one
  of the `K` decoded hard-decision bits is identical to the pre-rework core

### Requirement: `ca_mem` deinterleave scatter infers a simple-dual-port M4K

The loop core's `ca_mem` SHALL infer a simple-dual-port M4K block RAM — one
write port at the data-dependent QPP-deinterleave scatter index
(`ca_mem(pi_idx) <= xpe_body(pi_k)`), one registered sequential read port for
the accumulate (`ca_mem(feed_idx)`) and final-decision (`ca_mem(out_idx)`)
reads — with the scatter (write) and read phases disjoint and a
read-during-write mode that matches the fixed-point reference, remaining
bit-for-bit equal to the reference for every supported parameter set.

#### Scenario: Scatter write and sequential read on disjoint SDP ports

- **WHEN** the lower half-iteration scatters `ca_mem(pi_idx)` and the next upper
  half / final decision reads `ca_mem` sequentially
- **THEN** the scatter uses the SDP write port at the data-dependent `pi_idx`,
  the reads use the registered read port, the phases stay disjoint (no
  same-address same-cycle read-during-write on the bit-exact path), and the
  array init clear is re-sequenced to a single-write-port-compatible schedule

#### Scenario: Read-during-write semantics match the reference

- **WHEN** the inferred `ca_mem` SDP is compiled under Quartus II 13.0sp1 and
  exercised by the `hdl/sim/turbo_decoder_top/` cocotb lane
- **THEN** its `READ_DURING_WRITE_MODE` produces decoded bits bit-identical to
  the GHDL behavioural model and the committed golden vectors are byte-identical
