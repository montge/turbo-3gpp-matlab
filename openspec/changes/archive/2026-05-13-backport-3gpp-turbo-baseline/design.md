## Context

The repository implements the encoder and decoder for the 3GPP LTE turbo code from Release 15 (TS36.212). The implementation has lived as MATLAB code only, with the entire specification implicit in section references inside `.m` file docstrings.

We want two things:

1. **A spec baseline.** Future changes (new decoder variants, new code rates, new modulation orders, performance work, etc.) should be proposable as deltas against a recorded `as-built` spec.
2. **Octave portability.** Researchers without MATLAB licenses should be able to run the simulation chain under GNU Octave. The implementation is almost entirely plain MATLAB; the only blocker is the `matlab.System` base class, which Octave does not ship.

## Goals / Non-Goals

**Goals:**
- Record the existing 3GPP turbo coding chain behavior as OpenSpec capabilities, preserving section-level traceability to TS36.212.
- Add a `matlab.System`-equivalent base class so `turbo_coding_chain` (and its `turbo_encoding_chain` / `turbo_decoding_chain` subclasses) instantiate, configure, and `step` under GNU Octave 8.4+.
- Provide a deterministic noise-free smoke test that exercises encode → decode and asserts bit-exact recovery, runnable as `octave --no-gui test_octave_smoke.m`.

**Non-Goals:**
- Re-architecting the existing API. Specs are written to match the current implementation, not an idealized one.
- Porting the plotting/simulation scripts (`plot_BLER_vs_SNR.m`, `plot_SNR_vs_A.m`) end-to-end under Octave. They use enough graphics behavior (live `set(plot, 'XData', ...)` updates) that we only need the *encode/decode core* to be portable for now.
- Changing any DSP behavior. No bit changes to encoder output, no LLR changes to decoder output.

## Decisions

### Decision 1: Capability granularity follows TS36.212 sections, not files

The specs are organized by 3GPP processing block (CRC, segmentation, internal interleaver, encoder, rate matching, decoder, coding-chain, simulation, octave-compatibility), not by `.m` filename. Multiple `.m` files often implement one section (e.g. `subblock_interleaver.m` + `circular_buffer.m` + `rate_matching.m` all live in `rate-matching`).

**Rationale:** Section-level granularity makes the specs reusable for any future implementation language and matches how 3GPP engineers reason about the chain.

### Decision 2: Octave shim is a `+matlab/System.m` package directory

GNU Octave supports `+namespace` package directories. By placing a `+matlab/System.m` classdef on the Octave path, the existing `classdef turbo_coding_chain < matlab.System` line resolves correctly without modification to any existing source file. The shim only needs to:

- Hold a `setProperties(obj, nargin, varargin{:})` method that copies name/value pairs onto the object.
- Provide a no-op `setupImpl`, `processTunedPropertiesImpl`, and `resetImpl` so subclasses can call `setupImpl@turbo_coding_chain(obj)` etc.
- Implement `step(obj, ...)` that lazily invokes `setupImpl` on first call (matching `matlab.System` semantics: the encoding-chain `stepImpl` references `obj.CRC_generator_matrix_TB` etc., which are populated by `setupImpl`).
- Implement `reset(obj)` that calls `resetImpl(obj)`.
- Forward `obj(...)` callable syntax (used by `plot_BLER_vs_SNR.m` at `f = hEnc(a)`) to `step(obj, ...)`.

**Rationale:** Zero diff to existing `.m` files. Pure additive shim, only active when Octave finds it on the path. MATLAB users won't see it because MATLAB resolves `matlab.System` to its built-in class first when MATLAB's toolbox is installed; if they don't have it, the shim works for them too.

### Decision 3: Dependent properties are recomputed on every access

The existing chain uses MATLAB's `properties(Dependent, SetAccess = protected)` with `get.<Name>` accessors. Octave's classdef supports `get.<Name>` accessors but the resolution semantics for the `Dependent` attribute on `<matlab.System` subclasses is fragile. The shim does NOT try to emulate `Dependent` — Octave's normal getter dispatch on classdef properties is sufficient for the read paths the encoder/decoder uses. We do not need to support direct *assignment* to a dependent property, and the existing code never assigns to one.

**Rationale:** Keep the shim minimal. The existing code only ever reads dependent properties.

### Decision 4: Smoke test asserts bit-exact recovery in the noise-free case

The simulation scripts add AWGN noise and measure BLER. For Octave validation, we want a deterministic pass/fail that doesn't depend on Monte Carlo. We pick the smallest interleaver size (`A = 16`, `K_r = 40`) and the smallest output `G = 132`, generate random information bits, encode, treat each encoded `0` as LLR `+1` and each encoded `1` as LLR `-1` (i.e. infinitely confident channel), and assert the decoder returns the original information bits.

**Rationale:** A noise-free round trip is deterministic, fast, and is the strongest single-shot evidence that the entire chain (segmentation, CRC, encoder, interleaver, rate matching, decoder, desegmentation, CRC check) actually composes.

## Risks / Trade-offs

- **Spec drift.** The specs were derived from the as-built code, so any latent bug in the implementation gets enshrined as the spec. We accept this — the value of having *any* recorded contract outweighs the risk of fossilizing minor bugs, and any bug found later can be fixed via a normal openspec change with a `MODIFIED Requirements` delta.
- **Octave/MATLAB divergence.** If a future change to the chain depends on `matlab.System` features the shim doesn't emulate (locking nontunable properties post-`setup`, automatic introspection of `properties(Nontunable)` blocks, etc.) it will pass on MATLAB and fail on Octave. The `octave-compatibility` spec records the supported surface area so future changes are forced to either extend the shim or be flagged as MATLAB-only.
- **No simulation port.** Users on Octave can run the encoder/decoder but not the `plot_*` drivers. Documented in the simulation spec as a known limitation.
