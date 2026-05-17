## 1. Golden-Vector Generators

- [ ] 1.1 `scripts/generate_hdl_rate_matching_vectors.m`: random `d` 3×D + params → `rate_matching(d,…)`; CSV `D,N_ref,I_LBRM,rv,E,d,e` (d column-major).
- [ ] 1.2 `scripts/generate_hdl_tx_chain_vectors.m`: random `c`/`K` + params → `e = rate_matching(turbo_encoder(c, internal_interleaver(0:K-1)),…)`; CSV `K,N_ref,I_LBRM,rv,E,c,e`.
- [ ] 1.3 Suites: `K∈{40,512,6144}` (D=K+4), `rv∈{0,1,2,3}`, `I_LBRM∈{0,1}` (constraining `N_ref`), `E` incl. wrap.
- [ ] 1.4 Generators use only existing helpers; no MATLAB/Octave sources changed.

## 2. rate_matching_top

- [ ] 2.1 `hdl/rtl/rate_matching_top.vhdl`: load 3×D `d` into async-read buffers; instantiate 3× `subblock_interleaver` (idx 0/1/2) + `circular_buffer`, unmodified.
- [ ] 2.2 FSM: LOAD_D → INIT (start 3 subblocks + circular_buffer w/ K_Pi/params) → STREAM (K_Pi cycles forming `v(:,k)` → circular_buffer load) → read → output `E`.
- [ ] 2.3 `K_Pi=((D+31)>>5)<<5` computed once; `v(r,k)=filler? (0,fill) : (d_r[idx_o_r],0)`. K-agnostic.

## 3. tx_chain_top

- [ ] 3.1 `hdl/rtl/tx_chain_top.vhdl`: instantiate `turbo_encode_top` + `rate_matching_top` unmodified.
- [ ] 3.2 FSM: start `turbo_encode_top` with `K` + stream `c`; its `out_valid` column stream feeds `rate_matching_top` d-load (D=K+4); chain output = rate_matching_top output.

## 4. Simulation Lanes

- [ ] 4.1 `hdl/sim/rate_matching_top/` (Makefile + cocotb): drive `d`+params, assert output == golden `e`.
- [ ] 4.2 `hdl/sim/tx_chain_top/` (Makefile + cocotb): drive `K`+`c`+params, assert output == golden `e`.
- [ ] 4.3 Artifacts covered by existing `.gitignore`.

## 5. Verification

- [ ] 5.1 `rate_matching_top` lane PASS for all representative cases.
- [ ] 5.2 `tx_chain_top` lane PASS for all representative cases.
- [ ] 5.3 Regression: all prior HDL lanes + Octave suite still pass.
- [ ] 5.4 Record pass results.

## 6. Validation and Docs

- [ ] 6.1 Add READMEs for both lanes (schema, regeneration, run, follow-ons).
- [ ] 6.2 `npx openspec validate add-fpga-rate-matching --strict` passes.
- [ ] 6.3 `npx openspec validate --all --strict` — no regression.

## 7. Follow-on Note (not required for completion)

- [ ] 7.1 Record divider-free / BRAM synthesis hardening of the TX chain and an optional DE2 demo as the explicit next follow-ons; out of scope here.
