## ADDED Requirements

### Requirement: HDL lanes run as a CI gate

The CI workflow SHALL include a job that installs GHDL, GNU make, Python and
the pinned cocotb, and runs every `hdl/sim/*/` cocotb/GHDL lane against the
committed golden-vector CSVs on each pull request and push, failing the job if
any lane does not pass.

#### Scenario: All HDL lanes pass

- **WHEN** the CI HDL job runs on a commit whose HDL lanes are all bit-exact
  to their committed golden vectors
- **THEN** the job passes

#### Scenario: An HDL regression fails the gate

- **WHEN** a change makes any `hdl/sim/*/` lane mismatch its golden vector
- **THEN** the CI HDL job fails (the regression is gated, not silent)

#### Scenario: No model toolchain required

- **WHEN** the CI HDL job runs
- **THEN** it consumes the committed CSV vectors and requires no
  Octave/MATLAB (independent of the model-regeneration path)

### Requirement: Single reusable lane runner

The system SHALL provide `scripts/run_all_hdl_lanes.sh` that discovers and
runs every `hdl/sim/*/` lane, is used by both the CI job and local
developers, and automatically picks up newly added lanes.

#### Scenario: New lane is covered automatically

- **WHEN** a new `hdl/sim/<lane>/` with a Makefile is added
- **THEN** the runner (and therefore CI) executes it with no runner change

#### Scenario: Additive only

- **WHEN** this change is delivered
- **THEN** existing CI jobs, RTL, golden vectors, and other specs are
  unchanged
