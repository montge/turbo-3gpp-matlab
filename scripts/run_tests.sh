#!/usr/bin/env bash
# scripts/run_tests.sh -- Run the MOxUnit test suite under GNU Octave.
#
# Usage: scripts/run_tests.sh [tests_dir]
#
# Exits 0 on success, non-zero on any test failure.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Two test trees (kept separate from the vendored framework so MOxUnit's
# recursive discovery doesn't try to instantiate its own files as tests):
#   tests/unit/      -- per-source unit tests
#   tests/property/  -- property-based tests with fixed seeds
TESTS_UNIT="${REPO_ROOT}/tests/unit"
TESTS_PROPERTY="${REPO_ROOT}/tests/property"
MOXUNIT_DIR="${REPO_ROOT}/tests/MOxUnit/MOxUnit"

if [[ ! -d "${MOXUNIT_DIR}" ]]; then
    echo "MOxUnit not found at ${MOXUNIT_DIR}." >&2
    echo "Did you forget to initialize submodules? Try: git submodule update --init --recursive" >&2
    exit 1
fi

cd "${REPO_ROOT}"

# Suppress the latin-1 UTF-8 warnings from (c) marks in existing copyright headers.
# moxunit_runtests returns true on success; we exit ~success.
octave --no-gui --eval "
    warning('off', 'all');
    addpath('${REPO_ROOT}');
    addpath(genpath('${MOXUNIT_DIR}'));
    ok = true;
    if exist('${TESTS_UNIT}', 'dir') == 7
        addpath('${TESTS_UNIT}');
        ok = moxunit_runtests('${TESTS_UNIT}', '-recursive', '-verbose') && ok;
    end
    if exist('${TESTS_PROPERTY}', 'dir') == 7
        addpath('${TESTS_PROPERTY}');
        ok = moxunit_runtests('${TESTS_PROPERTY}', '-recursive', '-verbose') && ok;
    end
    exit(~ok);
"
