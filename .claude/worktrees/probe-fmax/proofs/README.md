# Formal-verification proofs for turbo-3gpp-matlab

This directory holds the formal proofs that ratify the OpenSpec capabilities
under `openspec/specs/`. See `proofs/traceability.md` for the mapping from
each proof obligation to the spec scenario it discharges.

The directory is organised by toolchain:

| Subdirectory | Toolchain | Status |
|---|---|---|
| `lean/`     | Lean 4    | **landed** (PR 1) — encoder termination, QPP bijection, CRC equivalence on a finite A-grid |
| `tla/`      | TLA+ / TLC | **landed** (PR 2) — HARQ protocol safety + bounded liveness |
| `cryptol/`  | Cryptol + SAW | **landed** (PR 3) — CRC bit-level equivalence via a translated C reference |

## Running the Lean proofs locally

The Lean toolchain is pinned in `proofs/lean/lean-toolchain` (currently
`leanprover/lean4:v4.14.0`). To check the proofs:

```bash
# Install elan (Lean's toolchain manager) if you don't have it.
curl -sSf https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | sh -s -- -y --default-toolchain none

# elan picks up the pinned Lean version from proofs/lean/lean-toolchain.
cd proofs/lean
lake build
```

The build is deliberately mathlib-free: the three proof modules
(`Turbo3gpp.CRC`, `Turbo3gpp.Interleaver`, `Turbo3gpp.Encoder`) rely only
on Lean's stdlib. A clean rebuild completes in a few seconds.

### Axiom audit

Every theorem in the suite depends only on Lean's foundational axioms. To
verify after a build:

```bash
cd proofs/lean
LEAN_PATH=.lake/build/lib lean --root=. <(echo '
  import Turbo3gpp
  #print axioms Turbo3gpp.Encoder.termination_reaches_zero_state
  #print axioms Turbo3gpp.Interleaver.qpp_bijection_for_supported_K
  #print axioms Turbo3gpp.CRC.crc24A_equivalence
')
```

Expected output:

```text
'...termination_reaches_zero_state' does not depend on any axioms
'...qpp_bijection_for_supported_K' depends on axioms: [propext, Lean.ofReduceBool]
'...crc24A_equivalence' depends on axioms: [propext, Lean.ofReduceBool, Quot.sound]
```

No `sorry`, no `admit`, no user-declared axioms.

### Network-restricted runners

The default Lean release server is `release.lean-lang.org`. In environments
where that host is firewalled (some corporate networks; some CI runners),
elan can be primed by downloading the tarball directly from GitHub releases
and unpacking it into the elan toolchain directory:

```bash
mkdir -p ~/.elan/toolchains/leanprover--lean4---v4.14.0
curl -L https://github.com/leanprover/lean4/releases/download/v4.14.0/lean-4.14.0-linux.tar.zst \
  | tar --use-compress-program=zstd -x --strip-components=1 \
  -C ~/.elan/toolchains/leanprover--lean4---v4.14.0
elan default leanprover/lean4:v4.14.0
```

This is the workaround the CI step under `.github/workflows/ci.yml` uses
on the `verify-lean` job.

## Running the TLA+ proofs locally

`proofs/tla/` holds the HARQ protocol model (`harq.tla`), its TLC
configuration (`harq.cfg`), and the pinned `tla-version` shell file
(`TLAPLUS_VERSION`, download URL, SHA-256). The model is checked by
TLC 1.8.0+ over a 4-RV / 2-tag state space (~70 states, sub-second).

```bash
# Fetch the pinned tla2tools.jar (one-time, ~4 MB).
source proofs/tla/tla-version
mkdir -p ~/.tla
curl -L "$TLA2TOOLS_URL" -o ~/.tla/tla2tools.jar
echo "$TLA2TOOLS_SHA256  $HOME/.tla/tla2tools.jar" | sha256sum -c -

# Run the model checker.
cd proofs/tla
java -XX:+UseParallelGC -cp ~/.tla/tla2tools.jar tlc2.TLC \
    -config harq.cfg -workers auto harq.tla
```

Expected final line:

```text
Model checking completed. No error has been found.
```

The three invariants (`TypeOK`, `CRCPassImpliesSyndromeZero`,
`DoneIsExplicit`) and the temporal property `EventualTermination` are
all checked in the same TLC invocation.

## Running the Cryptol / SAW proofs locally

`proofs/cryptol/` holds:

- `crc_3gpp.cry` — Cryptol specification of all four 3GPP CRC
  polynomials as bit-vector operations (the canonical algorithmic
  form: LFSR / polynomial division over GF(2)).
- `calculate_crc_bits.c` — C transliteration of `calculate_crc_bits.m`,
  with per-polynomial entry points (`crc24A_A16`, `crc24B_A16`,
  `crc16_A16`, `crc8_A16`) so SAW can verify each instantiation.
- `crc_3gpp.saw` — SAW driver that compiles the C to LLVM bitcode,
  loads the Cryptol spec, and asks Z3 to prove they agree on every
  16-bit input. Catches the real off-by-one cases (one was found and
  fixed in `crc24B_poly` during initial development).
- `version.txt` — shell-sourceable pin file recording the SAW release,
  download URL, and SHA-256.

Local install:

```bash
# Fetch and verify the pinned SAW toolchain (~218 MB, includes Z3, CVC4,
# Bitwuzla, Yices, ABC, Cryptol). Only needed once per workstation.
source proofs/cryptol/version.txt
mkdir -p ~/.saw
curl -L "$SAW_TARBALL_URL" -o /tmp/saw.tar.gz
echo "$SAW_TARBALL_SHA256  /tmp/saw.tar.gz" | sha256sum -c -
tar -xzf /tmp/saw.tar.gz -C ~/.saw --strip-components=1
export PATH="$HOME/.saw/bin:$PATH"

# Compile the C reference + run the SAW proof.
cd proofs/cryptol
clang -emit-llvm -c -O0 -g calculate_crc_bits.c -o calculate_crc_bits.bc
saw crc_3gpp.saw
```

Expected final output:

```text
Proof succeeded! crc24A_A16
Proof succeeded! crc24B_A16
Proof succeeded! crc16_A16
Proof succeeded! crc8_A16
All four CRC equivalence goals discharged.
```

Total wall-clock under 10 seconds on a modern x86_64 laptop; each goal
is a 2^16 = 65 536-input SMT problem dispatched to Z3.
