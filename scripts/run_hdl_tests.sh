#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-${ROOT_DIR}/.venv/bin/python}"

if ! command -v ghdl >/dev/null 2>&1; then
  cat >&2 <<'MSG'
GHDL is required for HDL simulation.
Install it with Homebrew on macOS:
  brew install ghdl
MSG
  exit 127
fi

if [[ ! -x "${PYTHON_BIN}" ]]; then
  cat >&2 <<MSG
Python virtualenv not found at ${PYTHON_BIN}.
Create the local Python 3.13 environment and install cocotb:
  python3.13 -m venv .venv
  . .venv/bin/activate
  python -m pip install -r requirements-dev.txt
MSG
  exit 127
fi

if ! "${PYTHON_BIN}" -c "import cocotb" >/dev/null 2>&1; then
  cat >&2 <<MSG
cocotb is not installed in ${PYTHON_BIN}.
Install HDL test dependencies:
  . .venv/bin/activate
  python -m pip install -r requirements-dev.txt
MSG
  exit 127
fi

if ! command -v make >/dev/null 2>&1; then
  cat >&2 <<'MSG'
make is required for the cocotb/GHDL test harness.
Install the Xcode command line tools on macOS:
  xcode-select --install
MSG
  exit 127
fi

export PATH="${ROOT_DIR}/.venv/bin:${PATH}"

(
  cd "${ROOT_DIR}/hdl/sim/crc8"
  make SIM=ghdl
)

echo "Wrote ${ROOT_DIR}/hdl/sim/crc8/crc8_parallel.vcd"

