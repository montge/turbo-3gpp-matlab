# turbo-3gpp-matlab

[![CI](https://github.com/montge/turbo-3gpp-matlab/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/montge/turbo-3gpp-matlab/actions/workflows/ci.yml)
[![License: GPL v3](https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg)](LICENSE)
[![OpenSpec](https://img.shields.io/badge/spec--driven-OpenSpec-6f42c1.svg)](https://github.com/Fission-AI/OpenSpec)
[![Octave 8.4 tested](https://img.shields.io/badge/GNU%20Octave-8.4%2B-1f425f.svg)](https://www.gnu.org/software/octave/)

MATLAB simulations of the encoder and decoder for the LTE turbo code from 3GPP Release 15 (TS36.212).

## Running on GNU Octave

The encoder/decoder core runs unmodified on GNU Octave 8.4+ via the minimal `matlab.System` shim at `+matlab/System.m`. To validate the chain end-to-end (encode → noise-free LLR mapping → decode → bit-exact match):

```bash
octave --no-gui test_octave_smoke.m
```

The plotting/simulation drivers (`plot_BLER_vs_SNR.m`, `plot_SNR_vs_A.m`) still require MATLAB.

## Specification

Behavior is recorded under [`openspec/`](openspec/) as a [Fission-AI OpenSpec](https://github.com/Fission-AI/OpenSpec) project. Validate locally:

```bash
npx openspec validate --all --strict
```
