## Context

The `turbo-encoder` capability (TS36.212 §5.1.3.2) is fully specified and
software-verified: a recursive-systematic constituent encoder (3 memory
elements, generator `[1,1,0,1]`, feedback `[1,0,1,1]`, 3-step trellis
termination) run over the natural and interleaved code-block orders, producing
a `3 × (K+4)` matrix with a specific termination-column layout. The software
entry point is `turbo_encoder(c, pi)` — it **receives** the interleaver pattern
`pi`; QPP generation lives in the separate `internal-interleaver` capability.

The FPGA path (`fpga-hdl-path`, `fpga-board-bringup`) is proven: board-neutral
cores under `hdl/rtl/`, cocotb/GHDL golden-vector simulation (now Windows-
capable via `scripts/run_hdl_tests.sh`), and an optional DE2 smoke.

## Goals / Non-Goals

**Goals:**

- A board-neutral synthesizable VHDL constituent encoder and turbo-encoder core
  that reproduce `turbo_encoder(c, pi)` bit-for-bit.
- Exhaustive simulation verification against golden vectors generated from the
  existing MATLAB/Octave `turbo_encoder` + `internal-interleaver` helpers.
- Reuse the established `hdl/` layout, harness, and golden-vector methodology.
- Keep the core K-agnostic and bounded.

**Non-Goals:**

- No turbo decoder, rate matching, or code-block segmentation.
- No fixed-point arithmetic (this datapath is purely bit-level).
- No in-hardware QPP / interleaver address generation (separate future block).
- No filler/`NaN` handling — v1 encodes concrete full code blocks.
- No required board work; the DE2 smoke is optional and hardware-gated.
- No screen/VGA.

## Decisions

1. **Streaming interface, not parallel.** LTE `K` ranges 40–6144, so a
   CRC-style parallel `data_i(K-1:0)` does not scale. The core consumes input
   bit-serially with a simple `start`/`valid`/`last` handshake and emits the
   output as a stream of `K+4` column triples `(d0,d1,d2)` with `valid`. One
   bit/column per clock; synchronous design with the 3-bit shift-register
   state.

2. **The testbench supplies both natural and interleaved streams (`c` and
   `c_prime`); the core does not interleave.** This mirrors the software
   `turbo_encoder(c, pi)` contract (pattern supplied externally), keeps the
   core K-agnostic with no large reorder RAM, and makes the golden-vector
   mapping exact. The interleave-buffer / in-hardware QPP is explicitly a
   follow-on block (it was already named as a separate candidate in
   `add-fpga-hdl-path`).
   *Alternative considered:* an internal block-RAM that buffers `c` and reads
   it back in `pi` order. Rejected for v1 — it pulls memory scheduling and the
   188-entry QPP `f1/f2` table into scope and makes the core K-bounded; defer
   it as its own change.

3. **Reusable constituent-encoder component.** Combinational next-state/output
   logic plus three flip-flops `(s1,s2,s3)`, implementing the spec recurrences
   `s1' = c⊕s2⊕s3`, `x=c`, `z=s1'⊕s1⊕s3`, and the 3 termination steps with the
   feedback forced to zero (`s1'=0`, `x=s2⊕s3`). Instantiated twice (natural and
   interleaved). Each emits `(x,z)` of length `K+3`.

4. **Dedicated output-assembly stage.** The `3 × (K+4)` layout is produced by a
   small stage that streams systematic/parity columns for `k=0..K-1`
   (`[x; z; z']`) and then emits the four termination columns exactly per the
   spec: `[x(K+1);z(K+1);x(K+2)]`, `[z(K+2);x(K+3);z(K+3)]`,
   `[x'(K+1);z'(K+1);x'(K+2)]`, `[z'(K+2);x'(K+3);z'(K+3)]`. The six tail
   `(x,z)` pairs per constituent encoder are buffered to assemble these.

5. **Golden vectors carry `c`, `c_prime`, and the expected `d` matrix.** The
   generator calls the existing public MATLAB/Octave helpers to compute `pi`
   (internal-interleaver) and `d = turbo_encoder(c, pi)`, and writes
   `hdl/vectors/turbo_encoder*.csv` with `K`, the `c` bits, the derived
   `c_prime = c(pi)` bits, and the flattened `3×(K+4)` `d`. The HDL/testbench
   need no interleaver logic.

6. **Representative `K` set, not all 188 sizes.** Because the core streams and
   is K-generic (K-dependence lives only in the deferred QPP block), a small
   set spanning the extremes and a mid value (e.g., `K ∈ {40, 512, 6144}`)
   plus a few random blocks per `K` gives high confidence. Final list pinned in
   tasks.

7. **Reuse the existing harness.** Add `hdl/sim/turbo_encoder/` with a cocotb
   test and Makefile mirroring `hdl/sim/crc8/`; it is picked up by the existing
   cross-platform `scripts/run_hdl_tests.sh` flow. Waveform artifacts stay
   gitignored.

## Risks / Trade-offs

- **Streaming control logic is more complex than the combinational CRC** →
  keep the handshake minimal (`start`/`valid`/`last` in, `valid` + column out)
  and cover it with directed + random cocotb cases.
- **Termination-column mapping is fiddly** → transcribe directly from the spec
  and assert every tail column bit in simulation (not just the systematic body).
- **Core is not a standalone encoder without the interleaver block** →
  explicitly a documented v1 boundary; the reorder-RAM/QPP hardware is the
  next planned change and the seam (external `c_prime`) is defined now.
- **cocotb streaming tests are heavier than CRC's single vector** → factor a
  small driver/monitor coroutine; reuse across `K` cases.
- **No filler handling** → v1 golden vectors exclude `NaN`/filler; this is
  noted as a scope boundary, not a silent gap.

## Open Questions

- Final `K` set and number of random blocks per `K` for the vector suite
  (proposed `{40, 512, 6144}` + 4 random each) — pin in tasks.
- CSV column schema details (bit packing / ordering) — settle when writing the
  generator; must round-trip exactly against `turbo_encoder(c, pi)`.
