#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/sim_build/smoke"

if ! command -v ghdl >/dev/null 2>&1; then
  cat >&2 <<'MSG'
GHDL is required for HDL smoke tests.
Install it with Homebrew on macOS:
  brew install ghdl
MSG
  exit 127
fi

mkdir -p "${BUILD_DIR}"

(
  cd "${BUILD_DIR}"
  ghdl -a --std=08 "${ROOT_DIR}/hdl/smoke/and2.vhdl" "${ROOT_DIR}/hdl/smoke/tb_and2.vhdl"
  ghdl -e --std=08 tb_and2
  ghdl -r --std=08 tb_and2 --vcd=and2.vcd --stop-time=5ns
)

echo "Wrote ${BUILD_DIR}/and2.vcd"

