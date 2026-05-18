# Complete TX chain HDL simulation

`tx_chain_top` wires the **unmodified** `turbo_encode_top` into the
**unmodified** `rate_matching_top`: a code block `c` + `K` + rate-match
params produce the length-`E` rate-matched bits — the complete LTE
transmit chain. Verified bit-for-bit against the composed software model
`rate_matching(turbo_encoder(c, internal_interleaver(0:K-1)), …)`.

## Golden vectors

`hdl/vectors/tx_chain.csv` — one case per row:

| column | meaning |
|--------|---------|
| `K` | code-block length |
| `N_ref`,`I_LBRM`,`rv`,`E` | rate-match parameters |
| `c` | `K`-char code-block bit string |
| `e` | `E`-char rate-matched bit string (full-chain output) |

### Regenerate

```
OCTAVE_BIN=<octave-cli> octave --no-gui --quiet --eval \
  "addpath(pwd); addpath(fullfile(pwd,'octave_shims')); \
   run('scripts/generate_hdl_tx_chain_vectors.m')"
```

Suite: `K∈{40,512,6144}`; `rv∈{0,2,3}`; `I_LBRM∈{0,1}`; `E` incl. wrap.

## Run

```
cd hdl/sim/tx_chain_top && make SIM=ghdl
```

## Status

This is the capstone of the HDL transmit side: turbo encode + QPP interleave +
QPP ROM + sub-block interleave + circular buffer, every block individually
golden-verified and now integrated end-to-end. Divider-free / BRAM synthesis
hardening and an optional DE2 demo are the explicit next follow-ons.
