## ADDED Requirements

### Requirement: RX chain inverts the TX chain and feeds the decoder

The system SHALL provide an `rx_chain_top` that inverts `tx_chain_top` —
performing de-rate-matching (inverse circular-buffer de-selection with
soft-combining and inverse subblock-interleave), code-block desegmentation, and
per-block feeding of the reused `turbo_decoder_top` core — to recover the
decoded transport-block bits from received soft LLR samples.

#### Scenario: De-rate-matching reconstructs the soft streams

- **WHEN** `rx_chain_top` receives the soft LLR samples for a transport block
- **THEN** it performs inverse circular-buffer de-selection back to the
  mother-code positions (accumulating soft-combined HARQ retransmissions) and
  inverse subblock-interleave, reconstructing the three soft LLR streams the
  decoder expects

#### Scenario: Desegmentation and decoder feed produce transport-block bits

- **WHEN** the soft streams for each segmented code block are available
- **THEN** `rx_chain_top` drives each block through the reused
  `turbo_decoder_top` (unmodified), concatenates the per-block decoded bits, and
  strips the per-block CRC to yield the decoded transport-block bits

### Requirement: RX chain verified end-to-end against the Octave RX model

The system SHALL verify `rx_chain_top` end-to-end against the float Octave RX
model: the deterministic inverse-rate-match stages numeric-exact, and the
full decoded output within the documented decoder BER margin.

#### Scenario: End-to-end match within the decoder margin

- **WHEN** a TX golden frame is passed through channel/soft samples and into
  `rx_chain_top`
- **THEN** the reconstructed soft streams match the Octave RX model for the
  deterministic inverse-rate-match stages
- **AND** the decoded transport-block bits match the Octave RX reference within
  the documented decoder margin
