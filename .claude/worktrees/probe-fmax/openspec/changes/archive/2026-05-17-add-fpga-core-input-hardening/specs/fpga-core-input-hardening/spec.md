## ADDED Requirements

### Requirement: Verified behaviour is preserved

Every input-validation guard or cleanliness fix SHALL be additive such that,
for all currently-verified golden vectors, every affected HDL lane remains
**bit-exact** with no change to any committed vector.

#### Scenario: All lanes stay green and bit-exact

- **WHEN** the hardening is applied and the HDL lanes are re-run
- **THEN** every lane passes bit-exact against its unchanged committed golden
  CSV, and the full regression (all HDL lanes + Octave) stays green

### Requirement: Invalid inputs are handled safely

The cores SHALL handle out-of-contract inputs without undefined behaviour:
`circular_buffer` (`K_Pi`/`N_cb`/`E = 0`), `rate_matching_top`
(`d_len = 0` or `> DMAX`), and `subblock_interleaver` (`d_in = 0`) SHALL NOT
perform divide/mod-by-zero or out-of-range buffer access, taking a defined
idle/abort path instead.

#### Scenario: Zero/over-range input does not corrupt or hang

- **WHEN** a core is driven with a zero or over-range size parameter
- **THEN** it takes a defined safe path (no UB, no out-of-range access, no
  silent garbage output)

### Requirement: Unsupported K is rejected in the encode datapath

`turbo_encode_top` SHALL honour `qpp_rom`'s supported indication and SHALL NOT
proceed to encode with the ROM's `(d0, step)` when `K` is unsupported; the
supported-`K` behaviour SHALL be identical to before.

#### Scenario: Unsupported K does not silently mis-encode

- **WHEN** `turbo_encode_top` is driven with a `K` absent from the QPP table
- **THEN** it surfaces an unsupported indication and does not emit an
  encoding computed from invalid constants

#### Scenario: Supported K unchanged

- **WHEN** driven with a supported `K`
- **THEN** the output is bit-identical to the pre-hardening core

### Requirement: Interface, generator, and doc cleanliness

`qpp_rom.done` SHALL have consistent, documented timing semantics consumable
by its integrators; `generate_hdl_qpp_rom.m` SHALL create the output
directory before writing; flagged documentation code fences SHALL carry a
language identifier — none of which changes any verified result.

#### Scenario: Generator works on a clean checkout

- **WHEN** `generate_hdl_qpp_rom.m` runs where `hdl/vectors/` does not yet
  exist
- **THEN** it creates the directory and writes the CSV successfully

#### Scenario: done semantics keep integrators green

- **WHEN** `qpp_rom.done` timing is finalized
- **THEN** the `qpp_rom`, `turbo_encode_top`, and `tx_chain_top` lanes all
  still pass bit-exact
