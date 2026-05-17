## 1. Golden-Vector Generator

- [x] 1.1 `scripts/generate_hdl_circular_buffer_vectors.m`: builds realistic `v` (3× `subblock_interleaver` of random encoder-shaped `d`), calls `circular_buffer(v, N_ref, I_LBRM, rv_idx, E)`.
- [x] 1.2 CSV `K_Pi,N_ref,I_LBRM,rv_idx,E,v,e` (v column-major, `-1`=filler; e = E-bit string) documented in generator + README.
- [x] 1.3 Suite: `K_Pi∈{64,544,6176}` (from D∈{44,516,6148}), `rv_idx∈{0,1,2,3}`, `I_LBRM∈{0,1}` (N_ref=800 constrains), `E` incl. wrap. Sanity-checked (n_v=3·K_Pi, len e=E).
- [x] 1.4 Uses only existing helpers; no MATLAB/Octave sources changed.

## 2. Circular-Buffer Core

- [x] 2.1 `hdl/rtl/circular_buffer.vhdl`: loads `K_Pi` `v` columns, builds `w` (`w[k]=v1`, `w[K_Pi+2k]=v2`, `w[K_Pi+2k+1]=v3`) into bit+filler arrays (`K_w≤18528`).
- [x] 2.2 `R_TC=K_Pi/32`, `K_w=3·K_Pi`, `N_cb` (LBRM min), `k_0=R_TC·(2·ceil(N_cb/(8·R_TC))·rv+2)` (integer arith, sim-first). All params latched at `start`.
- [x] 2.3 Filler-skipping circular read `pos=mod(k0+j,N_cb)`; `valid`/`last`; safety iteration cap (`jj>8·KW_MAX`).
- [x] 2.4 K-agnostic streaming interface (`start` latches all params).

## 3. Simulation Lane

- [x] 3.1 `hdl/sim/circular_buffer/` (Makefile + cocotb) mirrors established lanes.
- [x] 3.2 Driver latches params, loads `v` columns, collects `E` output bits.
- [x] 3.3 Asserts streamed output equals golden `e` for every case.
- [x] 3.4 Artifacts covered by existing `.gitignore`.

## 4. Verification

- [x] 4.1 Lane PASS for all 10 cases (K_Pi/rv/LBRM/E incl. wrap; `TESTS=1 PASS=1 FAIL=0`).
- [x] 4.2 No regression: crc8/turbo_encoder/internal_interleaver/qpp_rom/turbo_encode_top/subblock_interleaver HDL lanes PASS; Octave `OK (passed=102)`.
- [x] 4.3 Recorded here: 10 cases bit-exact incl. LBRM + wrap; regression green.

## 5. Validation and Docs

- [x] 5.1 `hdl/sim/circular_buffer/README.md` documents schema, regeneration, run, design + follow-ons.
- [x] 5.2 `npx openspec validate add-fpga-circular-buffer --strict` — passes.
- [x] 5.3 `npx openspec validate --all --strict` — no regression.

## 6. Follow-on Note (not required for completion)

- [x] 6.1 Full `rate_matching` integration (3× `subblock_interleaver` + this core; then chain with `turbo_encode_top`) and divider-free / BRAM synthesis hardening recorded as the explicit next follow-ons; out of scope here.
