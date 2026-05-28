## Why

The DE2 TX-chain demo is hardware-verified, and the just-archived
`add-fpga-block-ram-inference` change proved the route to put a full-capacity
core on the Cyclone II `EP2C35F672C6`: make its memories infer M4K block RAM
instead of LE register fabric. **The decoder is the next thing to put on the
board.** The goal of this change is a `turbo_decoder_top` board demo at the
user-chosen **`K = 512`** that produces real decoded bits and fits the DE2.

A READ-ONLY audit of the decoder RTL against the verified TX root cause found
that **every** memory on the `turbo_decoder_top` path has the exact inference
blocker the TX change fixed:

- The array **write** is nested inside the reset-guarded FSM body
  (`if rst = '1' then … else case st … end case end if`), which Quartus II
  13.0sp1 reads as a write gated/cleared by the synchronous reset — violating
  the M4K write-port template (no array-content clear) — so it falls back to LE
  registers (`Total memory bits : 0`).
- The reads are **asynchronous** (combinational array index into a variable in
  the same cycle), which the M4K template also disallows.

As-is, none of the decoder memories infer M4K, so even a modest-`K`
`turbo_decoder_top` would synthesize to a large LE register bank and not fit.
The dominant store is the constituent decoder's full-block α-RAM
(`8 · (K+3) · 15` bits — at `K=512` that is ~14 M4K). The decoder datapath is
**0-multiplier** (max/add only), so there is no DSP concern; with the memories
inferred the `K=512` build is expected to fit at ~3k LE / ~18 M4K with large
headroom (the EP2C35 has 33,216 LE / 105 M4K / 483,840 RAM bits).

This change is the **decoder-side analog** of the archived TX block-RAM change:
same root cause, same fix (lift the write to the clocked-process top level +
register the read + `ramstyle = "M4K"`), same dual gate (cocotb bit-exact +
Quartus fit report). It is **planning only** — no RTL lands here.

## What Changes

Restructure each `turbo_decoder_top`-path memory to hit the Quartus M4K
inference template, **bit-exact**, by lifting the array read/write out of the
reset-guarded FSM body into a dedicated unconditional clocked memory process,
with the FSM driving only address / write-enable / write-data / read-address:

- **`constituent_decoder.vhdl`** (the dominant memories — reused by every
  decoder lane):
  - `alpha_mem` — full-block α storage, `8 × (K+3) × 15` bits (decl ~153;
    init/write ~258/280/292; async reads ~280/282 in the forward sweep and the
    backward δ computation). **Dominant**. 1W (per-column α write) + read of the
    previous column; lift the write out of the reset-guarded `case`, register
    the previous-column read, absorb the added read latency in the sweep so
    `x_e` stays bit-exact. The per-step max-normalization read pattern needs
    care (each forward column reads the whole prior column).
  - `xa_mem` / `za_mem` — input LLR storage, `(K+3) × 9` bits each (decl
    ~155–157; writes ~252–253 in `S_LOAD`; async reads ~274–275 in `S_FWD`).
    Each a 1W/1R simple-dual-port M4K; write lifted out of the `if rst … else
    case` body, read registered.
- **`turbo_decoder_top.vhdl`** (the loop-level memories):
  - `za_mem` / `zpa_mem` — persistent parity+termination, `(K+3)`-deep (decl
    ~192–193; writes ~376–412 in `S_LOAD_D`; reads ~477/540). 1W/1R each.
  - `chs_mem` — `ch_sys` body, `K × 12` (decl ~196; write ~376; reads
    ~471/490/496/591). 1W/multi-read; lift write, register reads.
  - `ca_mem` / `ce_mem` — cyclic extrinsic state, `K × 12` each (decl ~202–203;
    writes ~419/491/497 and the scatter ~575; reads ~471/519/591).
  - `xpa_body` / `xpe_body` — interleave-read / captured-extrinsic bodies,
    `K × 12` each (decl ~263–264; writes ~519/552/556; reads ~536/575). 1W/1R.
  - **`ca_mem` scatter write is the highest risk.** Line ~575 does
    `ca_mem(pi_idx) <= xpe_body(pi_k)` — a **data-dependent
    (QPP-deinterleave) write index** while the reads (~471 accumulate,
    ~591 final decision) are **sequential**. As M4K this MUST become a
    **simple-dual-port** (one write port at `pi_idx`, one sequential read port).
    The same-cycle read-during-write semantics (read-old vs read-new) must be
    pinned to match the simulation reference.

Preserve the secondary template points the TX reduced-test confirmed are
tolerated: power-up init `:= (others => '0')` (where present), no asynchronous
clear on the array body, a defined read-during-write mode (never reading the
just-written address in the same cycle on the bit-exact path). Add
`ramstyle = "M4K"` to each array signal as belt-and-suspenders; fall back to an
explicit `altsyncram` instantiation behind the same port behaviour only if a
memory still resists inference under 13.0sp1.

**Bit-exactness is preserved.** The existing decoder cocotb lanes
(`constituent_decoder`, `turbo_decoder_top`, and `turbo_decoder_term_top` —
which shares both cores) stay green and the committed golden vectors are
**byte-identical**. Any read/write scheduling shift is absorbed inside the
owning FSM exactly as the TX sync-read hardening did.

## Capabilities

### New Capabilities

- **`fpga-decoder-block-ram-inference`** — a synthesis-oracle capability: the
  `turbo_decoder_top`-path memories SHALL infer as Cyclone II M4K block RAM
  under Quartus II 13.0sp1, so that a `turbo_decoder_top` build (at the cores'
  default `K_MAX` for the inference proof, and at `K = 512` for the board demo)
  fits the EP2C35 and closes 50 MHz timing, validated by a **two-tier gate** —
  the decoder cocotb lanes (functional bit-exactness) AND the Quartus fit report
  (the synthesis oracle: `Total memory bits > 0` / `M4K > 0`, device fits,
  `Fmax ≥ 50 MHz`, multipliers = 0). This mirrors the archived
  `fpga-block-ram-inference` capability for the TX side; nothing in the existing
  fpga-* specs asserts a block-RAM-inference property for the decoder cores.

### Modified Capabilities

- **`fpga-constituent-decoder`** — add a requirement that `alpha_mem`, `xa_mem`,
  and `za_mem` infer M4K (write lifted out of the reset-guarded FSM body; sync
  read; defined RDW; `ramstyle = "M4K"`), bit-exact to the fixed-point reference
  and the existing `constituent_decoder` cocotb lane.
- **`fpga-turbo-decode-loop`** — add a requirement that `za_mem`/`zpa_mem`,
  `chs_mem`, `ca_mem`/`ce_mem`, and `xpa_body`/`xpe_body` infer M4K, including
  the **`ca_mem` simple-dual-port split** (scatter write port + sequential read
  port) with read-during-write semantics pinned to the reference, bit-exact to
  the fixed-point full-loop reference and the existing `turbo_decoder_top`
  cocotb lane.

**Decision — new capability *and* modify the two cores (mirror the TX change).**
The per-core deltas pin the inference fix where the RTL lives (each core stays
self-describing). But "the decoder memories must infer M4K and the
`turbo_decoder_top` build must fit + close timing, proven by the Quartus fit
report" is a **cross-cutting synthesis-oracle property** that no single core
spec owns, and it carries a **new verification gate** (the fit report alongside
cocotb). That deserves its own capability rather than being smeared across the
two core specs. This is exactly the new-capability + modify-cores shape the
archived TX block-RAM change used (`fpga-block-ram-inference` +
`fpga-circular-buffer`/`fpga-rate-matching`/`fpga-turbo-encoder`).

## Impact

- **Planning only in this change** — no `hdl/`, `scripts/`, `.qsf`, `.m` edits
  land here. This is the proposal; implementation follows the staged `tasks.md`.
- When implemented: `hdl/rtl/constituent_decoder.vhdl` and
  `hdl/rtl/turbo_decoder_top.vhdl` are restructured for M4K inference
  (bit-exact preserved). A `turbo_decoder_top` board target (`K = 512`) and a
  full-`K_MAX` fit harness are produced.
- `turbo_decoder_term_top` and the reused `qpp_rom` / `qpp_interleaver` need no
  change here, but the `term_top` cocotb lane is re-run because it shares the
  two reworked cores — it MUST stay bit-exact.
- Depends on Quartus II 13.0sp1 on the existing Windows host; the fit-report
  gate is a local/manual synthesis step (not CI), exactly as the TX change's
  fit was. Requires no physical DE2 hardware to verify (cocotb + fit/timing
  report).

## Out of Scope (explicit — separate / later increments)

- **`turbo_decoder_term_top`'s own memories** — the HARQ soft-combining buffer
  and the two `6144 × 24` `crc24_check` generator matrices (~65 M4K fixed tax).
  These are deferred; a `term_top` board build is a later, heavier effort.
  `term_top` is touched here only as a **shared-core regression gate** (its
  lane re-runs), not as a fit target.
- The **algorithmic** sliding-window α rework (the decoder roadmap's M2 item).
  This change keeps the **full-block** α store and only changes its memory
  *inference*, not the algorithm. At `K = 512` the full-block α store is
  ~14 M4K and fits comfortably; the sliding-window rework is what is needed to
  push past `K ≈ 2700`, and is a separate increment.
- Fixed-point / width changes (the decoder Q-formats stay as committed).
- UART / host link; on-board large-`K` program-and-observe; DE1.
