## Why

This is roadmap milestone **M2** (`hdl/docs/decoder_roadmap.md` §3 maturation
track): replace the constituent decoder's **full-block α RAM** with a
**sliding-window** BCJR so the **full K = 6144 decoder fits on-chip** and the
M4K footprint drops sharply at every K.

Today `constituent_decoder.vhdl` computes **all** α columns and stores them in an
`alpha_mem` sized `STATES(8) × (K+3) × W_AB(15)` (one packed 120-bit M4K word per
column, depth `N_MAX = K+3`), then sweeps β backward re-reading those columns.
This α store is the dominant memory and the wall:

- At **K = 6144** it is `8 × 6147 × 15 ≈ 738 Kbit` > the EP2C35's **484 Kbit** of
  M4K → **the full-K decoder does not fit at all** (the archived
  `add-fpga-decoder-block-ram-inference` design.md §Risks already names α at
  full K as ~165 Kbit *for the column words alone* and pins the board demo to
  K = 512 precisely because of this).
- At **K = 512** (`N_MAX = 515`) the `515 × 120` α store is **30 of the
  constituent's 35 M4K** (block-RAM-inference design.md §4 / `constituent_decoder.vhdl`
  fit note lines 100-107). It is the single largest memory in the whole decoder
  and is why `rx_chain_top` sits at **96/105 M4K** at K = 512 with almost no
  headroom.

**Sliding-window BCJR** processes the trellis in windows of length `W`. The β
recursion for each window is started from a **flat (equiprobable) acquisition**
column `L` steps *beyond* the window edge and recursed over those `L` warm-up
steps so it converges before the window is emitted. Only one window's worth of
β (and, with α checkpointing, ≈ one window of α) need be live at once, so α
storage shrinks from `8 × (K+3)` to `≈ 8 × W` + a few boundary checkpoints. The
big α-RAM disappears and full K = 6144 fits.

## What Changes

- **Add** a sliding-window α/β schedule to the constituent decoder
  (`fpga-constituent-decoder`): forward α is computed in windows from periodic
  state checkpoints, and β is computed per window with an `L`-step acquisition
  warm-up, replacing the `8 × (K+3)` full-block α store with a `≈ 8 × W` (+
  checkpoint) footprint. Ideally gated behind a `WINDOW_LEN` generic so
  `WINDOW_LEN ≥ K+3` collapses to the existing full-block behaviour (the
  windowed core is then a strict superset).
- **Author** a **new** sliding-window fixed-point **reference model**
  (`scripts/fixedpoint_constituent_decoder_sw.m`, or a windowed mode/param of
  the existing reference) and **new golden vectors**. The existing full-block
  golden vectors do **not** carry over (see the approximation note below).
- **Verify** two-tier per the roadmap, plus a third loss-band check:
  - **inner** cocotb bit-exact vs the **new** windowed reference;
  - **outer-A** windowed-vs-full-block **equivalence/loss** (the *windowing*
    loss, distinct from quantization loss): extrinsic-LLR error at the
    constituent level and bounded end-to-end **BER** at the loop level, within a
    documented band (target ≲ 0.1–0.2 dB at the loop level for an adequate `L`);
  - **outer-B** the existing float-vs-fixed-point characterization continues to
    hold (windowing must not erode the P1/P2 margins).
- **Demonstrate** the headroom goal: the full **K = 6144** constituent /
  `turbo_decoder_top` / `rx_chain_top` path **fits the EP2C35** under Quartus II
  13.0sp1 (the memory that previously did not fit), and the K = 512 M4K count
  drops well below today's 96/105 for `rx_chain_top`.

All work is **proposal/design-only in this change** — no `hdl/`, `scripts/`,
`.qsf`, or `.m` edits land here. This change details the design; implementation
lands when it is started.

## The approximation subtlety (central to this change)

Sliding-window BCJR with a **finite** acquisition `L` is an **APPROXIMATION** —
its β (and therefore the extrinsic) is **not bit-exact** to the full-block
decoder, because the full-block β is recursed from the true terminated end state
across the whole block, whereas the windowed β is recursed from only an `L`-step
flat-initialized warm-up. The approximation error shrinks as `L` grows and
(prototype evidence, design.md §3) becomes negligible — even bit-exact — for an
adequate `L`. The consequence for verification is decisive:

> The windowed core **CANNOT** reuse `fixedpoint_constituent_decoder.m` (the
> full-block oracle) as its bit-exact reference. It needs a **new windowed
> fixed-point reference** that the RTL is bit-exact to (the inner gate), **plus**
> an explicit **windowed-vs-full-block** equivalence/BER check that quantifies
> and bounds the windowing loss (the outer gate).

This is exactly the two-tier discipline the roadmap §1 already mandates, with the
inner reference re-authored for the windowed traversal and one extra outer band
(windowing loss) layered on.

## Capabilities

### New Capabilities

- `fpga-decoder-sliding-window`: a windowed-α/β (sliding-window BCJR with
  checkpoints + `L`-step β acquisition) memory architecture for the constituent
  decoder that bounds α storage to `≈ 8 × W` so the full K = 6144 turbo decoder
  fits the EP2C35, with a **new** sliding-window fixed-point reference
  establishing a new bit-exact contract and a documented windowing-loss band
  against the full-block decoder.

## Impact

- Extends `fpga-constituent-decoder` (and transitively `fpga-turbo-decode-loop`,
  `fpga-turbo-decoder-termination`, `fpga-rx-chain-integration`) with a new α/β
  memory architecture; **changes the bit-exact golden-vector contract**. Because
  windowing is applied **inside** `constituent_decoder`, all decoder tops benefit
  automatically and their streaming interfaces are unchanged.
- The pinned fixed-point widths (`W_in = 9 … W_xe = 18`, ±inf sentinel,
  per-step max-norm) are inherited **UNCHANGED** — only the α/β schedule and
  storage change.
- Depends on the existing two-tier discipline (cocotb bit-exact + Quartus fit)
  and Quartus II 13.0sp1 on the Windows host.
- Risk: the bit-exact-contract change means a fresh windowed reference +
  characterization is the safety-critical artifact (roadmap §1); `W`/`L` and
  whether to recompute or checkpoint α trade RAM against recompute cycles and
  latency and are pinned in design.md with prototype evidence.

## Out of Scope (explicit)

- Exact Log-MAP accuracy (that is M1 / `add-fpga-decoder-exact-log-map`).
- Recurrence pipelining for Fmax (that is `add-fpga-decoder-recurrence-pipelining`).
- Fixed-point width tightening (that is M3); the P1 widths are inherited as-is.
- Any change to the constituent or top-level **streaming interface** (ports,
  load/output cadence) — windowing is an internal-memory-and-schedule change.
- Any board demo of the K = 6144 fit beyond the Quartus fit gate.
