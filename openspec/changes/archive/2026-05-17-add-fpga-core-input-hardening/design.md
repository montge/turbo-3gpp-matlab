## Context

CodeRabbit (PR #19) flagged 6 actionable items. Triage: all are
out-of-contract input-robustness or interface/doc cleanliness; none is
reachable in the verified golden-vector lanes (the project deliberately drives
controlled, bounded inputs — sim-first). The cores are archived and verified
bit-exact for their specified contract. The risk to manage here is *not*
breaking that verified behaviour while adding defensive handling.

## Goals / Non-Goals

**Goals:** add input-validity guards + the interface/generator/doc fixes;
preserve every verified lane bit-exact (regression is the gate).

**Non-Goals:** no algorithm, format, or feature change; no synthesis; no
golden-vector or spec-behaviour change.

## Decisions

1. **Guards are strictly additive and out-of-contract.** Each guard triggers
   only for inputs the verified vectors never exercise (`K_Pi/E/d_len/d_in=0`,
   over-range, unsupported-`K`). For all valid inputs the datapath is
   byte-for-byte unchanged ⇒ existing CSV lanes must stay green with **no
   vector edits**. That equality is the acceptance criterion.

2. **Behaviour on invalid input = clean, observable, safe.** Prefer a defined
   idle/abort (e.g., assert an `error`/`invalid` style status or simply do
   not start) over partial/garbage runs. No divide/mod-by-zero, no
   out-of-range buffer indexing. Exact per-core signal chosen in
   implementation; the contract is "no UB, no silent garbage."

3. **`turbo_encode_top` honours `rom_sup`.** On `S_LOOKUP` with
   `rom_sup='0'`, do not latch `(d0,step)`/proceed; surface an
   unsupported-`K` indication. Supported `K` path is identical to today.

4. **`qpp_rom.done`.** Make it a one-cycle pulse on scan completion (clear on
   the cycle after assert) — and confirm every consumer (`turbo_encode_top`,
   the unit lane) still works (they latch on the edge, so a pulse is
   compatible). If any consumer relied on the level, document and keep level
   with a renamed/commented semantic instead. Decided during implementation
   against the actual consumers; lanes must stay green either way.

5. **Generator + docs.** `generate_hdl_qpp_rom.m`: add the
   `if ~exist(dir) mkdir` guard (verbatim pattern from the sibling
   generators). Docs: add `bash`/`text` language to the flagged fences only —
   no content change.

## Risks / Trade-offs

- **Regression on valid inputs** → the entire point of Decision 1; every
  affected lane is re-run and must remain bit-exact with unchanged vectors.
- **`qpp_rom.done` change ripples into `turbo_encode_top`** → both the
  `qpp_rom` unit lane and the `turbo_encode_top`/`tx_chain_top` lanes are
  re-run; if a pulse breaks a consumer, fall back to documented-level (still
  green) rather than force the pulse.
- **Scope creep into "real" hardening** (sliding-window, divider-free) → out
  of scope; those remain the separate documented synthesis follow-ons. This
  change is *only* the CodeRabbit items.

## Open Questions

- Per-core invalid-input signalling (status bit vs no-start vs assert) —
  settle in implementation; the only firm contract is "no UB / no silent
  garbage / valid-input behaviour unchanged."
