## Context

`internal_interleaver.m` contains the authoritative 188-row TS36.212 Table
5.1.3-3 (`K,f1,f2`). `qpp_interleaver` already streams `pi` from
`(K,d0,step)`; `turbo_encoder` already produces `3×(K+4)` from natural +
interleaved bit streams. Both are sim-verified and unmodified here. This change
adds the table in hardware and wires the cores into a standalone encode path.

## Goals / Non-Goals

**Goals:**

- A generated, standard-faithful `K→(d0,step)` ROM + lookup.
- `turbo_encode_top` producing `d` from `(K, code block)` only, reusing the
  three verified cores unmodified.
- End-to-end sim verification against the existing software golden model.

**Non-Goals:**

- No decoder, rate matching, fixed-point, or board work. No screen.
- Not throughput-optimized: a simple async-read block buffer and a scanning
  ROM lookup are used (correctness-first; BRAM/dual-port + pipelining is a
  documented follow-on).

## Decisions

1. **Generate the ROM package; never hand-type it.** An Octave generator reads
   `internal_interleaver.m`'s `parameters` table, computes `d0=mod(f1+f2,K)`
   and `step=mod(2*f2,K)` per row, and emits a committed
   `hdl/rtl/qpp_rom_pkg.vhd` constant array (188 entries). Single-sourced from
   the standard → cannot drift; regenerating is deterministic.

2. **Scan-based lookup, not address-by-K.** The 188 `K` are non-uniformly
   spaced (steps 8/16/32/64), so direct addressing would need a sparse
   6145-deep ROM or piecewise index math. A sequential scan over the 188-entry
   ROM comparing the input `K` (≤188 cycles, < the `K`≥40 encode time) yields
   `(d0,step)` + a `supported` flag. Simple, exact, cheap.

3. **`turbo_encode_top` reuses the three cores unmodified.** Dataflow:
   - **Load:** stream the `K` code-block bits into a block buffer
     `buf(0..K-1)`; latch `K`; `qpp_rom` looks up `(d0,step)`.
   - **Encode:** start `qpp_interleaver`; for data step `i=0..K-1` it yields
     `pi(i)`. Read `buf(i)` → `c_bit` and `buf(pi(i))` → `cprime_bit`; drive
     `turbo_encoder` (one data step/cycle). Then 3 termination steps, then 4
     emit cycles — exactly `turbo_encoder`'s existing protocol.
   - The block buffer has one write port (load) and two async read ports
     (`i` and `pi(i)`); inferred as distributed RAM. Async read keeps the
     `pi(i)`→`buf`→`turbo_encoder` path single-cycle, matching the verified
     core timings.

4. **Reuse `hdl/vectors/turbo_encoder.csv` for the end-to-end lane.** It
   already has `K`, `c`, and expected `d`. The top computes `c_prime`
   internally (ROM+interleaver+buffer), so the test drives only `K`+`c` and
   checks `d` — proving the integration without new vectors.

5. **Separate ROM unit lane.** A generated `qpp_rom` golden list (every
   supported `K`→`d0/step`, plus a couple of unsupported `K`→`supported=0`)
   is checked independently for fast, isolated failure.

## Risks / Trade-offs

- **Orchestration FSM aligning `pi(i)`, buffer reads, and the encoder
  protocol is the only genuinely new logic** → the three sub-cores are already
  proven; the end-to-end golden-vector lane (same `d` oracle as the encoder)
  catches any alignment error immediately.
- **Async-read buffer / scan lookup are not throughput-optimal** → explicit,
  documented v1 boundary; BRAM/dual-port + pipelined lookup is the named
  follow-on. Correctness is unaffected.
- **ROM transcription risk** → eliminated by generating the package from the
  `.m` table; the ROM unit lane re-checks every entry vs `internal_interleaver`.

## Open Questions

- ROM package array style (record vs parallel constant vectors) — settle in
  the generator; the unit lane is the oracle.
- Whether to also stream the natural-order `c` from the buffer or pass the
  input through directly — buffer-read for both keeps timing uniform; confirm
  during implementation.
