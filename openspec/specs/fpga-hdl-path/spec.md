# fpga-hdl-path Specification

## Purpose
Defines the repository's FPGA/HDL development path: the board-neutral VHDL
source layout, the cross-platform GHDL/cocotb local simulation lane, the use of
the MATLAB/Octave implementation as the golden-vector source for HDL tests, and
the staged progression from simulator-verified cores to Altera DE1/DE2 board
bring-up. This spec is the source-of-truth contract that downstream FPGA
capability specs (CRC, subblock interleaver, circular buffer, internal
interleaver, QPP ROM, rate matching, turbo encoder, board bring-up) layer on
top of.
## Requirements
### Requirement: HDL sources are organized for simulator and board reuse

The system SHALL provide a hardware-development layout that separates
board-neutral synthesizable HDL cores from simulator testbenches, generated
golden vectors, and board-specific wrappers or constraints.

#### Scenario: Portable core layout

- **WHEN** a new HDL implementation block is added
- **THEN** its synthesizable source is placed in a board-neutral HDL source path
- **AND** simulator-only testbench code and generated artifacts are not required
  by the synthesizable core

#### Scenario: Board-specific wrapper isolation

- **WHEN** a DE1 or DE2 wrapper is added for an HDL core
- **THEN** board pin assignments, clocks, switches, LEDs, and Quartus project
  files are kept separate from the portable core implementation

### Requirement: Mac-local HDL simulation is reproducible

The system SHALL provide a local simulation workflow that uses GHDL and cocotb to
compile HDL, run tests, and optionally emit a waveform file suitable for GTKWave.

#### Scenario: GHDL smoke simulation passes

- **WHEN** the HDL smoke simulation command is run on a Mac with GHDL available
- **THEN** GHDL analyzes, elaborates, and runs the smoke test without assertion
  failures

#### Scenario: Waveform artifact is generated on request

- **WHEN** the HDL smoke simulation is run with waveform output enabled
- **THEN** a VCD, GHW, or FST waveform file is created in an ignored simulator
  artifact path

### Requirement: HDL behavior is checked against the software golden model

The system SHALL compare each implemented HDL block against golden vectors
generated from the existing MATLAB/Octave implementation or from checked-in
fixtures produced by that implementation.

#### Scenario: Golden vector comparison

- **WHEN** a cocotb test drives an HDL block with a golden input vector
- **THEN** the HDL output matches the corresponding expected vector from the
  MATLAB/Octave golden model

#### Scenario: First block stays bounded

- **WHEN** the first HDL implementation block is selected
- **THEN** it is limited to CRC calculation or subblock interleaver address/data
  ordering before full turbo encoder or decoder hardware is attempted

### Requirement: DE1/DE2 bring-up follows simulator verification

The system SHALL treat Altera DE1/DE2 board support as a follow-on milestone
after the relevant HDL core has passing simulator tests.

#### Scenario: Board target is documented before synthesis

- **WHEN** a board-specific implementation task starts
- **THEN** the exact board variant, FPGA device, Quartus version, clocking
  assumptions, and observable test interface are documented

#### Scenario: Board smoke test reuses a verified core

- **WHEN** a DE1 or DE2 board smoke test is created
- **THEN** it instantiates a simulator-verified HDL core rather than forking the
  core behavior into board-specific logic

