## Why

This is roadmap milestone **M2** (`hdl/docs/decoder_roadmap.md` §3 maturation
track): replace the constituent decoder's **full-block α RAM** with a
**sliding-window α** (windowed forward compute with periodic state
checkpoints), so the **full K = 6144 decoder fits on-chip**. Today only K ≤
~2700 fits: full-block α at K = 6144 is 8 states × (K+3) × ~15-bit ≈ **738 Kbit**,
which exceeds the EP2C35's **484 Kbit** of M4K. The locked v1 design
(`decoder_roadmap.md` §2) deliberately chose full-block α as a sim-first stance
and named sliding-window as the synthesis-hardening follow-on. This change
formalizes that follow-on.

This is a **big** change and it **alters the bit-exact contract**: a windowed
BCJR with checkpoints produces different α traversal order and warm-up than the
full-block reference, so it needs its **own fixed-point reference model** and a
fresh **characterization** against the float `constituent_decoder.m` /
`turbo_decoder.m`. It is therefore not a drop-in to the existing
`fpga-constituent-decoder` golden vectors.

## What Changes

- **Add** a sliding-window α scheme to the constituent decoder
  (`fpga-constituent-decoder`): forward pass computed over windows of length
  `W` with state checkpoints saved at window boundaries, replacing the
  `8 × (K+3)` full-block α store with a `8 × W` (+ checkpoint) footprint.
- **Author** a new sliding-window fixed-point **reference model** (Octave) and
  golden vectors; the existing full-block golden vectors do NOT carry over.
- **Verify** two-tier per the roadmap: inner cocotb bit-exact vs the new
  sliding-window reference; outer characterization (equivalence at the
  constituent level, bounded BER at the loop level) vs float, confirming the
  windowing introduces no accuracy regression beyond a documented band.
- **Demonstrate** the headroom goal: the full **K = 6144** constituent /
  `turbo_decoder_top` path **fits the EP2C35** under Quartus II 13.0sp1 (the
  memory that previously did not fit).

All work is **proposal-only in this change** — no `hdl/`, `scripts/`, `.qsf`,
or `.m` edits land here. Full window-size / checkpoint-stride design is deferred
to when this change is started.

## Capabilities

### New Capabilities

- `fpga-decoder-sliding-window`: a windowed-α (sliding-window BCJR with
  checkpoints) memory architecture for the constituent decoder that bounds α
  storage to `8 × W` so the full K = 6144 turbo decoder fits the EP2C35, with a
  new sliding-window fixed-point reference establishing a new bit-exact
  contract.

## Impact

- Extends `fpga-constituent-decoder` (and transitively `fpga-turbo-decode-loop`)
  with a new memory architecture; changes the bit-exact golden-vector contract.
- Depends on the existing two-tier verification discipline (cocotb bit-exact +
  Quartus fit) and Quartus II 13.0sp1 on the Windows host.
- Risk: the bit-exact-contract change means a fresh reference + characterization
  is the safety-critical artifact (per roadmap §1); window size and checkpoint
  stride trade RAM against recompute cycles and are open design questions.

## Out of Scope (explicit)

- Exact Log-MAP accuracy (that is M1 / `add-fpga-decoder-exact-log-map`).
- Recurrence pipelining for Fmax (that is `add-fpga-decoder-recurrence-pipelining`).
- Any board demo of the K = 6144 fit beyond the Quartus fit gate.
