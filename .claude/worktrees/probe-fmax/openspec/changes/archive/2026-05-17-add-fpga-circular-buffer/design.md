## Context

`circular_buffer.m` (TS36.212 §5.1.4.1.2): `K_Pi = cols(v)` (mult. of 32),
`R_TC = K_Pi/32`, `K_w = 3·K_Pi`. Build `w`: `w[k]=v(1,k)` for `k∈[0,K_Pi)`;
`w[K_Pi+2k]=v(2,k)`, `w[K_Pi+2k+1]=v(3,k)`. `N_cb = K_w` if `I_LBRM=0` else
`min(N_ref,K_w)`. `k_0 = R_TC·(2·ceil(N_cb/(8·R_TC))·rv_idx + 2)`. Then read
`E` non-`NaN` values from `w` at `mod(k_0+j,N_cb)` advancing `j`.

## Goals / Non-Goals

**Goals:** a board-neutral core streaming `E` rate-matched bits bit-exact vs
`circular_buffer.m`; golden-vector sim across `K_Pi`/`rv`/`E`/LBRM; reuse the
established layout/harness.

**Non-Goals:** no `rate_matching` integration (next follow-on), no
divider-free synthesis hardening (follow-on), no decoder/fixed-point/board, no
screen.

## Decisions

1. **Stream `v` in column order; build `w` during load.** For `k=0..K_Pi-1`
   present `(v1,v2,v3)` each with a `filler` flag; write `w[k]=v1`,
   `w[K_Pi+2k]=v2`, `w[K_Pi+2k+1]=v3` into bit + filler arrays
   (`K_w ≤ 3·6176 = 18528`). Async-read arrays (sim-first; BRAM hardening is a
   follow-on, as for `turbo_encode_top`).

2. **Integer arithmetic for `N_cb`/`k_0`/read (sim-first).** `R_TC=K_Pi>>5`,
   `K_w=3·K_Pi`; `ceil(N_cb/(8·R_TC)) = (N_cb + 8·R_TC − 1)/(8·R_TC)`; `k_0`
   and `mod(k_0+j,N_cb)` use VHDL integer `/`,`mod` (GHDL exact). A
   divider-free reformulation (the quotient is ≤ 12) is a documented synthesis
   follow-on — consistent with the project's sim-first-then-harden discipline.

3. **Filler-skipping circular read.** `j` from 0: `pos = mod(k_0+j, N_cb)`;
   if `w_fill[pos]=0` emit `w_bit[pos]` and `k++`; always `j++`; until `k=E`.
   Streamed output with `valid`/`last`; variable cycle count.

4. **K-agnostic streaming interface.** `start` latches
   `K_Pi/N_ref/I_LBRM/rv_idx/E`; load phase consumes `K_Pi` `v` columns; read
   phase streams `E` bits.

5. **Golden vectors built realistically.** The generator forms a realistic `v`
   (sub-block-interleaved random encoded-shaped `d`, so filler is the genuine
   left-pad pattern), then `e = circular_buffer(v, …)`. CSV carries `K_Pi`,
   params, the flattened `v` (bit, `-1`=filler), and the `E`-bit `e`. The HDL
   gets `v`+params and must reproduce `e`.

## Risks / Trade-offs

- **w-construction index mapping (rows 2/3 interleave) is easy to misorder** →
  transcribed directly from `circular_buffer.m` and proven by exact
  golden-vector simulation.
- **Read loop can iterate well past `E` (filler skips, wrap)** → bounded in
  practice (real `v` has few filler); test data is realistic so termination is
  guaranteed; a safety iteration cap is included.
- **Integer `/`,`mod` are not directly synthesizable-efficient** → explicit,
  documented v1 boundary; divider-free hardening is the named follow-on.
- **`K_w` array size (~18.5k)** → fine for GHDL sim; BRAM mapping is the
  hardening follow-on.

## Open Questions

- Param coverage set (`K_Pi` from `D∈{44,516,6148}`; `rv_idx∈{0,1,2,3}`;
  `I_LBRM∈{0,1}` with an `N_ref` that actually constrains; a couple of `E`
  including `E>K_w` wrap) — pin in tasks.
- CSV layout for `v` (per-column triples vs row-major) — settle in the
  generator; the sim comparison is the oracle.
