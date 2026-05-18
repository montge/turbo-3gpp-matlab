## Why

The sub-block interleave stage of rate matching is done in HDL. The remaining
piece is the §5.1.4.1.2 **circular buffer** — bit collection, the
redundancy-version/LBRM start offset, and the filler-skipping circular read
that yields the rate-matched length-`E` output. It is deterministic and fully
golden-vector verifiable against the existing `circular_buffer.m`. Verifying it
standalone (the most intricate deterministic block) before integrating mirrors
how the QPP interleaver was verified before the ROM integration.

## What Changes

- Add a board-neutral synthesizable VHDL `circular_buffer` core under
  `hdl/rtl/` that, given the 3×`K_Pi` sub-block-interleaved matrix `v` (each
  element a bit + `filler` flag) and `(N_ref, I_LBRM, rv_idx, E)`, builds the
  length-`K_w = 3·K_Pi` buffer `w` (row 1, then rows 2/3 interleaved), computes
  `N_cb` and the start offset `k_0`, and streams `E` non-filler bits read
  circularly from `w` starting at `k_0` — bit-for-bit equal to
  `circular_buffer(v, N_ref, I_LBRM, rv_idx, E)`.
- v1 is **sim-first / correctness-first**: integer arithmetic (incl. the
  `ceil`/`mod` in `k_0` and the modular read) is used directly (GHDL exact). A
  divider-free synthesis reformulation and the full `rate_matching`
  integration (3× verified `subblock_interleaver` + this core) are documented
  follow-ons.
- Add a cocotb/GHDL lane `hdl/sim/circular_buffer/` driven by golden vectors
  from `circular_buffer.m` over representative `K_Pi`, `rv_idx`, `E`, and both
  LBRM modes.

## Capabilities

### New Capabilities

- `fpga-circular-buffer`: HDL circular-buffer core reproducing
  `circular_buffer` (w construction, `k_0`/rv/LBRM, NaN-skip circular read)
  and its golden-vector simulation lane.

### Modified Capabilities

<!-- None. Reuses fpga-hdl-path layout/methodology; the software
     rate-matching/circular_buffer spec is unchanged (golden reference). -->

## Impact

- New files under `hdl/rtl/` (circular buffer core), a vector generator using
  `circular_buffer.m`, and `hdl/sim/circular_buffer/` cocotb tests.
- No changes to MATLAB/Octave sources or prior specs/cores.
- Reuses the cross-platform HDL harness and golden-vector methodology.
- Explicit non-goals: no `rate_matching` integration yet (next follow-on), no
  divider-free synthesis hardening (follow-on), no decoder, no fixed-point, no
  board work.
