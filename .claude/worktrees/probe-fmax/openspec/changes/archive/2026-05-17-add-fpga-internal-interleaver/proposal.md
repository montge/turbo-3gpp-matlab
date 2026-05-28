## Why

The HDL turbo encoder is complete but takes the interleaved code block
externally — the QPP interleaver was the explicitly deferred seam. Adding a
board-neutral HDL QPP address generator closes that seam: it produces the
TS36.212 §5.1.3.2.3 permutation `pi(i) = (f1·i + f2·i²) mod K` that turns the
encoder into a standalone transmit datapath. It is deterministic, bounded, and
formally proven bijective for all 188 `K` (Lean), so it is fully golden-vector
verifiable like CRC8 and the turbo encoder.

## What Changes

- Add a board-neutral synthesizable VHDL QPP interleaver address generator
  under `hdl/rtl/` that streams `pi(0..K-1)` using the incremental recurrence
  (no wide multipliers): `pi_0 = 0`, `d_0 = (f1+f2) mod K`,
  `step = (2·f2) mod K`, `pi_{i+1} = (pi_i + d_i) mod K`,
  `d_{i+1} = (d_i + step) mod K` — every operand `< K`, one conditional
  subtract per step.
- The `(K, d_0, step)` constants are supplied externally (derived from the
  standardized `(K,f1,f2)` table); the 188-entry `K → (f1,f2)` ROM is the
  natural next follow-on, kept out of this bounded increment — mirroring how
  interleave was externalized from the encoder.
- Add a cocotb/GHDL lane `hdl/sim/internal_interleaver/` driven by golden
  vectors generated from the existing `internal_interleaver.m`
  (`hdl/vectors/internal_interleaver.csv`), checking the full permutation
  (including bijectivity) for a representative `K` set.
- No on-board work (sim-first); any future DE2 demo is an optional,
  hardware-gated follow-on. No screen.

## Capabilities

### New Capabilities

- `fpga-internal-interleaver`: HDL QPP address generator reproducing
  `internal_interleaver` `pi` bit-for-bit, its golden-vector simulation lane,
  and the external-constants seam to the turbo encoder.

### Modified Capabilities

<!-- None. Reuses fpga-hdl-path layout/methodology; the software
     internal-interleaver spec is unchanged (golden reference only). -->

## Impact

- New files under `hdl/rtl/` (QPP address generator), a vector generator using
  the existing `internal_interleaver.m`, and `hdl/sim/internal_interleaver/`
  cocotb tests.
- No changes to existing MATLAB/Octave sources, prior HDL cores, or prior
  specs; `internal_interleaver.m` is the golden reference only.
- Reuses the cross-platform HDL harness and golden-vector methodology.
- Explicit non-goals: no in-HW `(K,f1,f2)` ROM (separate follow-on), no
  decoder, no rate matching, no fixed-point, no board work.
