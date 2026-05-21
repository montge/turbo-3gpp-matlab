## ADDED Requirements

### Requirement: HDL simulation checks run as a development test lane

The test suite SHALL include a development-oriented HDL simulation lane for
GHDL/cocotb checks that can be run locally and, once tool availability is
settled, in CI.

#### Scenario: HDL test command reports missing tools clearly

- **WHEN** the HDL simulation command is run without required tools such as GHDL
  or cocotb
- **THEN** the command fails with an actionable message naming the missing tool
  and how to install or activate it

#### Scenario: HDL test lane is separate from MATLAB and proof lanes

- **WHEN** the existing MATLAB/Octave tests or proof checks run
- **THEN** HDL simulator build products are not required unless the HDL test
  command is explicitly invoked
