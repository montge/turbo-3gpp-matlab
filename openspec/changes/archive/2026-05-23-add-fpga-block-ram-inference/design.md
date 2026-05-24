## Context

The complete LTE transmit chain is sim-complete and bit-exact in GHDL/cocotb:

```
tx_chain_top  =  turbo_encode_top  →  rate_matching_top
                 (qpp_rom + qpp_         (3× subblock_interleaver
                  interleaver +           + circular_buffer)
                  turbo_encoder)
```

The `add-fpga-tx-chain-de2-demo` change synthesis-hardened the three TX memories
to **synchronous read** (registered read address, one-cycle latency absorbed in
each FSM via a prime/prefetch beat) and made `circular_buffer` divider-free.
That was enough for a **K=40** board demo — but only because the buffer depths
were parameterized down (`MAXK=64`, `DMAX=64`, `KW_MAX=256`) so the buffers fit
as LE register fabric. Running the real Quartus II 13.0sp1 fit on the
**full-size** chain exposed the deferred problem:

> **`Total memory bits : 0`** — no buffer inferred M4K; the full-`K` design was
> ~85k LE (2.5× over the EP2C35's 33,216) → cannot fit.

### What the reduced-test investigation found (Quartus II 13.0sp1, EP2C35F672C6)

A standalone synthesis of `turbo_encode_top` at full `MAXK=6144` reproduced
`Total memory bits : 0` (15,683 LE, no "Inferred … megafunction" message). A
series of minimal RAM test entities then bisected the cause:

1. **A clean sync-read 1-bit-wide array (depth 6144) with init `(others=>'0')`
   DOES infer altsyncram/M4K** — even with *two* read ports on the same array,
   even with an over-range read index (`integer range 0 to MAXK` reading an
   `array(0 to MAXK-1)`). So none of: 1-bit width, the power-up init, the dual
   read tap, or the loose index range is the blocker.
2. **Wrapping the array *write* inside the `if rst='1' then … else … end if`
   synchronous-reset branch defeats inference** — the identical array, written
   at the *top level* of the clocked process (reset touching only the index
   registers, not the memory body), infers M4K (`Total memory bits` jumps from
   0 to > 0). This was isolated with a two-array A/B test where the only
   difference was write placement: the reset-wrapped one stayed registers, the
   top-level one became altsyncram.

**Conclusion:** the inference blocker shared by all three TX memories is that
the array write lives inside the reset-guarded FSM body
(`turbo_encode_top` `buf` write at `S_LOAD`; `rate_matching_top` `d1/d2/d3buf`
at `S_LOADD`; `circular_buffer` `w_bit`/`w_fill` at `S_LOAD`) — Quartus 13.0sp1
reads that as a write gated/cleared by the synchronous reset, which violates the
M4K write-port template (no array-content clear), so it bails to LE registers.
The sync-read style added earlier is correct and necessary; only the **write
placement** (plus the secondary template points below) must change.

## Goals / Non-Goals

**Goals**

- Make `circular_buffer` `w_bit`/`w_fill`, `rate_matching_top` `d1/d2/d3buf`,
  and `turbo_encode_top` `buf` infer Cyclone II **M4K block RAM** under Quartus
  II 13.0sp1.
- Keep every change **bit-exact**: the four cocotb lanes stay green and the
  committed golden vectors are byte-identical.
- Make a **full-`K`** `tx_chain_top` build (`K` up to 6144, or a documented
  intermediate) **fit the EP2C35 and close 50 MHz timing**, with the fit report
  showing `M4K > 0` / `Total memory bits > 0`.

**Non-Goals**

- No decoder memory work, no sliding-window, no UART, no DE1, no on-board
  large-`K` run (all out of scope, see proposal).
- No change to the divider-free arithmetic already landed (the `q`/`pos`
  recurrences stay).
- No fixed-point / width changes (TX chain is bit/integer logic).
- No algorithmic change — only the *implementation* of the memories changes;
  the standard-defined behaviour and every output bit are identical.

## Decisions

### 1. Lift each memory out of the reset-guarded FSM body (the core fix)

Adopt the canonical "RAM in its own process; FSM owns only address / we /
control" pattern for each array, proven to infer in the reduced test:

```vhdl
-- Memory process: unconditional, no reset on the array body.
process(clk) begin
  if rising_edge(clk) then
    if we = '1' then buf(wr_addr) <= wr_data; end if;  -- top-level write
    rd_data <= buf(rd_addr);                            -- registered read
  end if;
end process;

-- FSM process keeps its if rst then..else case.. but drives ONLY
-- wr_addr/we/rd_addr/wr_data and reads rd_data — never the array itself.
```

- **`turbo_encode_top` `buf`** — one write port (`S_LOAD`) + two read taps
  (`buf(didx)`, `buf(pi_idx)`). M4K is at most dual-port, and 1W+2R is three
  ports, so split into **two simple-dual-port copies** written identically
  (`bufN` read by `didx`, `bufP` read by `pi_idx`) — each a clean 1W/1R M4K.
  Reads are already registered into `cbit_r`/`cpbit_r`; only the write moves out
  of the `if rst … else case` body. The `S_ENC_PRIME` prefetch beat already
  absorbs the read latency; behaviour is unchanged.
- **`rate_matching_top` `d1/d2/d3buf`** — three independent 1W/1R simple-dual-
  port M4Ks; writes (`S_LOADD`) lifted to a top-level memory process; the
  registered reads (`rd1/rd2/rd3`) and the pipelined filler/valid taps already
  realign the `v` columns, so the loaded columns stay identical.
- **`circular_buffer` `w_bit`/`w_fill`** — two 1W/1R simple-dual-port M4Ks. The
  `S_LOAD` step writes three positions per `v` column (`w[cidx]`,
  `w[K_Pi+2·cidx]`, `w[K_Pi+2·cidx+1]`). A single write port cannot do three
  writes/cycle, so the load is **re-sequenced** (e.g. three sub-beats per column
  or a two-bank split keyed on the address parity) into a single-write-port
  schedule, lifted out of the reset-guarded `case`. The sync read (`rd_addr` →
  `rd_bit`/`rd_fill`) and the `S_PRIME` fill beat are unchanged. Crucially the
  re-sequenced load must still present the *same* `w` contents before the read
  begins — the cocotb lane is the proof.

### 2. Preserve the secondary template points the test showed are tolerated

- **Power-up init `:= (others => '0')`** — kept. The test confirmed it does not
  block inference (maps to a `.mif`/init, `ADDRESS_ACLR = NONE`). Bit-exactness
  relies on it (buffers read 0 at unwritten positions on filler columns).
- **No asynchronous clear on the array** — none today; keep it that way.
- **Read-during-write** — the bit-exact path never reads the address being
  written in the same cycle (load completes before read starts), so the inferred
  `READ_DURING_WRITE_MODE = OLD_DATA`/don't-care is harmless. Document it so a
  future edit does not introduce a same-address RDW that would change a bit.

### 3. Explicit `ramstyle = "M4K"` attribute (belt-and-suspenders)

Annotate each array signal with the Quartus attribute
`ramstyle = "M4K"` (Cyclone II has no MLAB/M9K; M4K is the only block-RAM
flavour) so inference is asserted at the source and a future refactor that
re-buries a write fails loudly (wrong resource) rather than silently reverting
to LE. The attribute alone does **not** force inference if the template is
violated — the structural fix in Decision 1 is what makes it infer; the
attribute guards the intent.

### 4. Fallback: explicit `altsyncram` instantiation

If a memory still resists inference under 13.0sp1 after Decisions 1–3 (e.g. the
`circular_buffer` re-sequenced multi-write load proves awkward), fall back to an
**explicit `altsyncram` megafunction instantiation** behind the same port
behaviour (registered read, 1W/1R). This is deterministic (no reliance on the
inference heuristics) at the cost of a Cyclone-II-specific primitive in the RTL.
Prefer inference; instantiate only where necessary, and keep it behind a wrapper
so GHDL simulation (which has no `altsyncram`) still uses a behavioural model —
the cocotb lane must stay portable. (Open question: how many, if any, need this.)

### 5. How bit-exactness is preserved and confirmed (two-tier gate)

- **Inner gate — cocotb / GHDL, bit-exact (functional oracle).** Re-run the
  `circular_buffer`, `rate_matching_top`, `turbo_encode_top`, and `tx_chain_top`
  lanes against the **unchanged** committed golden CSVs. Any read/write
  re-scheduling is absorbed in the owning FSM so the emitted streams are
  identical; no vector is regenerated. This is the same discipline the prior
  sync-read hardening passed.
- **Outer gate — Quartus II 13.0sp1 fit report (synthesis oracle).** Compile the
  full-`K` `tx_chain_top` build and assert, from the report:
  - `Total memory bits > 0` and the inferred-megafunction / M4K count `> 0`
    (expectation ≈ 12 M4K, ~55 Kbit; the EP2C35 has 105 M4K / 483,840 bits);
  - the device **fits** (LE well under 33,216 — the buffers leave register
    fabric for logic only);
  - **`Fmax ≥ 50 MHz`** (setup + hold slack positive on the `CLOCK_50` domain).
  This fit report is a new, recorded deliverable — the synthesis oracle that the
  simulation-only gate cannot provide.

## Risks / Trade-offs

- **`circular_buffer` multi-write load re-sequencing is the top risk.** Going
  from three array writes/cycle to a single-write-port schedule changes the load
  timing; a mis-sequenced load corrupts `w` and hence the output.
  *Mitigation:* the `circular_buffer` cocotb lane (all `rv_idx∈{0,1,2,3}`, both
  `I_LBRM`, the buffer-wrap `E`) is the gate; not accepted until bit-exact with
  the committed vectors unchanged. A two-bank (even/odd address) split is an
  alternative that keeps one write/bank/cycle without re-sequencing.
- **Read-during-write semantics changing an output bit.** If the re-sequenced
  load ever reads an address in the same cycle it is written, the inferred RDW
  mode (`OLD_DATA`) could differ from the GHDL behavioural read.
  *Mitigation:* keep load and read phases disjoint (they already are); assert it
  in review; the cocotb lane catches any divergence.
- **Latency shifts.** Lifting the write out of the FSM must not change the cycle
  on which data is available to the read. The reads are already registered and
  latency-absorbed; moving only the *write* placement should not shift read
  timing — but the lanes re-confirm it.
- **13.0sp1 inference quirks.** The reduced test was on this exact toolchain, so
  the template is calibrated to it; still, the full design may surface a new
  quirk (e.g. the two-copy `buf` not merging). *Mitigation:* the fit report is
  inspected per memory; the `altsyncram` fallback (Decision 4) is the escape.
- **Two `buf` copies double the encoder's write fan-out / bits.** Two 6144-bit
  copies = 12 Kbit ≈ 3 M4K instead of 1; still trivial against 105 M4K.
  Acceptable; M4K is the budget that is abundant, LE is the scarce one.

## Open Questions

- **Which memories can infer cleanly vs need explicit `altsyncram`?** Expect all
  three to infer after the write-placement fix (the reduced test inferred the
  equivalent shapes); `circular_buffer`'s multi-write load is the one most
  likely to need the two-bank trick or the fallback. Confirm during stage 1–3
  per-memory fit checks.
- **Target `K_MAX` for the "full" build.** True maximum `K=6144`
  (`MAXK=6144`/`DMAX=6148`/`KW_MAX=18528`), or a documented intermediate (e.g.
  `K≤2048`) if a surprise resource/timing issue appears? Default: `K=6144`
  (the buffers are ~55 Kbit ≈ 12 M4K, well within 105). Confirm the build target
  the fit gate must satisfy.
- **Keep the K=40 demo wrapper's small overrides?** They are harmless and let
  the existing board self-check keep running; but the fit *proof* for this
  change is the full-`K` build. Default: keep the demo overrides, add a separate
  full-`K` fit target. Confirm.
- **`ramstyle` attribute syntax under 13.0sp1.** Confirm the attribute is
  honoured (`attribute ramstyle : string; attribute ramstyle of sig : signal is
  "M4K";`) vs needing the `.qsf` `RAMSTYLE`/inference settings; the structural
  fix is primary either way.
- **Should the fit-report gate become a scripted check** (parse `M4K`/`Fmax`
  from the report) or stay a manual recorded step like the prior demo's fit?
  Default: recorded manual step (no CI synthesis lane), matching project
  practice.
