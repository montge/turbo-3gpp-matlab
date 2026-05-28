## Why

The decoder's **Fmax is ~14.25 MHz** (`turbo_decoder_de2` restricted Fmax),
capped by the constituent core's ~70 ns critical paths, which is why the DE2
demo runs on a ~12.5 MHz PLL workaround (the archived
`add-fpga-turbo-decoder-de2-demo` **Option A**). The original stub framed
**Option B** as a 50 MHz radix-2 / ACS look-ahead restructuring on the premise
that the in-loop **per-step max-normalization** dominates the cone.

**A direct synthesis probe (2026-05-27) disproved that premise.** Replacing the
8-way max-normalization with output-equivalent **anchor normalization** in both
the α (`S_FWD`) and β (`S_BWD`) recurrences moved Fmax by ~0 (14.25 → 14.2 MHz),
because a **second, independent ~70 ns path** co-limits: the `S_BWD` extrinsic
fold (`alpha_mem read → 16-term sequential maxstar δ-fold → xe_r`), which is
**feed-forward**, not a recurrence. So there is no cheap single lever, and 50 MHz
(shortening *both* paths ~3.5×, one of them a true feedback recurrence) is not a
safe bet.

This change is therefore **re-scoped to a measurement-gated bounded throughput
win**: attack the two co-limiting paths with techniques that are **output-bit-
exact in the board's Max-Log-MAP mode**, and fit at the **measured** achievable
clock (likely ~2× the current 12.5 MHz = ~2× decode throughput), with a stage-1
GO/NO-GO synthesis gate. See `design.md` for the probe data and technique
analysis.

## What Changes

- **Stage 1 (GO/NO-GO gate):** behind generics defaulting to current behavior,
  implement (a) a **balanced-tree extrinsic fold** (re-associating the serial
  `maxstar` fold — bit-exact in `EXACT_LOGMAP=false` since plain `max` is
  associative; gated off in exact mode) and (b) **cheaper recurrence
  normalization** (anchor / modulo, output-equivalent). **Synthesize and measure
  Fmax.** Proceed only on ≥ ~1.5× improvement; otherwise document the finding and
  shelve (the M2 precedent).
- **Stage 2:** prove output-bit-exactness — all existing decoder lanes green,
  `hdl/vectors/*` byte-identical. A new reference/vectors is required **only** if
  exact-mode re-association, an internally-checked normalization change, or a
  fold-pipeline latency change forces it (each contained and deterministic).
- **Stage 3:** integrate, full regression, and Quartus II 13.0sp1 fit of
  `turbo_decoder_de2` at the highest PLL the measured Fmax supports; record
  Fmax / LE / M4K vs baseline. The self-check + LCD demo is unchanged; only the
  PLL ratio moves. On-board re-confirm is hardware-gated (user's board).

The original 50 MHz radix-2 / ACS look-ahead on the true α/β **feedback**
recurrence is **explicitly deferred** — it doubles per-cycle ACS work for an
uncertain net gain and is a possible future arc only if more throughput is
wanted after this bounded win lands.

## Capabilities

### New Capabilities

- `fpga-decoder-recurrence-pipelining`: a bounded, measurement-gated decoder
  throughput optimization — balanced-tree extrinsic fold + cheaper recurrence
  normalization — that raises decoder Fmax (target ~2×, measured, not 50 MHz),
  **output-bit-exact** to the existing Max-Log-MAP golden vectors in the board's
  default mode, enabling a faster board PLL than the 12.5 MHz Option-A workaround.

## Impact

- Extends `fpga-constituent-decoder` (transitively `fpga-turbo-decode-loop`,
  `fpga-turbo-decoder-de2-demo`) with a faster, output-equivalent recurrence /
  fold; in the common case the bit-exact golden-vector contract is **unchanged**
  (byte-identical vectors), unlike the stub's assumed new reference.
- Depends on the two-tier discipline (cocotb bit-exact + outer characterization)
  and Quartus II 13.0sp1 timing on the Windows host.
- **Risk:** stage 1 may be NO-GO (the α/β feedback ACS itself may dominate); the
  gate exists precisely to catch that and shelve with a documented finding rather
  than sink effort — mirroring the M2 outcome.

## Out of Scope (explicit)

- The 50 MHz target and radix-2 / ACS look-ahead on the **feedback** recurrence
  (deferred future arc).
- Exact Log-MAP accuracy (M1 / `add-fpga-decoder-exact-log-map`, done).
- Sliding-window memory (M2 / shelved).
- A new board demo beyond re-fitting the existing decoder demo at a faster PLL.
