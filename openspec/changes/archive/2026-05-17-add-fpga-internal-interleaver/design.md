## Context

`internal_interleaver.m` implements the TS36.212 §5.1.3.2.3 QPP interleaver:
look up `(f1,f2)` for a supported `K` from the 188-entry Table 5.1.3-3, then
`pi(i) = mod(f1·i + f2·i², K)` for `i = 0..K-1`. The QPP bijection is Lean-
proven for every supported `K`. The HDL turbo encoder consumes the interleaved
order externally; this change supplies that order in hardware.

## Goals / Non-Goals

**Goals:**

- A board-neutral synthesizable VHDL core that streams `pi(0..K-1)` bit-exact
  vs `internal_interleaver`.
- Exhaustive simulation against golden vectors from the existing helper,
  including a bijectivity check.
- Reuse the established `hdl/` layout, harness, and golden-vector method.

**Non-Goals:**

- No in-hardware `(K,f1,f2)` ROM (188 entries) — separate follow-on; v1 takes
  the per-`K` constants externally.
- No decoder, rate matching, fixed-point, or board work. No screen.

## Decisions

1. **Incremental recurrence, not direct `f1·i + f2·i²`.** The direct form needs
   `f2·i²` up to ~3.6·10¹⁰ (wide multiplier). The second difference of `pi` is
   constant, giving an add-only recurrence with all state `< K` (~13 bits):
   `pi_0=0`, `d_0=(f1+f2) mod K`, `pi_{i+1}=(pi_i+d_i) mod K`,
   `d_{i+1}=(d_i+step) mod K` with `step=(2·f2) mod K`. Verified algebraically
   against `mod(f1·i+f2·i²,K)`.

2. **Pre-reduced constants supplied externally.** Inputs are `K`,
   `d0 = (f1+f2) mod K`, and `step = (2·f2) mod K` — all `< K`. Then each sum
   `pi_i+d_i` and `d_i+step` is `< 2K`, so reduction is a **single conditional
   subtract of K** (fully synthesizable, no divider, no multi-cycle mod).
   *Alternative considered:* an internal 188-entry `K→(f1,f2)` ROM + on-chip
   constant derivation. Deferred — it pulls the whole table into scope; the
   external-constants seam mirrors how interleave was externalized from the
   encoder and keeps this increment bounded and exactly verifiable.

3. **Streaming, K-agnostic interface.** `clk/rst`, a `start` pulse latching
   `K/d0/step`, then `valid` output streaming `pi(i)` for `i=0..K-1` with a
   `last` flag; no compile-time `K`. Index width sized for the LTE max
   (`K ≤ 6144` → 13-bit values).

4. **Golden vectors from the existing helper.** The generator calls
   `internal_interleaver(0:K-1)` and also emits the derived `(d0, step)` so the
   testbench just feeds constants and checks the streamed `pi`. CSV:
   `K,d0,step,pi` where `pi` is `K` space-free comma-free fixed-width fields…
   (schema pinned in tasks; must round-trip exactly).

5. **Bijectivity is asserted, not assumed.** The cocotb check verifies the
   streamed `pi` equals the golden `pi` *and* is a permutation of `0..K-1`
   (mirrors the Lean-proven property as a runtime guard).

6. **Representative `K` set.** `K` is validated by `internal_interleaver`
   (errors on unsupported sizes), so the set cannot drift from the standard.
   v1 uses `K ∈ {40, 512, 6144}` (LTE min/mid/max) plus a few extra table
   entries; widening toward all 188 is cheap and a one-line change.

## Risks / Trade-offs

- **Algebraic recurrence error would corrupt every index** → verified by
  derivation *and* by exact full-permutation + bijectivity simulation against
  the proven software model.
- **Core is not standalone without the constants table** → explicit, documented
  v1 seam; the `K→(f1,f2)` ROM is the defined next follow-on.
- **Index/accumulator width** → sized from the LTE maximum `K=6144`; asserted
  in sim across the max-`K` case.

## Open Questions

- Final `K` set / extra table entries for the suite — pin in tasks
  (`{40,512,6144}` baseline).
- CSV field layout for `pi` — settle in the generator; the sim comparison is
  the oracle that proves it round-trips.
