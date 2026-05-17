# fpga-subblock-interleaver Specification

## Purpose
Defines the board-neutral HDL sub-block interleaver address generator
(TS36.212 §5.1.4.1.1): a divider-free streaming core that, for an input length
`D` and index `∈ {0,1,2}`, emits the `K_Pi = 32·⌈D/32⌉` read pattern with a
per-element filler flag and the original `d`-index, bit-for-bit equal to the
software `subblock_interleaver`, plus its golden-vector simulation lane.

## Requirements
### Requirement: Board-neutral sub-block interleaver address generator

The system SHALL provide a synthesizable, board-neutral VHDL core under
`hdl/rtl/` that, for an input length `D` and a sub-block interleaver index in
`{0,1,2}`, streams the `K_Pi` read pattern of TS36.212 §5.1.4.1.1, where
`K_Pi = 32·⌈D/32⌉`, emitting for each position a `filler` flag and (when not
filler) the original `d`-index, bit-for-bit equal to
`subblock_interleaver(0:D-1, idx)`.

#### Scenario: Index 0/1 pattern matches the standard

- **WHEN** the core is run for `D` with index 0 (or 1)
- **THEN** the streamed pattern equals `subblock_interleaver(0:D-1, idx)` with
  filler positions flagged and the remaining positions giving the correct
  `d`-index

#### Scenario: Index 2 pattern matches the standard

- **WHEN** the core is run for `D` with index 2
- **THEN** the streamed pattern equals `subblock_interleaver(0:D-1, 2)`,
  including the `+1` and `mod K_Pi` of the §5.1.4.1.1 index-2 formula

#### Scenario: Output length and filler count

- **WHEN** the core streams a pattern for input length `D`
- **THEN** it emits exactly `K_Pi = 32·⌈D/32⌉` elements, of which exactly
  `K_Pi − D` are flagged filler

### Requirement: Divider-free, K-agnostic streaming interface

The core SHALL derive `R=⌈D/32⌉`, `K_Pi` and `N_D` from `D` using only
shifts/adds (no division), accept `D` and `idx` at run time via a start
handshake, and SHALL NOT require `D` fixed at synthesis time.

#### Scenario: Varied D without resynthesis

- **WHEN** different `D` (and indices) are run via the start handshake
- **THEN** each yields the correct pattern with no compile-time `D` parameter

#### Scenario: No division primitive

- **WHEN** the core advances
- **THEN** position decomposition uses nested counters (`k mod R`, `⌊k/R⌋`) and
  the index-2 reduction is a single conditional subtract of `K_Pi`

### Requirement: Simulation verified against the software golden model

The system SHALL provide a cocotb/GHDL lane driven by golden vectors generated
from the existing `subblock_interleaver` helper, comparing the full streamed
pattern (filler flags and `d`-indices) for a representative `D` set and
indices `{0,2}`, with a spot-check that index 1 equals index 0.

#### Scenario: Every element matches the golden vector

- **WHEN** the simulation runs a golden case `(D, idx)`
- **THEN** every streamed element's filler flag and `d`-index equal
  `subblock_interleaver(0:D-1, idx)`

#### Scenario: Representative coverage including filler

- **WHEN** the vector suite is generated
- **THEN** it spans encoder-relevant `D` plus at least one `D` that is not a
  multiple of 32 (exercising filler), for indices `{0,2}`

### Requirement: Additive board-neutral placement

The change SHALL place the core under `hdl/rtl/` and its simulation under
`hdl/sim/subblock_interleaver/`, reuse the existing cross-platform HDL flow,
keep generated artifacts out of version control, and modify no existing cores
or specs.

#### Scenario: No regression to existing work

- **WHEN** the change is delivered
- **THEN** prior HDL cores, the existing specs, and MATLAB/Octave sources are
  unchanged, and simulator build products are gitignored
