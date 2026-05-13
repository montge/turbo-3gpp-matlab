#!/usr/bin/env bash
# Run the MOxUnit test suite under Octave with MOcov coverage instrumentation.
# Writes:
#   tests/coverage.xml  -- Cobertura XML produced by MOcov
#   tests/coverage.txt  -- LCOV-style human-readable summary produced by
#                          scripts/coverage_gate.py (covers the 90% gate too)
# Exits non-zero on any test failure, any coverage-XML read error, or when the
# coverage gate (default 90 %) is missed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [ ! -d tests/MOxUnit/MOxUnit ]; then
    echo "tests/MOxUnit submodule is not populated." >&2
    echo "Run: git submodule update --init --recursive" >&2
    exit 2
fi
if [ ! -d tests/MOcov/MOcov ]; then
    echo "tests/MOcov submodule is not populated." >&2
    echo "Run: git submodule update --init --recursive" >&2
    exit 2
fi

OCTAVE_BIN="${OCTAVE_BIN:-octave}"
COVERAGE_THRESHOLD="${COVERAGE_THRESHOLD:-90}"

"$OCTAVE_BIN" --no-gui --quiet --eval "
    warning('off', 'all');
    repo_root = pwd();
    addpath(repo_root);
    addpath(fullfile(repo_root, 'tests', 'MOxUnit', 'MOxUnit'));
    addpath(fullfile(repo_root, 'tests', 'MOcov', 'MOcov'));
    moxunit_set_path();
    % Change pwd to a fresh, unique tempname() subdirectory so the implicit
    % '.' path entry does not shadow MOcov's rewritten files. Using
    % tempname() (and removing it on exit) guards against stale instrumented
    % files left behind by prior runs on the same runner.
    cov_pwd = tempname();
    mkdir(cov_pwd);
    cleanup_cov_pwd = onCleanup(@() rmdir(cov_pwd, 's'));
    cd(cov_pwd);
    % Run only the unit tests (not tests/property/*) under instrumentation.
    % Property tests sweep random parameters and add ~6-10 minutes under
    % instrumentation without exercising any source lines that the unit
    % tests do not already hit. The full suite, including property tests,
    % is exercised by scripts/run_tests.sh.
    success = moxunit_runtests( ...
        fullfile(repo_root, 'tests'), ...
        '-verbose', ...
        '-with_coverage', ...
        '-cover', repo_root, ...
        '-cover_exclude', 'tests', ...
        '-cover_exclude', '[+]matlab', ...
        '-cover_exclude', 'plot_BLER_vs_SNR.m', ...
        '-cover_exclude', 'plot_SNR_vs_A.m', ...
        '-cover_exclude', 'node_modules', ...
        '-cover_exclude', 'openspec', ...
        '-cover_exclude', 'scripts', ...
        '-cover_exclude', 'test_octave_smoke.m', ...
        '-cover_xml_file', fullfile(repo_root, 'tests', 'coverage.xml'));
    if success
        exit(0);
    else
        exit(1);
    end
"

if [ ! -s tests/coverage.xml ]; then
    echo "ERROR: tests/coverage.xml was not produced or is empty." >&2
    echo "Check the Octave step above for MOcov errors." >&2
    exit 3
fi

python3 scripts/coverage_gate.py \
    --xml tests/coverage.xml \
    --summary tests/coverage.txt \
    --threshold "$COVERAGE_THRESHOLD"
