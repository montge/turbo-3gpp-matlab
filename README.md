# turbo-3gpp-matlab

[![CI](https://github.com/montge/turbo-3gpp-matlab/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/montge/turbo-3gpp-matlab/actions/workflows/ci.yml)
[![License: GPL v3](https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg)](LICENSE)
[![OpenSpec](https://img.shields.io/badge/spec--driven-OpenSpec-6f42c1.svg)](https://github.com/Fission-AI/OpenSpec)
[![Formal verification](https://img.shields.io/badge/formal--verification-Lean%204%20%7C%20TLA%2B%20%7C%20Cryptol%2FSAW-2ea44f.svg)](proofs/README.md)
[![Octave 8.4 tested](https://img.shields.io/badge/GNU%20Octave-8.4%2B-1f425f.svg)](https://www.gnu.org/software/octave/)

MATLAB simulations of the encoder and decoder for the LTE turbo code from 3GPP Release 15 (TS36.212).

## Running on GNU Octave

The encoder/decoder core runs unmodified on GNU Octave 8.4+ via the minimal `matlab.System` shim at `octave_shims/+matlab/System.m`. To validate the chain end-to-end (encode → noise-free LLR mapping → decode → bit-exact match):

```bash
octave --no-gui test_octave_smoke.m
```

MATLAB users should run from the repository root normally; the Octave shim is kept off MATLAB's default package path so it does not shadow MathWorks' built-in `matlab.System`.

The plotting/simulation drivers (`plot_BLER_vs_SNR.m`, `plot_SNR_vs_A.m`) still require MATLAB.

## Running tests

The repository ships an [MOxUnit](https://github.com/MOxUnit/MOxUnit) test suite (~95 tests across 24 files) and a [MOcov](https://github.com/MOcov/MOcov) line-coverage gate. Both run on GNU Octave 8.4+ and on MATLAB R2020a+.

Clone with submodules:

```bash
git clone --recursive https://github.com/montge/turbo-3gpp-matlab.git
# Or if already cloned:
git submodule update --init --recursive
```

Run the test suite (unit tests in `tests/` + property-based tests in `tests/property/`):

```bash
npm test                                  # or: bash scripts/run_tests.sh
```

Run line-coverage measurement under MOcov with the 90 % gate (writes `tests/coverage.txt`, fails non-zero below the gate):

```bash
bash scripts/run_coverage.sh
```

Run static analysis (MISS_HIT `mh_style` + `mh_lint` + `mh_metric`, with the project's `miss_hit.cfg`):

```bash
pip install miss_hit==0.9.42
bash scripts/run_miss_hit.sh
```

Check that every `#### Scenario:` block in the OpenSpec capability specs has at least one matching test function (CI gates this):

```bash
python3 scripts/check_spec_traceability.py
```

Check that every Lean, TLA+, and Cryptol proof source is listed in the formal verification traceability matrix:

```bash
python3 scripts/check_proof_traceability.py
```

CI uploads `tests/coverage.txt`, `tests/coverage.xml`, and `tests/metric.txt` as the `test-artifacts` artifact on every run (pass or fail) so you can review per-PR coverage trends.

## Specification

Behavior is recorded under [`openspec/`](openspec/) as a [Fission-AI OpenSpec](https://github.com/Fission-AI/OpenSpec) project. Validate locally:

```bash
npx openspec validate --all --strict
```
