#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Detect the virtualenv layout: POSIX venvs use .venv/bin, Windows venvs
# (incl. Git Bash) use .venv/Scripts. Prefer whichever exists so the same
# script works on macOS, Linux, and Windows.
if [[ -x "${ROOT_DIR}/.venv/Scripts/python.exe" ]]; then
  VENV_BIN="${ROOT_DIR}/.venv/Scripts"
  DEFAULT_PYTHON="${VENV_BIN}/python.exe"
else
  VENV_BIN="${ROOT_DIR}/.venv/bin"
  DEFAULT_PYTHON="${VENV_BIN}/python"
fi
PYTHON_BIN="${PYTHON_BIN:-${DEFAULT_PYTHON}}"

case "$(uname -s 2>/dev/null || echo unknown)" in
  Darwin)              OS_KIND=macos ;;
  MINGW*|MSYS*|CYGWIN*) OS_KIND=windows ;;
  Linux)               OS_KIND=linux ;;
  *)                   OS_KIND=other ;;
esac

ghdl_hint() {
  case "${OS_KIND}" in
    macos)   echo "  brew install ghdl" ;;
    windows) echo "  winget install --id ghdl.ghdl.ucrt64.mcode -e" ;;
    linux)   echo "  apt-get install ghdl   # or your distro's package" ;;
    *)       echo "  see https://ghdl.github.io for install options" ;;
  esac
}

make_hint() {
  case "${OS_KIND}" in
    macos)   echo "  xcode-select --install" ;;
    windows) echo "  winget install --id ezwinports.make -e" ;;
    linux)   echo "  apt-get install make" ;;
    *)       echo "  install GNU make from your platform's package manager" ;;
  esac
}

if ! command -v ghdl >/dev/null 2>&1; then
  {
    echo "GHDL is required for HDL simulation. Install it with:"
    ghdl_hint
  } >&2
  exit 127
fi

if [[ ! -x "${PYTHON_BIN}" ]]; then
  cat >&2 <<MSG
Python virtualenv not found at ${PYTHON_BIN}.
Create the local Python 3.13 environment and install cocotb:
  py -3.13 -m venv .venv   # Windows; use python3.13 on macOS/Linux
  "${PYTHON_BIN}" -m pip install -r requirements-dev.txt
MSG
  exit 127
fi

if ! "${PYTHON_BIN}" -c "import cocotb" >/dev/null 2>&1; then
  cat >&2 <<MSG
cocotb is not installed in ${PYTHON_BIN}.
Install HDL test dependencies:
  "${PYTHON_BIN}" -m pip install -r requirements-dev.txt
MSG
  exit 127
fi

if ! command -v make >/dev/null 2>&1; then
  {
    echo "make is required for the cocotb/GHDL test harness. Install it with:"
    make_hint
  } >&2
  exit 127
fi

export PATH="${VENV_BIN}:${PATH}"

# On Windows, GHDL embeds Python directly and does not process the venv's
# pyvenv.cfg, so the embedded interpreter cannot import cocotb/pygpi from the
# venv. Bind the libpython explicitly and put the venv site-packages on
# PYTHONPATH so the embedded interpreter resolves cocotb. These are
# cocotb-documented knobs and are not set on POSIX, where the venv activates
# normally (preserving the existing macOS/Linux behavior).
if [[ "${OS_KIND}" == "windows" ]]; then
  export LIBPYTHON_LOC="$("${PYTHON_BIN}" -m find_libpython)"
  export PYGPI_PYTHON_BIN="${PYTHON_BIN}"
  export PYTHONPATH="$("${PYTHON_BIN}" -c "import sysconfig; print(sysconfig.get_path('purelib'))")${PYTHONPATH:+;${PYTHONPATH}}"
fi

(
  cd "${ROOT_DIR}/hdl/sim/crc8"
  make SIM=ghdl
)

echo "Wrote ${ROOT_DIR}/hdl/sim/crc8/crc8_parallel.vcd"
