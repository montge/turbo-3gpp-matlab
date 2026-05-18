# Shared HDL simulation environment shim. Source this; do not execute.
#
#   source "$(dirname "$0")/hdl_env.sh"
#   hdl_env_setup || exit $?
#
# Sets ROOT_DIR, OS_KIND, VENV_BIN, PYTHON_BIN, prepends the venv to PATH, and
# on Windows binds GHDL's embedded interpreter to the venv libpython (the
# LIBPYTHON_LOC / PYGPI_PYTHON_BIN / PYTHONPATH knobs). On Linux/macOS the
# venv activates normally and those knobs stay unset, so CI (ubuntu, .venv/bin)
# and the Windows dev host behave identically. Returns non-zero (does not
# exit) when a prerequisite is missing, so callers decide how to fail.

HDL_ENV_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -x "${HDL_ENV_ROOT}/.venv/Scripts/python.exe" ]]; then
  HDL_VENV_BIN="${HDL_ENV_ROOT}/.venv/Scripts"
  HDL_DEFAULT_PYTHON="${HDL_VENV_BIN}/python.exe"
else
  HDL_VENV_BIN="${HDL_ENV_ROOT}/.venv/bin"
  HDL_DEFAULT_PYTHON="${HDL_VENV_BIN}/python"
fi
HDL_PYTHON_BIN="${PYTHON_BIN:-${HDL_DEFAULT_PYTHON}}"

case "$(uname -s 2>/dev/null || echo unknown)" in
  Darwin)               HDL_OS_KIND=macos ;;
  MINGW*|MSYS*|CYGWIN*) HDL_OS_KIND=windows ;;
  Linux)                HDL_OS_KIND=linux ;;
  *)                    HDL_OS_KIND=other ;;
esac

hdl_env_setup() {
  if ! command -v ghdl >/dev/null 2>&1; then
    echo "hdl_env: GHDL not found on PATH" >&2
    return 127
  fi
  if ! command -v make >/dev/null 2>&1; then
    echo "hdl_env: GNU make not found on PATH" >&2
    return 127
  fi
  if [[ ! -x "${HDL_PYTHON_BIN}" ]]; then
    echo "hdl_env: venv python not found at ${HDL_PYTHON_BIN} (create .venv + pip install -r requirements-dev.txt)" >&2
    return 127
  fi
  if ! "${HDL_PYTHON_BIN}" -c "import cocotb" >/dev/null 2>&1; then
    echo "hdl_env: cocotb not importable in ${HDL_PYTHON_BIN}" >&2
    return 127
  fi

  export PATH="${HDL_VENV_BIN}:${PATH}"

  if [[ "${HDL_OS_KIND}" == "windows" ]]; then
    # GHDL embeds Python and does not process the venv pyvenv.cfg; bind the
    # libpython + site-packages explicitly. Inert on POSIX (venv activates).
    export LIBPYTHON_LOC="$("${HDL_PYTHON_BIN}" -m find_libpython)"
    export PYGPI_PYTHON_BIN="${HDL_PYTHON_BIN}"
    export PYTHONPATH="$("${HDL_PYTHON_BIN}" -c "import sysconfig; print(sysconfig.get_path('purelib'))")${PYTHONPATH:+;${PYTHONPATH}}"
  fi
  return 0
}
