## Why

With the standalone HW turbo-encode datapath done, the next transmit-chain
stage is rate matching (TS36.212 §5.1.4.1). Its first, bounded, deterministic
piece is **sub-block interleaving** (§5.1.4.1.1) — a fixed address permutation
with no redundancy-version, circular-buffer, or limited-buffer state. Like the
QPP interleaver it is fully golden-vector verifiable against the existing
software model, so it is the right next increment; the circular buffer / rv /
LBRM / `E` selection (§5.1.4.1.2) is the explicit follow-on.

## What Changes

- Add a board-neutral synthesizable VHDL sub-block interleaver address
  generator under `hdl/rtl/` that streams, for an input length `D` and index
  `∈ {0,1,2}`, the `K_Pi` read pattern into the `NaN`-left-padded sequence,
  emitting a per-element `filler` flag plus the original `d`-index — bit-for-bit
  equal to `subblock_interleaver(0:D-1, idx)`.
- Derivation needs **no divider**: `R = ⌈D/32⌉` via a shift; nested counters
  `r0 = k mod R`, `c0 = ⌊k/R⌋`; a 32-entry constant `P` ROM; and for index 2 a
  single conditional subtract for the `mod K_Pi`. (Indices 0 and 1 are
  identical per the standard.)
- Add a cocotb/GHDL lane `hdl/sim/subblock_interleaver/` driven by golden
  vectors generated from the existing `subblock_interleaver.m`
  (`hdl/vectors/subblock_interleaver.csv`) for representative `D` and indices.
- No on-board work (sim-first). No screen.

## Capabilities

### New Capabilities

- `fpga-subblock-interleaver`: HDL sub-block interleaver address generator
  reproducing `subblock_interleaver` (indices 0/1/2, filler propagation) and
  its golden-vector simulation lane.

### Modified Capabilities

<!-- None. Reuses fpga-hdl-path layout/methodology; the software
     rate-matching/subblock_interleaver spec is unchanged (golden reference). -->

## Impact

- New files under `hdl/rtl/` (sub-block interleaver core), a vector generator
  using `subblock_interleaver.m`, and `hdl/sim/subblock_interleaver/` cocotb
  tests.
- No changes to MATLAB/Octave sources or prior specs/cores.
- Reuses the cross-platform HDL harness and golden-vector methodology.
- Explicit non-goals: no circular buffer, redundancy versions, LBRM, `E`/bit
  selection, decoder, fixed-point, or board work — the §5.1.4.1.2 circular
  buffer is the documented next follow-on.
