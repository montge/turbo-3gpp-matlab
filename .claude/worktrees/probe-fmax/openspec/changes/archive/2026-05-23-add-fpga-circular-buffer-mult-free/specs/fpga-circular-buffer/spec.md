## MODIFIED Requirements

### Requirement: Board-neutral circular-buffer core

The system SHALL provide a synthesizable, board-neutral VHDL core under
`hdl/rtl/` that, given a 3×`K_Pi` sub-block-interleaved matrix `v` (each
element a bit plus a `filler` flag) and parameters `(N_ref, I_LBRM, rv_idx,
E)`, produces the length-`E` rate-matched output of TS36.212 §5.1.4.1.2,
bit-for-bit equal to `circular_buffer(v, N_ref, I_LBRM, rv_idx, E)`.

The core's `N_cb` / `q` / `k_0` index and start-offset arithmetic SHALL use **no
embedded multipliers** — it SHALL be realized entirely with add / shift / compare
/ accumulate so the synthesized block maps to logic + M4K block RAM with **zero
DSP (embedded 9-bit multiplier) elements** at the full `KW_MAX` depth, while
remaining bit-for-bit equal to the software `circular_buffer`. In particular the
start offset `k_0 = R_TC·(2·⌈N_cb/(8·R_TC)⌉·rv_idx + 2)` SHALL be computed without
any variable×variable product (e.g. by accumulating the constant `2·R_TC·rv_idx`
over the same iterations that compute `q = ⌈N_cb/(8·R_TC)⌉`, then adding `2·R_TC`).

#### Scenario: Bit-collection buffer construction

- **WHEN** `v` is loaded
- **THEN** the core forms `w` of length `K_w = 3·K_Pi` with `w[k]=v(1,k)` for
  `k∈[0,K_Pi)` and the rows 2 and 3 interleaved as
  `w[K_Pi+2k]=v(2,k)`, `w[K_Pi+2k+1]=v(3,k)`

#### Scenario: Start offset matches the standard

- **WHEN** the core computes its start offset
- **THEN** `N_cb = K_w` for `I_LBRM=0` else `min(N_ref,K_w)`, and
  `k_0 = R_TC·(2·⌈N_cb/(8·R_TC)⌉·rv_idx + 2)` with `R_TC = K_Pi/32`

#### Scenario: Start-offset arithmetic uses no embedded multipliers

- **WHEN** the core computes `k_0 = R_TC·(2·q·rv_idx + 2)` (with
  `q = ⌈N_cb/(8·R_TC)⌉`)
- **THEN** it does so with no variable×variable product — the `q·rv_idx` term is
  produced by accumulating the constant `2·R_TC·rv_idx` over the `q` iterations of
  the existing divider-free `q` recurrence, and the constants `2·R_TC` and
  `2·R_TC·rv_idx` (with `rv_idx∈{0,1,2,3}`) are formed by shift/add/select — so
  the assignment infers add/shift logic, never an `lpm_mult` / embedded multiplier

#### Scenario: Filler-skipping circular read

- **WHEN** the output is produced
- **THEN** it is exactly `E` values read from `w` at `mod(k_0+j, N_cb)` with
  `j` advancing, skipping `filler` entries, equal to the `circular_buffer`
  golden output

#### Scenario: Synthesizes with zero DSP at full KW_MAX, M4K and timing retained

- **WHEN** the core is synthesized standalone at full `KW_MAX=18528` under
  Quartus II 13.0sp1 (EP2C35F672C6)
- **THEN** the Analysis & Synthesis report shows `Embedded Multiplier 9-bit
  elements = 0` while the `w` storage still infers M4K block RAM (`Total memory
  bits > 0`, ≈ 49,152 bits / 12 M4K) and the read clock closes `Fmax ≥ 50 MHz`

#### Scenario: Multiplier removal preserves the golden output and its lane

- **WHEN** the reworked core is run against the existing
  `hdl/sim/circular_buffer/` cocotb lane
- **THEN** every streamed length-`E` output bit matches
  `hdl/vectors/circular_buffer.csv` and the committed golden vectors are
  byte-identical
