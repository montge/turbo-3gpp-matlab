## 1. Golden-Vector Generator

- [ ] 1.1 Add `scripts/generate_hdl_internal_interleaver_vectors.m`: for each supported `K`, get `pi = internal_interleaver(0:K-1)`, look up `(f1,f2)`, emit `d0=mod(f1+f2,K)` and `step=mod(2*f2,K)`.
- [ ] 1.2 Document the CSV schema (`K,d0,step,pi` with a fixed `pi` field layout that round-trips exactly).
- [ ] 1.3 Generate the suite for `K ∈ {40, 512, 6144}` (LTE min/mid/max); `K` validated by `internal_interleaver`.
- [ ] 1.4 Generator uses only the existing helper; no MATLAB/Octave sources changed.

## 2. QPP Address-Generator Core

- [ ] 2.1 Add `hdl/rtl/qpp_interleaver.vhdl` with the incremental recurrence (`pi_0=0`, `d_0=d0`, `pi_{i+1}=pi_i+d_i` cond-sub `K`, `d_{i+1}=d_i+step` cond-sub `K`).
- [ ] 2.2 Streaming, K-agnostic interface: `start` latches `K/d0/step`; `valid` + `index`/`last` stream `pi(0..K-1)`; widths sized for `K ≤ 6144`.
- [ ] 2.3 No `(K,f1,f2)` table in the core (constants are inputs).

## 3. Simulation Lane

- [ ] 3.1 Add `hdl/sim/internal_interleaver/` (Makefile + cocotb test) mirroring the established lanes.
- [ ] 3.2 Driver feeds `K/d0/step`, collects `K` streamed indices.
- [ ] 3.3 Assert every index equals the golden `pi` and the sequence is a permutation of `0..K-1`.
- [ ] 3.4 Simulator artifacts covered by existing `.gitignore` (no new patterns expected).

## 4. Verification

- [ ] 4.1 Run the new lane; confirm all representative `K` pass (incl. K=6144).
- [ ] 4.2 Regression: existing turbo + CRC HDL lanes and the Octave suite still pass.
- [ ] 4.3 Record pass results (K set, counts) in the change.

## 5. Validation and Docs

- [ ] 5.1 Add a short `hdl/sim/internal_interleaver/README.md` (schema, regeneration, run).
- [ ] 5.2 `npx openspec validate add-fpga-internal-interleaver --strict` passes.
- [ ] 5.3 `npx openspec validate --all --strict` — no regression.

## 6. Follow-on Note (not required for completion)

- [ ] 6.1 Record the `K→(f1,f2)` ROM + optional DE2 demo as the explicit next follow-on; out of scope here.
