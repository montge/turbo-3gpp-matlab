# Circular buffer HDL simulation

Verifies `hdl/rtl/circular_buffer.vhdl` bit-for-bit against the MATLAB/Octave
`circular_buffer` (TS36.212 §5.1.4.1.2).

## Golden vectors

`hdl/vectors/circular_buffer.csv` — one case per row:

| column | meaning |
|--------|---------|
| `K_Pi` | columns of `v` (multiple of 32) |
| `N_ref`,`I_LBRM`,`rv_idx`,`E` | circular-buffer parameters |
| `v` | `3·K_Pi` ints, column-major (`v(1,k) v(2,k) v(3,k)` per column), bit `0/1` or `-1` = NaN filler |
| `e` | `E`-char bit string = `circular_buffer(v, N_ref, I_LBRM, rv_idx, E)` |

`v` is built realistically (sub-block interleave of a random encoder-shaped
`d`), so the filler is the genuine left-pad pattern, matching how
`rate_matching` feeds the circular buffer.

### Regenerate

```
OCTAVE_BIN=<octave-cli> octave --no-gui --quiet --eval \
  "addpath(pwd); addpath(fullfile(pwd,'octave_shims')); \
   run('scripts/generate_hdl_circular_buffer_vectors.m')"
```

Suite: `K_Pi` from `D∈{44,516,6148}`; `rv_idx∈{0,1,2,3}`; `I_LBRM∈{0,1}`
(with a constraining `N_ref`); `E` including values that force buffer wrap.

## Run

```
cd hdl/sim/circular_buffer && make SIM=ghdl
```

## Design / follow-ons

`w[k]=v(1,k)`; `w[K_Pi+2k]=v(2,k)`; `w[K_Pi+2k+1]=v(3,k)`.
`N_cb = K_w(=3·K_Pi)` if `I_LBRM=0` else `min(N_ref,K_w)`.
`k_0 = R_TC·(2·⌈N_cb/(8·R_TC)⌉·rv_idx + 2)`, `R_TC=K_Pi/32`. Read `E`
non-filler bits at `mod(k_0+j,N_cb)`.

v1 is **sim-first**: integer `/`,`mod` are used directly (GHDL exact). The
explicit next follow-ons (out of scope here) are: the full `rate_matching`
integration (3× verified `subblock_interleaver` + this core, then chained with
`turbo_encode_top` for a complete HW TX chain) and a divider-free /
BRAM-mapped synthesis hardening.
