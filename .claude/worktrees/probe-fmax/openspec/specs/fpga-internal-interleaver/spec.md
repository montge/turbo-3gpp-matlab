# fpga-internal-interleaver Specification

## Purpose
Defines the board-neutral HDL implementation of the TS36.212 §5.1.3.2.3 QPP
internal interleaver: a synthesizable address generator that streams
`pi(i) = (f1·i + f2·i²) mod K` bit-for-bit equal to the software
`internal_interleaver`, using an add-only incremental recurrence with
externally supplied pre-reduced constants, plus its golden-vector simulation
lane (including a bijectivity guard).

## Requirements
### Requirement: Board-neutral QPP interleaver address generator

The system SHALL provide a synthesizable, board-neutral VHDL core under
`hdl/rtl/` that produces the TS36.212 §5.1.3.2.3 QPP permutation
`pi(i) = (f1·i + f2·i²) mod K` for `i = 0..K-1`, using an add-only incremental
recurrence with all internal state strictly less than `K`.

#### Scenario: Permutation matches the standard

- **WHEN** the core is run for a supported `K` with constants `d0=(f1+f2) mod K`
  and `step=(2·f2) mod K`
- **THEN** the streamed sequence equals `mod(f1·i + f2·i², K)` for
  `i = 0..K-1`

#### Scenario: Output is a bijection

- **WHEN** the core streams `pi(0..K-1)` for any supported `K`
- **THEN** the multiset of emitted values equals `{0,1,…,K-1}`

### Requirement: K-agnostic streaming interface with externally supplied constants

The core SHALL accept `K` and the pre-reduced constants `d0` and `step` at
run time via a start handshake and SHALL NOT require `K` to be fixed at
synthesis time; it SHALL NOT contain the `(K,f1,f2)` table.

#### Scenario: Varied block sizes without resynthesis

- **WHEN** different supported `K` values (with their constants) are run
- **THEN** each produces the correct `pi` with no compile-time `K` parameter

#### Scenario: Reduction is a single conditional subtract

- **WHEN** the recurrence advances
- **THEN** each new value is reduced modulo `K` by at most one subtraction of
  `K` (operands are `< K`, sums `< 2K`)

### Requirement: Simulation verified against the software golden model

The system SHALL provide a cocotb/GHDL lane driven by golden vectors generated
from the existing `internal_interleaver` helper, comparing the full streamed
permutation and asserting bijectivity, for a representative `K` set including
the LTE minimum and maximum.

#### Scenario: Every index matches the golden vector

- **WHEN** the simulation runs a golden case for `K`
- **THEN** every streamed `pi(i)` equals the expected value from
  `internal_interleaver(0:K-1)` and the sequence is a permutation of
  `0..K-1`

#### Scenario: K set cannot drift from the standard

- **WHEN** the vector suite is generated
- **THEN** every `K` is one that `internal_interleaver` accepts (it errors on
  unsupported sizes), spanning the LTE minimum, a mid value, and the maximum

### Requirement: Additive board-neutral placement

The change SHALL place the new core under `hdl/rtl/` and its simulation under
`hdl/sim/internal_interleaver/`, reuse the existing cross-platform HDL test
flow, keep generated artifacts out of version control, and modify no existing
cores or specs.

#### Scenario: No regression to existing work

- **WHEN** the change is delivered
- **THEN** prior HDL cores, the existing specs, and MATLAB/Octave sources are
  unchanged, and simulator build products are gitignored
