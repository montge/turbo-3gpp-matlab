# RX-chain (end-to-end) HDL simulation

`rx_chain_top` wires the soft de-rate-match (`de_rate_matching_top`) straight
into the **unmodified** `turbo_decoder_top` — the complete LTE **receive** chain
(received channel LLRs → K decoded hard bits), the reverse of `tx_chain_top`.

This lane is the **end-to-end smoke gate**: it drives each golden frame's
`e_soft` channel-LLR stream through the DUT and asserts the K decoded bits equal
the reference CHAIN
`fixedpoint_turbo_decoder(fixedpoint_de_rate_matching(e_q, …), pi, 8)`
**bit-for-bit**. Each sub-core is already bit-exact in isolation (the
`de_rate_matching_top` lane for the de-rate-match; the `turbo_decoder_top` lane
for the decode), so this gate isolates the `rx_chain_top` wiring / handshake
between the de-rate-match column stream and the decoder load port.

The deep **BER-vs-SNR** trend is the Octave outer harness
`scripts/characterize_rx_chain.m` (TX → BPSK+AWGN → RX vs the float path); this
cocotb lane is the few-frame bit-exact smoke check.

See **`hdl/sim/de_rate_matching_top/README.md`** for the full two-tier method,
the de-rate-match-as-inverse algebra, the CSV schemas, the W_LLR/W_DRM/W_EXT
pins, regenerate/run commands, the BER result, and the deferred follow-ons.

## Run

```
cd hdl/sim/rx_chain_top && make SIM=ghdl    # 4/4 frames bit-exact vs reference chain
```

`hdl/vectors/rx_chain_top.csv` decodes at H = 2·max_iter = 16 (the
`MAX_ITERATIONS = 8` DUT default the Makefile elaborates).
