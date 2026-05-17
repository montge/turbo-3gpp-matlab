## 1. Golden-Vector Generator

- [ ] 1.1 Add `scripts/generate_hdl_circular_buffer_vectors.m`: build a realistic `v` (sub-block-interleaved random encoder-shaped `d`), call `circular_buffer(v, N_ref, I_LBRM, rv_idx, E)`.
- [ ] 1.2 CSV schema documented: `K_Pi,N_ref,I_LBRM,rv_idx,E,v,e` with `v` flattened column-major as `(bit | -1 filler)`, `e` an `E`-bit string.
- [ ] 1.3 Suite: `K_Pi` from `D∈{44,516,6148}`; `rv_idx∈{0,1,2,3}`; `I_LBRM∈{0,1}` (with a constraining `N_ref`); `E` incl. one forcing wrap.
- [ ] 1.4 Uses only existing helpers; no MATLAB/Octave sources changed.

## 2. Circular-Buffer Core

- [ ] 2.1 Add `hdl/rtl/circular_buffer.vhdl`: load `K_Pi` `v` columns, build `w` (`w[k]=v1`, `w[K_Pi+2k]=v2`, `w[K_Pi+2k+1]=v3`) into bit+filler arrays (`K_w≤18528`).
- [ ] 2.2 Compute `R_TC=K_Pi>>5`, `K_w=3·K_Pi`, `N_cb` (LBRM), `k_0=R_TC·(2·ceil(N_cb/(8·R_TC))·rv_idx+2)` (integer arith, sim-first).
- [ ] 2.3 Filler-skipping circular read: `pos=mod(k_0+j,N_cb)`, skip filler, emit `E` bits; `valid`/`last`; safety iteration cap.
- [ ] 2.4 K-agnostic streaming interface (`start` latches params).

## 3. Simulation Lane

- [ ] 3.1 Add `hdl/sim/circular_buffer/` (Makefile + cocotb) mirroring established lanes.
- [ ] 3.2 Driver latches params, loads `v` columns, collects `E` output bits.
- [ ] 3.3 Assert streamed output equals golden `e` for every case.
- [ ] 3.4 Artifacts covered by existing `.gitignore`.

## 4. Verification

- [ ] 4.1 Lane PASS for all representative cases (K_Pi/rv/LBRM/E incl. wrap).
- [ ] 4.2 Regression: all prior HDL lanes + Octave suite still pass.
- [ ] 4.3 Record pass results.

## 5. Validation and Docs

- [ ] 5.1 Add `hdl/sim/circular_buffer/README.md` (schema, regeneration, run, design + follow-ons).
- [ ] 5.2 `npx openspec validate add-fpga-circular-buffer --strict` passes.
- [ ] 5.3 `npx openspec validate --all --strict` — no regression.

## 6. Follow-on Note (not required for completion)

- [ ] 6.1 Record the full `rate_matching` integration (3× verified `subblock_interleaver` + this core; then chain with `turbo_encode_top`) and the divider-free synthesis hardening as the explicit next follow-ons; out of scope here.
