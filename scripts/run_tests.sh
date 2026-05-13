#!/usr/bin/env bash
# Run the MOxUnit test suite under Octave.
# Exits non-zero on any test failure or on an Octave execution error.
#
# Discovery is non-recursive across two explicit directories — the unit tests
# under tests/ and the property-based tests under tests/property/ — so the
# vendored MOxUnit submodule at tests/MOxUnit/ is not picked up by discovery
# (MOxUnit's own self-tests assume an independent bootstrap).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [ ! -d tests/MOxUnit/MOxUnit ]; then
    echo "tests/MOxUnit submodule is not populated." >&2
    echo "Run: git submodule update --init --recursive" >&2
    exit 2
fi

OCTAVE_BIN="${OCTAVE_BIN:-octave}"

"$OCTAVE_BIN" --no-gui --quiet --eval "
    warning('off', 'all');
    addpath(pwd);
    addpath('tests/MOxUnit/MOxUnit');
    moxunit_set_path();
    success = moxunit_runtests('tests', 'tests/property', '-verbose');
    if success
        exit(0);
    else
        exit(1);
    end
"
