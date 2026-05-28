#!/usr/bin/env bash
# Run every cocotb/GHDL HDL lane under hdl/sim/*/ against the COMMITTED golden
# vectors. Fails fast-ish: runs all lanes, reports per-lane status, exits
# non-zero if any lane did not pass. Used by the CI hdl-sim job and locally.
#
# No Octave/MATLAB needed — the lanes read tracked CSV vectors. A lane whose
# vector file is missing fails clearly via its own cocotb test (FileNotFound
# -> non-zero make), which is the "a future change forgot the vector" signal;
# the dir->CSV name mapping is intentionally irregular (e.g. turbo_encode_top
# reuses turbo_encoder.csv; rsc_constituent_encoder has no CSV by design), so
# the runner does not hard-map it.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/hdl_env.sh
source "${ROOT_DIR}/scripts/hdl_env.sh"
hdl_env_setup || {
  echo "ERROR: HDL environment not ready (see messages above)." >&2
  exit 127
}

echo "== HDL toolchain =="
ghdl --version 2>&1 | head -1
"${HDL_PYTHON_BIN}" -c "import cocotb; print('cocotb', cocotb.__version__)"
make --version 2>&1 | head -1
echo

mapfile -t LANES < <(find "${ROOT_DIR}/hdl/sim" -mindepth 2 -maxdepth 2 \
  -name Makefile -printf '%h\n' | sort)

if [[ ${#LANES[@]} -eq 0 ]]; then
  echo "ERROR: no hdl/sim/*/Makefile lanes found." >&2
  exit 1
fi

declare -a FAILED=()
for lane in "${LANES[@]}"; do
  name="$(basename "${lane}")"
  echo "──────── lane: ${name} ────────"
  rm -rf "${lane}/sim_build" "${lane}/results.xml" 2>/dev/null || true
  out="$( cd "${lane}" && make SIM=ghdl 2>&1 )"
  rc=$?
  echo "${out}" | tail -3
  # Pass iff make succeeded AND a cocotb summary with FAIL=0 (and >=1 PASS)
  # is present (guards against a make that exits 0 without running tests).
  if [[ ${rc} -eq 0 ]] \
     && grep -qE 'PASS=[1-9][0-9]* FAIL=0' <<<"${out}" \
     && ! grep -qE 'FAIL=[1-9]' <<<"${out}"; then
    echo "  -> PASS"
  else
    echo "  -> FAIL (rc=${rc})"
    FAILED+=("${name}")
  fi
  echo
done

echo "════════ HDL lane summary ════════"
echo "lanes: ${#LANES[@]}  failed: ${#FAILED[@]}"
if [[ ${#FAILED[@]} -ne 0 ]]; then
  printf '  FAILED: %s\n' "${FAILED[*]}"
  exit 1
fi
echo "  ALL LANES PASS (bit-exact vs committed golden vectors)"
