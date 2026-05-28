## Context

`subblock_interleaver.m` (TS36.212 §5.1.4.1.1): for input length `D`, pick the
smallest `R` with `D ≤ 32R`; `K_Pi = 32R`; left-pad `N_D = K_Pi - D` `NaN`
filler; then permute. Indices 0 and 1 are identical (row-major reshape into
`R×32`, permute columns by the fixed 32-entry table `P`, read row-major). Index
2 uses `pi(k) = mod(P[⌊k/R⌋] + 32·(k mod R) + 1, K_Pi)`.

Deriving the read pattern into the padded sequence `y` (length `K_Pi`):
- **idx 0/1:** `pi_y(k) = (k mod R)·32 + P[⌊k/R⌋]`
- **idx 2:** `pi_y(k) = ( P[⌊k/R⌋] + 32·(k mod R) + 1 ) mod K_Pi`

and the original `d`-index is `pi_y - N_D` (filler if `pi_y < N_D`). This
matches `subblock_interleaver(0:D-1, idx)` element-for-element (filler = `NaN`).

## Goals / Non-Goals

**Goals:** a board-neutral synthesizable core streaming the `K_Pi` pattern
(`filler` flag + `d`-index) bit-exact vs the software model; golden-vector sim;
reuse the established layout/harness.

**Non-Goals:** no circular buffer / rv / LBRM / `E` selection (§5.1.4.1.2 — the
next follow-on), no decoder, no fixed-point, no board work, no screen.

## Decisions

1. **No divider — nested counters.** As `k` runs `0..K_Pi-1`, hold
   `r0 = k mod R` and `c0 = ⌊k/R⌋`: each step `r0++`; when `r0 = R` →
   `r0 = 0, c0++`. `R = ⌈D/32⌉ = (D+31) >> 5`; `K_Pi = R << 5`;
   `N_D = K_Pi − D`. All shifts/adds, no division.

2. **Fixed `P` ROM (32 entries) as a local constant.** Small; embedded in the
   core (not generated — it is a single 32-entry standard constant, unlike the
   188-row QPP table). `P[c0]` looked up combinationally.

3. **Index handling.** `idx ∈ {0,1}` share one datapath
   (`pi_y = (r0<<5) + P[c0]`); `idx = 2` adds `+1` then one conditional
   subtract of `K_Pi`. `idx = 2`'s `K_Pi` reduction is single-subtract because
   `P[c0] + 32·r0 + 1 ≤ K_Pi`.

3. **Streaming, K-agnostic interface.** `start` latches `D` and `idx`; the core
   derives `R/K_Pi/N_D`; then streams `K_Pi` outputs with `valid`, a `filler`
   flag, the `d`-index `idx_o` (valid only when `filler=0`), and `last`.

4. **Golden vectors from the existing helper.** Generator calls
   `subblock_interleaver(0:D-1, idx)`; emits per element either the `d`-index
   or a filler sentinel. CSV: `D,idx,pat` (space-separated, `-1` = filler).
   Indices 0 and 1 are identical, so the suite covers `idx ∈ {0,2}` (with a
   spot-check that `idx=1` equals `idx=0`).

## Risks / Trade-offs

- **Reshape/transpose order is easy to get wrong** → the pattern was derived
  algebraically from the MATLAB column-major `reshape`/transpose and is proven
  by exact full-pattern simulation against `subblock_interleaver`.
- **Filler representation** → no `NaN` in HDL; a per-element `filler` flag
  carries the same information; the generator maps `NaN → -1`.
- **`D` range** → encoder rows are `D = K+4` (≤ 6148 → `K_Pi ≤ 6176`,
  `R ≤ 193`); datapath widths sized accordingly and asserted at max `D`.

## Open Questions

- Representative `D` set — use the encoder-relevant `D ∈ {44, 516, 6148}`
  (from `K ∈ {40,512,6144}`) plus a couple of non-multiple-of-32 `D` to
  exercise filler; pin in tasks.
- CSV sentinel for filler (`-1`) vs a separate flag column — settle in the
  generator; the sim comparison is the oracle.
