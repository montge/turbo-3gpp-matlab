# Standalone turbo-encode datapath HDL simulation

`turbo_encode_top` integrates three **unmodified** verified cores into a
self-contained LTE turbo encoder: feed a code block + `K`, get the TS36.212
§5.1.3.2 `3 × (K+4)` matrix.

```
 K + code block ─▶ block buffer ─┬─▶ buf(i)      ─▶ turbo_encoder ─▶ d (3×(K+4))
                                 └─▶ buf(pi(i)) ─▶      ▲
   qpp_rom: K → (d0,step) ─▶ qpp_interleaver: pi(i) ────┘
```

- `qpp_rom` (`hdl/rtl/qpp_rom.vhdl` + generated `qpp_rom_pkg.vhd`) maps `K` to
  `(d0,step)` via the 188-entry TS36.212 Table 5.1.3-3.
- `qpp_interleaver` streams `pi(i)`; `turbo_encoder` does RSC + assembly.
- An input buffer (1 write, 2 async read ports) supplies `buf(i)` and
  `buf(pi(i))` so the encoder gets natural- and interleaved-order bits.

## Verification

- **End-to-end lane** (`hdl/sim/turbo_encode_top/`) reuses
  `hdl/vectors/turbo_encoder.csv`: drives only `K` and `c`, asserts the
  produced `d` equals the golden matrix (the top derives `c_prime` itself).
- **ROM unit lane** (`hdl/sim/qpp_rom/`) checks every supported `K` →
  `d0/step` vs `hdl/vectors/qpp_rom.csv`, and that unsupported `K` report
  `supported=0`.

## Regenerate the ROM

```
OCTAVE_BIN=<octave-cli> octave --no-gui --quiet --eval \
  "addpath(pwd); addpath(fullfile(pwd,'octave_shims')); \
   run('scripts/generate_hdl_qpp_rom.m')"
```

Parses the `parameters` table straight out of `internal_interleaver.m`
(authoritative TS36.212 Table 5.1.3-3) and emits the committed
`hdl/rtl/qpp_rom_pkg.vhd` (188 entries) + `hdl/vectors/qpp_rom.csv` — never
hand-edited.

## Run the lanes

```
cd hdl/sim/qpp_rom          && make SIM=ghdl
cd hdl/sim/turbo_encode_top && make SIM=ghdl
```

## Follow-on (not in this change)

`turbo_encode_top` is correctness-first: a simple async-read buffer and a
scanning ROM lookup. BRAM/true-dual-port + pipelined lookup (throughput) and an
optional DE2 demo are the explicit next follow-on.
