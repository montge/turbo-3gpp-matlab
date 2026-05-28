## Context

The fixed-point Max-Log-MAP decoder is sim-complete and bit-exact in
GHDL/cocotb:

```
turbo_decoder_top  =  constituent_decoder (reused, sequentially: upper, lower)
                      + qpp_rom + qpp_interleaver
turbo_decoder_term_top  =  turbo_decoder_top  + crc24_check + HARQ accumulate
```

The TX block-RAM change (`add-fpga-block-ram-inference`, archived 2026-05-23)
empirically established — with a reduced test on the exact toolchain (Quartus II
13.0sp1, `EP2C35F672C6`) — the inference blocker and its fix:

1. A clean sync-read array with `(others=>'0')` init **does** infer
   altsyncram/M4K, even with two read ports or a loose index range.
2. Wrapping the array **write** inside the `if rst='1' then … else … end if`
   synchronous-reset branch **defeats** inference (`Total memory bits : 0`);
   lifting the identical write to the **top level** of the clocked process
   (reset touching only the index/control registers, never the array body)
   makes the same array infer M4K.

**A READ-ONLY decoder audit confirmed every `turbo_decoder_top`-path memory has
this exact blocker** — the write is in the reset-guarded `case` body and the
read is asynchronous. So none of them infer M4K as-is, and a
`turbo_decoder_top` build would be a large LE register bank (the α-RAM alone
dominates). The fix is the same proven recipe, applied per memory.

### The memories in scope (audit-confirmed, cite against the RTL)

`constituent_decoder.vhdl` (dominant; reused by every decoder lane):

| Memory | Shape | Decl | Write (reset-guarded) | Async read |
|---|---|---|---|---|
| `alpha_mem` | `8 × (K+3) × 15` | ~153 | ~258 (col-0 init), ~292 (`S_FWD`) | ~280/282 (`S_FWD`), backward δ |
| `xa_mem` | `(K+3) × 9` | ~155 | ~252 (`S_LOAD`) | ~274 (`S_FWD`) |
| `za_mem` | `(K+3) × 9` | ~157 | ~253 (`S_LOAD`) | ~275 (`S_FWD`) |

`turbo_decoder_top.vhdl` (loop level):

| Memory | Shape | Decl | Write (reset-guarded) | Read |
|---|---|---|---|---|
| `za_mem` | `(K+3)`-deep | ~192 | ~378/386/392/396 (`S_LOAD_D`) | ~477 |
| `zpa_mem` | `(K+3)`-deep | ~193 | ~380/402/408/412 | ~540 |
| `chs_mem` | `K × 12` | ~196 | ~376 | ~471/490/496/591 |
| `ca_mem` | `K × 12` | ~202 | ~419 (init), ~575 (**scatter**) | ~471/591 |
| `ce_mem` | `K × 12` | ~203 | ~491/497 | ~519 |
| `xpa_body` | `K × 12` | ~263 | ~519 | ~536 |
| `xpe_body` | `K × 12` | ~264 | ~552/556 | ~575 |

The datapath is **0-multiplier** (max/add saturating helpers only) — no DSP
concern. With the memories inferred, the `K=512` build is expected at ~3k LE /
~18 M4K, fitting the EP2C35 (33,216 LE / 105 M4K) with large headroom.

## Goals / Non-Goals

**Goals**

- Make every `turbo_decoder_top`-path memory (constituent `alpha_mem`/`xa_mem`/
  `za_mem`; turbo `za_mem`/`zpa_mem`/`chs_mem`/`ca_mem`/`ce_mem`/`xpa_body`/
  `xpe_body`) infer Cyclone II **M4K block RAM** under Quartus II 13.0sp1.
- Keep every change **bit-exact**: the `constituent_decoder`,
  `turbo_decoder_top`, and `turbo_decoder_term_top` cocotb lanes stay green and
  the committed golden vectors are byte-identical.
- Make a `turbo_decoder_top` build fit the EP2C35 and close 50 MHz timing —
  at the cores' default `K_MAX` (the inference proof) and at **`K = 512`** (the
  board demo) — with the fit report showing `M4K > 0` / `Total memory bits > 0`
  and multipliers = 0.

**Non-Goals**

- No `turbo_decoder_term_top` memory work (HARQ buffer, `crc24_check` matrices)
  — deferred (see proposal Out of Scope). `term_top`'s lane is only a
  shared-core regression gate.
- No sliding-window / algorithmic α rework (M2). The full-block α store stays;
  only its memory inference changes.
- No fixed-point / width changes; no UART; no DE1; no on-board large-`K` run.

## Decisions

### 1. Lift each memory out of the reset-guarded FSM body (the core fix)

Adopt the canonical "RAM in its own process; FSM owns only address / we /
control" pattern for each array, proven to infer in the TX reduced test:

```vhdl
-- Memory process: unconditional, no reset on the array body.
process(clk) begin
  if rising_edge(clk) then
    if we = '1' then mem(wr_addr) <= wr_data; end if;  -- top-level write
    rd_data <= mem(rd_addr);                            -- registered read
  end if;
end process;
-- FSM process keeps its if rst then..else case.. but drives ONLY
-- wr_addr/we/rd_addr/wr_data and reads rd_data — never the array itself.
```

Per memory:

- **`constituent_decoder` `alpha_mem`** (dominant). The forward sweep writes
  column `kidx` from a max-normalized combination of column `kidx-1`; the
  backward sweep re-reads columns for the δ computation. Lift the column write
  out of the `if rst … else case` body; **register the previous-column read**
  so the forward recurrence reads `alpha_mem(kidx-1)` from a registered port
  rather than combinationally. Because each forward column needs the **whole**
  prior 8-state column (for the per-step max-norm), the registered read must
  present that column one cycle ahead — handle via a prefetch beat or a
  shadow register of the just-written column (the value is already in hand the
  cycle it is written, so the recurrence can forward it without a RAM read on
  the immediately-next column). Whatever the scheme, the emitted `x_e` must be
  bit-identical (the cocotb lane is the proof). See Open Questions on the
  max-norm read pattern.
- **`constituent_decoder` `xa_mem`/`za_mem`** — each a clean 1W/1R
  simple-dual-port: write in `S_LOAD` lifted out of the reset-guarded body,
  the `S_FWD` read (`xa_mem(kidx-1)`, `za_mem(kidx-1)`) registered. The
  one-cycle read latency is absorbed by aligning with the α prefetch (the
  forward sweep already advances one column per cycle).
- **`turbo_decoder_top` `za_mem`/`zpa_mem`** — persistent, set once at load,
  read sequentially during core feed. 1W/1R simple-dual-port each; write lifted
  out of `S_LOAD_D`, the feed read registered.
- **`turbo_decoder_top` `chs_mem`** — 1 write port (load), several sequential
  read taps (accumulate, capture, final decision). Each read tap registered;
  reads are at distinct indices in distinct phases, so a single read port
  time-shared per phase suffices.
- **`turbo_decoder_top` `ce_mem`** — written by the upper-decoder accumulate,
  read by the PI1 interleave (`ce_mem(pi_idx)`). The interleave read is
  data-dependent in **address** but is a pure read; 1W/1R simple-dual-port with
  the read registered.
- **`turbo_decoder_top` `xpa_body`/`xpe_body`** — 1W/1R each; writes lifted,
  reads registered.

### 2. `ca_mem` → simple-dual-port with read-during-write pinned (top risk)

`ca_mem` is the highest-risk memory. It has:

- a **scatter write** at the data-dependent QPP-deinterleave index
  `ca_mem(pi_idx) <= xpe_body(pi_k)` (~575, in `S_LO_PI2`),
- an init write `ca_mem(k) <= 0` (~419), and
- **sequential reads** at `ca_mem(feed_idx)` (~471, upper accumulate) and
  `ca_mem(out_idx)` (~591, final decision).

As M4K it must be a **simple-dual-port**: one write port (driven at `pi_idx`
during the deinterleave scatter, or at the init index) and one read port
(sequential `feed_idx`/`out_idx`). The phases are disjoint in the schedule —
the PI2 scatter (writes) completes before the next upper half's accumulate
(reads) begins, and the final decision read happens after the last scatter — so
the bit-exact path **never reads the address being written in the same cycle**.
That makes the inferred `READ_DURING_WRITE_MODE` (OLD_DATA / don't-care)
harmless. **This must be confirmed**: the read-old vs read-new behaviour of the
inferred SDP must match the GHDL behavioural model, and a future edit must not
introduce a same-address same-cycle RDW. Pin it in the spec and the lane.

The init loop (`for k … ca_mem(k) <= 0`, ~419) currently zeroes the whole array
in the reset/load region; as a lifted single write port it becomes a sequenced
clear (one address per cycle) or relies on a `valid`/first-write flag so unread
stale words never reach the datapath. Keep it bit-exact (the first upper half
reads `ca_mem` only after the init or the prior-iteration scatter has populated
the read indices).

### 3. Absorbing the added read latency (bit-exactness)

Registering the reads adds one cycle of latency on each memory path. As in the
TX change, this is absorbed **inside the owning FSM** (a prefetch/prime beat or
an extra wait substate), so the externally observed streams — the constituent
`x_e` sequence and the turbo decoded-bit stream — are **identical
cycle-for-cycle in content** (the cocotb lanes compare values, and stay green).
The forward α recurrence is the most latency-sensitive (it reads the prior
column every cycle); the prefetch/forward-the-just-written-column scheme keeps
it single-cycle-per-column without a stall, or accepts a documented one-beat
prime that does not change any output value.

### 4. α-RAM max-norm read pattern

Each forward column reads all 8 states of the prior column to compute the
per-step max-normalization, then writes all 8 states of the current column.
Stored as a `state_vec` (8 × 15-bit) word per column, `alpha_mem` is a
`(K+3)`-deep × 120-bit memory — one M4K-word per column, so the whole prior
column comes back in one registered read. At `K=512`: `515 × 120 = 61,800`
bits ≈ 14 M4K (M4K is 4096 bits; 120-bit words pack ~34 words/M4K so depth
drives the count). The registered single-port read of the prior column is the
natural M4K shape; the recurrence forwards the just-computed column to avoid a
read bubble. The backward sweep re-reads columns for δ in reverse; that is a
second sequential read port (SDP) or a re-use of the same registered read in a
distinct phase. Confirm the exact M4K count and that no extra port is needed
during stage 1 fit.

### 5. Explicit `ramstyle = "M4K"` attribute (belt-and-suspenders)

Annotate each array signal `ramstyle = "M4K"` (Cyclone II has only M4K block
RAM) so inference is asserted at source and a future refactor that re-buries a
write fails loudly (wrong resource) rather than silently reverting to LE. The
attribute alone does not force inference — Decision 1 is what makes it infer;
the attribute guards intent.

### 6. Fallback: explicit `altsyncram` instantiation

If a memory still resists inference under 13.0sp1 after Decisions 1–5 (most
likely `ca_mem`'s scatter SDP or `alpha_mem`'s wide word), fall back to an
explicit `altsyncram` megafunction behind the same port behaviour (registered
read, 1W/1R or SDP). Keep it behind a wrapper so GHDL simulation (no
`altsyncram`) uses a behavioural model and the cocotb lane stays portable.
Prefer inference; instantiate only where necessary.

### 7. How bit-exactness is preserved and confirmed (two-tier gate)

- **Inner gate — cocotb / GHDL, bit-exact (functional oracle).** Re-run the
  `constituent_decoder`, `turbo_decoder_top`, and `turbo_decoder_term_top`
  lanes against the **unchanged** committed golden vectors. `term_top` shares
  both reworked cores, so its lane is part of the gate even though its own
  memories are untouched. No vector is regenerated.
- **Outer gate — Quartus II 13.0sp1 fit report (synthesis oracle).** Compile
  `turbo_decoder_top` and assert from the report: `Total memory bits > 0` and
  inferred M4K count `> 0` (~18 M4K expected at `K=512`, of 105); the device
  fits (LE well under 33,216); multipliers = 0; and `Fmax ≥ 50 MHz` (positive
  setup + hold slack on `CLOCK_50`). Run at the cores' default `K_MAX` (the
  general inference proof) and at `K = 512` (the board demo). Both fit reports
  are recorded deliverables.

## Risks / Trade-offs

- **`ca_mem` scatter SDP is the top risk.** A data-dependent write index plus
  sequential reads is exactly the shape that can trip inference or surface a
  read-during-write divergence. *Mitigation:* model it as a clean 1W (scatter) /
  1R (sequential) SDP with disjoint phases; the `turbo_decoder_top` cocotb lane
  (all `K`/SNR/iteration cases) is the gate; `altsyncram` fallback if needed.
- **Iterative-loop timing closure on the deep trellis path at 50 MHz.** The
  forward/backward sweeps with registered α reads add pipeline depth on the
  longest combinational path (the 8-way max + max-norm + saturate per column).
  Registering the RAM reads can *help* Fmax (it breaks the async-read combinational
  cone) but the per-column arithmetic must still close. *Mitigation:* the fit
  report's `Fmax`/slack is the gate; the datapath is 0-mult and max/add only.
- **α-RAM at `K=512` is ~14 M4K** — the dominant consumer. Comfortable against
  105 M4K, but at full `K=6144` the full-block α store is ~165 Kbit and starts
  to crowd; that is why the board demo is pinned at `K=512` and the full-`K_MAX`
  fit is only the *inference* proof, not a board target (pushing past `K≈2700`
  needs the sliding-window M2 rework — out of scope).
- **Latency shifts changing an output value.** Registering reads must not shift
  the cycle on which a value reaches the datapath in a way that changes content.
  *Mitigation:* absorb in the FSM (Decision 3); the lanes re-confirm bit-exact.
- **13.0sp1 inference quirks.** Calibrated on the TX reduced test; the wide
  `alpha_mem` word and the `ca_mem` SDP are new shapes. *Mitigation:* per-memory
  fit inspection in stages 1–2; `altsyncram` fallback.

## Open Questions

- **`ca_mem` read-during-write — old vs new?** The bit-exact path keeps write
  (PI2 scatter) and read (accumulate / final decision) phases disjoint, so RDW
  should be don't-care. Confirm against the GHDL model that no case reads a
  just-scattered address in the same cycle, and pin the inferred SDP's RDW mode
  accordingly. This is the single most important question to resolve before
  accepting the `ca_mem` rework.
- **Constituent and turbo reworked in one stage or split?** Default: split —
  stage 1 does `constituent_decoder` (the dominant α-RAM, independently
  fit-checkable and reused by all lanes), stage 2 does `turbo_decoder_top`.
  Confirm whether the α latency-absorb forces the two to be co-designed.
- **Target `K` for the fit check.** Default the cocotb gate at the cores'
  default `K_MAX` (constituent `N_MAX=6147`, turbo `K_MAX=6144`) for the
  inference proof, plus a `K = 512` fit toward the board demo. Confirm the
  board demo `K` (user-chosen `512`) and whether the full-`K_MAX`
  `turbo_decoder_top` even needs to *fit* (α at `K_MAX` exceeds on-chip RAM) or
  whether the inference proof at `K_MAX` is satisfied by the **per-core**
  constituent fit while the **integrated** fit is asserted only at `K=512`.
- **α-RAM word packing.** Whether to keep `alpha_mem` as one wide
  (120-bit) word per column (one M4K read returns the whole column) or split
  into 8 per-state arrays. Default: wide word (matches the max-norm read of the
  whole column in one cycle). Confirm the M4K count/fit either way.
- **`ramstyle` attribute syntax under 13.0sp1.** Confirm the VHDL attribute is
  honoured (`attribute ramstyle : string; attribute ramstyle of sig : signal is
  "M4K";`) vs needing a `.qsf` setting; the structural fix is primary either way.
- **Fit-report gate scripted or manual?** Default: recorded manual step (no CI
  synthesis lane), matching the TX change and project practice.
