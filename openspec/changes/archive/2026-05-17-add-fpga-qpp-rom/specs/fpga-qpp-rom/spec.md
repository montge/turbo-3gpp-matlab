## ADDED Requirements

### Requirement: Generated standardized QPP parameter ROM

The system SHALL provide a VHDL ROM of the TS36.212 Table 5.1.3-3 parameters
for all 188 supported `K`, generated from `internal_interleaver.m`'s table
(not hand-transcribed), each entry pre-reduced to `K`, `d0=(f1+f2) mod K`,
`step=(2·f2) mod K`.

#### Scenario: ROM is generated from the standard table

- **WHEN** the ROM package is produced
- **THEN** it is emitted by a generator that reads `internal_interleaver.m`'s
  parameter table and contains exactly the 188 supported entries

### Requirement: K to (d0, step) lookup with supported flag

The system SHALL provide a core that, given an input `K`, returns the matching
`(d0, step)` and a `supported` indication, and reports unsupported `K`
distinctly.

#### Scenario: Supported K resolves correctly

- **WHEN** the lookup is run with a supported `K`
- **THEN** it returns that row's `d0` and `step` and asserts `supported`

#### Scenario: Unsupported K is rejected

- **WHEN** the lookup is run with a `K` not in the table
- **THEN** it deasserts `supported`

### Requirement: Standalone hardware turbo-encode datapath

The system SHALL provide a top core that, given only a code block and its
length `K`, produces the TS36.212 §5.1.3.2 `3 × (K+4)` encoded matrix by
integrating the existing verified QPP-interleaver and turbo-encoder cores
without modifying them.

#### Scenario: Encoded output matches the software model end to end

- **WHEN** the top is driven with `K` and a code block `c`
- **THEN** the streamed `3 × (K+4)` output equals `turbo_encoder(c, pi)` with
  `pi = internal_interleaver(0:K-1)`

#### Scenario: Sub-cores are reused unmodified

- **WHEN** the integrated datapath is delivered
- **THEN** `qpp_interleaver.vhdl`, `turbo_encoder.vhdl`, and
  `rsc_constituent_encoder.vhdl` are unchanged

### Requirement: Simulation verified against the software golden model

The system SHALL verify the ROM lookup and the integrated datapath in
cocotb/GHDL against vectors derived from the existing software helpers,
reusing `hdl/vectors/turbo_encoder.csv` for the end-to-end check, with no
changes to existing cores, specs, or MATLAB/Octave sources, and with simulator
artifacts kept out of version control.

#### Scenario: End-to-end lane reuses existing golden vectors

- **WHEN** the integration lane runs
- **THEN** it drives only `K` and `c` from `hdl/vectors/turbo_encoder.csv` and
  asserts the produced `d` equals that row's expected matrix

#### Scenario: ROM unit lane checks every entry

- **WHEN** the ROM unit lane runs
- **THEN** every supported `K` returns the `d0/step` consistent with
  `internal_interleaver`, and unsupported `K` report `supported=0`

#### Scenario: No regression

- **WHEN** the change is delivered
- **THEN** the existing turbo, interleaver, and CRC HDL lanes and the Octave
  suite still pass, and build artifacts are gitignored
