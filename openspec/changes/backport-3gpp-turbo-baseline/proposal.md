## Why

The repository ships a working MATLAB implementation of the 3GPP LTE turbo coding chain (Release 15, TS36.212) but has no machine-readable specification for the behavior it provides. New contributors and AI agents have to re-derive the contract by reading code. We also want to run the simulations under GNU Octave for users without a MATLAB license, which requires a small compatibility shim around the `matlab.System` base class.

This change backports the *existing* behavior into OpenSpec as the baseline ("the spec describes what is already there") and adds one genuinely new capability: GNU Octave compatibility.

## What Changes

- Document the existing 3GPP LTE turbo encoder, decoder, and supporting blocks as OpenSpec capabilities so downstream changes can be proposed as deltas against a recorded baseline.
- Add a thin compatibility layer so `turbo_coding_chain`, `turbo_encoding_chain`, and `turbo_decoding_chain` can be instantiated and stepped under GNU Octave 8.4+, which lacks the `matlab.System` base class.
- Provide a small Octave smoke test that exercises the encode → decode round trip for a default-sized transport block and verifies bit-exact recovery of the information bits in the noise-free case.
- No requirement changes to the existing DSP behavior — this proposal records the as-built contract and only **adds** the Octave-compatibility requirements.

## Capabilities

### New Capabilities

- `crc`: CRC polynomial selection (CRC24A/CRC24B/CRC16/CRC8), generator-matrix construction, and the generate/check/remove operations used by both the transport block and code block layers.
- `code-block-segmentation`: Segmentation of a transport block into `C` code blocks per TS36.212 §5.1.2, including filler-bit handling and per-segment code block CRC when `C > 1`, plus the inverse desegmentation operation with CRC verification.
- `internal-interleaver`: The QPP interleaver from TS36.212 §5.1.3.2.3 across all 188 supported information-block lengths `K ∈ {40, …, 6144}`.
- `turbo-encoder`: The rate-1/3 parallel-concatenated convolutional encoder of TS36.212 §5.1.3.2, including the 3-memory recursive constituent encoder, trellis termination, and the internal interleaver.
- `rate-matching`: Subblock interleaving (§5.1.4.1.1) and the circular buffer with redundancy versions 0–3 and optional limited-buffer rate matching (§5.1.4.1.2), plus the inverse rate-dematching used by the decoder.
- `turbo-decoder`: Iterative Log-BCJR decoding of the rate-1/3 turbo code with configurable iteration count, `max*` vs `max` metric combining, optional HARQ LLR accumulation, and CRC-driven early termination.
- `coding-chain`: The top-level `turbo_coding_chain`, `turbo_encoding_chain`, and `turbo_decoding_chain` system-object–style API that owns all derived parameters (`B`, `C`, `K_r`, `D_r`, `E_r`, `N_ref`, …) and dispatches the per-segment encode/decode pipeline.
- `simulation`: The reusable `plot_BLER_vs_SNR` and `plot_SNR_vs_A` simulation drivers, including their result-file format, HARQ retransmission protocol, and early-stop criteria.
- `octave-compatibility`: A minimal `matlab.System`-equivalent base class plus a smoke test so the encoding and decoding chains run unmodified under GNU Octave 8.4+.

### Modified Capabilities

None. This change records the baseline as-is.

## Impact

- New OpenSpec specs under `openspec/specs/{crc,code-block-segmentation,internal-interleaver,turbo-encoder,rate-matching,turbo-decoder,coding-chain,simulation,octave-compatibility}/spec.md`.
- New `+matlab/System.m` shim (Octave-only) — placed on the path so MATLAB users are unaffected.
- New `test_octave_smoke.m` exercising the encode/decode round trip and meant to be runnable as `octave --no-gui test_octave_smoke.m`.
- One one-character fix to an existing `.m` file: `turbo_decoding_chain.m`'s constructor was misnamed `NRLDPCDecoder` (a copy-paste artifact from a sibling LDPC project). Under MATLAB this worked accidentally because `matlab.System`'s built-in constructor applies name/value pairs when a subclass omits a proper constructor; under Octave the subclass's misnamed constructor became a regular method and construction args were silently dropped. Renamed to `turbo_decoding_chain` to match the class name.
- No other changes to existing `.m` files in the repository root; the existing implementation is the source of truth for the backported specs.
