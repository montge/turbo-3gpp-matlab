# octave-compatibility Specification

## Purpose
Defines the minimal `matlab.System` shim under `octave_shims/+matlab/System.m` plus the `test_octave_smoke.m` round-trip script that together let the turbo encoder, decoder, and coding-chain classes run unmodified on GNU Octave 8.4+ without shadowing MATLAB's built-in `matlab.System`.
## Requirements
### Requirement: matlab.System shim for Octave

The system SHALL provide a GNU Octave-compatible `matlab.System` base class under `octave_shims/+matlab/System.m` so that the existing `classdef turbo_coding_chain < matlab.System` (and its subclasses) instantiate and execute under Octave when `octave_shims` is added to the Octave path, without modification to any existing `.m` file. The shim SHALL implement, at minimum:

- A constructor that accepts no arguments and produces a configurable object.
- A `setProperties(obj, n_args, varargin)` method that copies any `'Name', Value` pairs in `varargin` onto the corresponding object property, calling the property's set-method if one exists. The expected calling convention is `setProperties(obj, nargin, varargin{:})` from the subclass constructor — `nargin` is the MATLAB intrinsic evaluated at the constructor's call site (it equals the number of arguments the constructor received), and `varargin{:}` expands the constructor's variadic arguments. `setProperties` uses the passed-in count to iterate the name/value pairs. This is the established matlab.System idiom; subclasses do NOT manually pass the count.
- A `step(obj, varargin{:})` method that:
  - On its first call (or the first call after `release`), invokes `setupImpl(obj)` on the subclass, then `processTunedPropertiesImpl(obj)`.
  - On every call, dispatches to `stepImpl(obj, varargin{:})` and returns its outputs.
- A `reset(obj)` method that calls `resetImpl(obj)` on the subclass.
- A `release(obj)` method that marks the object as not-yet-set-up so the next `step` re-runs `setupImpl`.
- Callable forwarding so `obj(arg1, arg2, …)` is equivalent to `step(obj, arg1, arg2, …)` (used at `f = hEnc(a)` in the simulation driver).
- No-op default implementations of `setupImpl`, `processTunedPropertiesImpl`, and `resetImpl` so subclasses may either override them or call them with `setupImpl@matlab.System(obj)` semantics.

The shim MUST NOT enforce nontunable-property locking and MUST NOT emulate the `Dependent` attribute beyond what Octave's classdef getter dispatch already provides — the existing code does not rely on those behaviors.

#### Scenario: Construction with name-value pairs
- **WHEN** an Octave session constructs a `turbo_encoding_chain('A', 16, 'G', 132, 'Q_m', 2)` with `octave_shims` on the path
- **THEN** the object exposes `A = 16`, `G = 132`, `Q_m = 2` and `step(obj, a)` runs the encoding pipeline without error

#### Scenario: Lazy setupImpl on first step
- **WHEN** `step(obj, a)` is called for the first time on a freshly constructed `turbo_encoding_chain`
- **THEN** the shim invokes `setupImpl` once before `stepImpl`, populating the hidden CRC and interleaver properties

#### Scenario: Callable forwarding
- **WHEN** `hEnc(a)` is used in place of `step(hEnc, a)`
- **THEN** the result is identical to `step(hEnc, a)`

#### Scenario: reset and re-setup
- **WHEN** `release(obj)` is called and a subsequent `step(obj, …)` is invoked
- **THEN** `setupImpl` is re-run before `stepImpl`

### Requirement: Octave smoke test for encode → decode round trip

The system SHALL provide a `test_octave_smoke.m` script, runnable as `octave --no-gui test_octave_smoke.m` from the repository root, that:

1. Seeds the random number generator deterministically.
2. Constructs a `turbo_encoding_chain` and a `turbo_decoding_chain` with `A = 16`, `G = 132`, `Q_m = 2`, and `iterations = 8`.
3. Generates a random binary `1 × A` information vector `a`.
4. Encodes `a` to produce `f`, maps `0 → +1` and `1 → -1` to form a noise-free LLR vector, and decodes to recover `a_hat`.
5. Compares `a_hat` to `a` and exits with status code 0 on bit-exact match, non-zero otherwise. The script SHALL print `OCTAVE SMOKE TEST PASSED` on success.

#### Scenario: Smoke test passes on Octave 8.4
- **WHEN** the test is invoked as `octave --no-gui test_octave_smoke.m` from the repository root
- **THEN** the script prints `OCTAVE SMOKE TEST PASSED` and exits with status 0

#### Scenario: Smoke test fails on broken encode/decode
- **WHEN** the encode or decode pipeline returns a vector that does not match the original `a`
- **THEN** the script exits with a non-zero status code and does NOT print the pass marker
