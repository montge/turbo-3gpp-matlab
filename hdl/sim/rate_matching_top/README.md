# Rate matching (integrated) HDL simulation

`rate_matching_top` integrates three **unmodified** `subblock_interleaver`
instances (idx 0/1/2, run in lockstep) and the **unmodified** `circular_buffer`
into the full TS36.212 §5.1.4.1 `rate_matching`. Verified bit-for-bit against
`rate_matching.m`.

## Golden vectors

`hdl/vectors/rate_matching.csv` — one case per row:

| column | meaning |
|--------|---------|
| `D` | input columns (= K+4 in the chain) |
| `N_ref`,`I_LBRM`,`rv`,`E` | rate-match parameters |
| `d` | `3·D` bits, column-major (`d(1,k) d(2,k) d(3,k)` per column) |
| `e` | `E`-char bit string = `rate_matching(d, N_ref, I_LBRM, rv, E)` |

### Regenerate

```
OCTAVE_BIN=<octave-cli> octave --no-gui --quiet --eval \
  "addpath(pwd); addpath(fullfile(pwd,'octave_shims')); \
   run('scripts/generate_hdl_rate_matching_vectors.m')"
```

Suite: `D` from `K∈{40,512,6144}`; `rv∈{0,2,3}`; `I_LBRM∈{0,1}`
(constraining `N_ref`); `E` including buffer wrap.

## Run

```
cd hdl/sim/rate_matching_top && make SIM=ghdl
```

## Follow-on (not in this change)

Divider-free / BRAM synthesis hardening of the rate-match path and an optional
DE2 demo are the explicit next follow-ons; v1 is correctness-first.
