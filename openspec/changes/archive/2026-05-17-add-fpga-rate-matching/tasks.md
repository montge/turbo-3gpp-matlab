## 1. Golden-Vector Generators

- [x] 1.1 `scripts/generate_hdl_rate_matching_vectors.m`: random `d` 3×D + params → `rate_matching(d,…)`; CSV `D,N_ref,I_LBRM,rv,E,d,e` (d column-major).
- [x] 1.2 `scripts/generate_hdl_tx_chain_vectors.m`: random `c`/`K` + params → `e = rate_matching(turbo_encoder(c, internal_interleaver(0:K-1)),…)`; CSV `K,N_ref,I_LBRM,rv,E,c,e`.
- [x] 1.3 Suites: `K∈{40,512,6144}` (D=K+4), `rv∈{0,2,3}`, `I_LBRM∈{0,1}` (constraining `N_ref`), `E` incl. wrap. Sanity-checked (n_d=3·D, len e=E).
- [x] 1.4 Generators use only existing helpers; no MATLAB/Octave sources changed.

## 2. rate_matching_top

- [x] 2.1 `hdl/rtl/rate_matching_top.vhdl`: 3×D async-read input buffers; 3× `subblock_interleaver` (idx 0/1/2) + `circular_buffer`, unmodified.
- [x] 2.2 FSM: LOAD_D → INIT (start 3 subblocks + circular_buffer w/ K_Pi/params) → STREAM (K_Pi cycles forming `v(:,k)`) → read → output `E`.
- [x] 2.3 `K_Pi=((D+31)>>5)<<5` computed once; `v(r,k)=filler? (0,fill):(d_r[idx_o_r],0)`. K-agnostic.

## 3. tx_chain_top

- [x] 3.1 `hdl/rtl/tx_chain_top.vhdl`: `turbo_encode_top` + `rate_matching_top`, unmodified.
- [x] 3.2 FSM: start `turbo_encode_top` (K) + stream `c`; its `out_valid` column stream feeds `rate_matching_top` d-load (D=K+4); chain output = rate_matching_top output.

## 4. Simulation Lanes

- [x] 4.1 `hdl/sim/rate_matching_top/` — drive `d`+params, assert output == golden `e`. PASS (8 cases).
- [x] 4.2 `hdl/sim/tx_chain_top/` — drive `K`+`c`+params, assert output == golden `e`. PASS (7 cases).
- [x] 4.3 Artifacts covered by existing `.gitignore`.

## 5. Verification

- [x] 5.1 `rate_matching_top` lane PASS — D∈{44,516,6148}, rv∈{0,2,3}, LBRM∈{0,1} bit-exact vs `rate_matching.m`.
- [x] 5.2 `tx_chain_top` lane PASS — K∈{40,512,6144}, rv∈{0,2,3}, LBRM∈{0,1} bit-exact vs the composed software chain.
- [x] 5.3 No regression: all 8 prior HDL lanes PASS; Octave `OK (passed=102)`.
- [x] 5.4 Recorded here: rate_matching 8/8 + tx_chain 7/7 bit-exact; regression green.

## 6. Validation and Docs

- [x] 6.1 `hdl/sim/rate_matching_top/README.md` and `hdl/sim/tx_chain_top/README.md` added (schema, regeneration, run, follow-ons).
- [x] 6.2 `npx openspec validate add-fpga-rate-matching --strict` — passes.
- [x] 6.3 `npx openspec validate --all --strict` — no regression.

## 7. Follow-on Note (not required for completion)

- [x] 7.1 Divider-free / BRAM synthesis hardening of the TX chain and an optional DE2 demo recorded as the explicit next follow-ons; out of scope here.
