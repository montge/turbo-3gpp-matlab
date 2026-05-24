## Why

This is roadmap milestone **P4** (`hdl/docs/decoder_roadmap.md` §3, "RX-chain
integration"): build the **receive-side inverse** of the completed `tx_chain_top`
capstone, feeding the now-verified turbo decoder. The TX chain
(CRC → code-block segmentation → turbo encode → subblock-interleave →
circular-buffer rate-match) runs on real silicon; the decoder cores
(`turbo_decoder_top`, `turbo_decoder_term_top`) are sim-verified. What is
missing is the glue that turns received soft samples back into decoder input:
**de-rate-matching** and **code-block desegmentation**. P4 was explicitly scoped
"later, once P1–P3 land" — they have landed, so this formalizes P4.

The RX chain mirrors `tx_chain_top` in reverse: inverse circular-buffer
selection + **soft combining** of HARQ retransmissions, inverse subblock
interleave (gathering the three soft streams back into systematic/parity), code
-block **desegmentation** (concatenating per-block decoded bits and stripping the
per-block CRC), then feeding `turbo_decoder_top`. It is **integration of
existing cores**, not new decode math, verified end-to-end against the Octave RX
model.

## What Changes

- **Add** an RX-chain top (`rx_chain_top`, the inverse of `tx_chain_top`):
  - **inverse rate-matching** — inverse circular-buffer (de-selection back to
    the mother-code positions, with soft-combining accumulation for HARQ) and
    inverse subblock-interleave, reconstructing the three soft LLR streams;
  - **code-block desegmentation** — drive each segmented block through the
    decoder and concatenate the decoded bits, removing per-block CRC;
  - **feed `turbo_decoder_top`** (reused unmodified) per block.
- **Verify** end-to-end against the **Octave RX model**: the HDL `rx_chain_top`
  output (decoded transport-block bits) matches the float RX reference within
  the documented decoder margin, and the inverse-rate-match soft streams are
  bit/numerically checked against the model (inner gate where the stage is
  integer/soft-deterministic, BER-margin where the decoder is in the loop).

All work is **proposal-only in this change** — no `hdl/`, `scripts/`, `.qsf`,
or `.m` edits land here. The exact soft-combining accumulation format and the
desegmentation buffering are deferred to when this change is started.

## Capabilities

### New Capabilities

- `fpga-rx-chain-integration`: an `rx_chain_top` that inverts `tx_chain_top` —
  inverse circular-buffer + soft-combining + inverse subblock-interleave
  (de-rate-matching), code-block desegmentation, and per-block feeding of the
  reused `turbo_decoder_top` — verified end-to-end against the Octave RX model.

## Impact

- Integrates existing capabilities `fpga-circular-buffer`,
  `fpga-subblock-interleaver`, `fpga-rate-matching`, `code-block-segmentation`,
  and `fpga-turbo-decode-loop` into a receive capstone mirroring
  `fpga-tx-chain-de2-demo`'s `tx_chain_top`.
- Depends on the two-tier discipline (cocotb/GHDL bit-or-numeric exact for the
  inverse-rate-match stages + bounded BER margin once the decoder is in the
  loop) and Quartus II 13.0sp1.
- Risk: soft-combining accumulation width and the inverse-circular-buffer
  de-selection are the new pieces; the rest is reuse. Board demo is out of scope
  here.

## Out of Scope (explicit)

- A DE2 board demo of the RX chain (a later capstone like the TX demo).
- Channel estimation / demodulation / LLR formation upstream of the soft
  samples (the RX chain starts from soft LLRs, as the decoder does today).
- Decoder accuracy/memory maturation (M1/M2, separate changes).
