# fpga-board-bringup Specification

## Purpose
Defines how a simulator-verified board-neutral HDL core is brought up on Altera
DE1/DE2 Cyclone II hardware: the pinned Quartus toolchain, board wrappers that
reuse the verified core unmodified, isolation of board constraints from the
portable core, exclusion of Quartus build artifacts from version control, and a
manual program-and-observe smoke validated against the MATLAB/Octave golden
model.

## Requirements
### Requirement: Board synthesis is pinned to a Cyclone II-capable toolchain

The system SHALL target Quartus II 13.0sp1 for DE1/DE2 synthesis and
programming, and SHALL document that Quartus II 13.1 cannot target the Cyclone
II devices on these boards.

#### Scenario: Toolchain and device are recorded before synthesis

- **WHEN** a board Quartus project is added
- **THEN** the project records the exact device string (`EP2C35F672C6N` for
  DE2, `EP2C20F484C7N`/`EP2C20F484C7` for DE1)
- **AND** board documentation states Quartus II 13.0sp1 is required and 13.1 is
  unsupported for Cyclone II

#### Scenario: Project compiles under the pinned toolchain

- **WHEN** the board project is compiled with Quartus II 13.0sp1
- **THEN** synthesis and fitting complete without unconstrained-device or
  unsupported-family errors

### Requirement: Board wrapper reuses the verified core unmodified

The system SHALL implement each board top entity as a wrapper that instantiates
the simulator-verified `crc8_parallel` core without editing or forking the
board-neutral HDL source.

#### Scenario: Core is instantiated, not copied

- **WHEN** a DE1 or DE2 wrapper is added
- **THEN** the wrapper instantiates `crc8_parallel` from the board-neutral HDL
  source path
- **AND** `hdl/rtl/crc8_parallel.vhdl` is unchanged by this work

#### Scenario: Board input drives the core

- **WHEN** board switches (and keys, if used) are set to an input value
- **THEN** that value is presented to the core `data_i` port
- **AND** the core `crc_o` output is shown on the board's LEDs and
  seven-segment displays

### Requirement: Board constraints are isolated from the portable core

The system SHALL keep Quartus project files, pin-location assignments, and
timing constraints under the board-specific path, separate from the
board-neutral core.

#### Scenario: Constraints live under the board path

- **WHEN** pin and timing constraints are added for a board
- **THEN** the `.qpf`, `.qsf`, and `.sdc` files reside under
  `hdl/boards/<board>/`
- **AND** no pin or board assignment appears in `hdl/rtl/`

### Requirement: Quartus build artifacts are not committed

The system SHALL exclude Quartus build, simulation, and programming outputs
from version control while keeping project and constraint sources tracked.

#### Scenario: Build outputs are ignored

- **WHEN** a board project is compiled
- **THEN** generated outputs (for example `db/`, `incremental_db/`,
  `output_files/`, `*.sof`, `*.pof`, `*.qws`) are ignored by git
- **AND** `git status` is clean after a compile aside from intentionally
  tracked sources

### Requirement: On-board behavior is validated against the software golden model

The system SHALL define a manual program-and-observe smoke test whose expected
output is taken from the same MATLAB/Octave-derived golden vectors used by the
HDL simulator.

#### Scenario: Programmed board matches the golden vector

- **WHEN** the board is programmed and a switch input from
  `hdl/vectors/crc8_parallel.csv` is applied
- **THEN** the CRC value shown on the board equals the expected CRC for that
  input row in the golden vectors

#### Scenario: Smoke procedure is documented

- **WHEN** the board bring-up is delivered
- **THEN** documentation describes the programming command, the chosen golden
  input(s), and the expected displayed CRC so the check is repeatable
