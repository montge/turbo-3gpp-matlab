#!/usr/bin/env bash
# Run MISS_HIT (mh_style + mh_lint + mh_metric) against the repository.
#
# Spec policy (openspec/specs/test-suite/spec.md, MISS_HIT requirement):
#   - mh_style and mh_lint MUST fail CI on *errors*. Style messages and
#     medium-severity lint checks (e.g. shadowing the builtin `pi`) are
#     reported in logs but do NOT fail the build until a separate ratcheting
#     change.
#   - mh_metric runs informational only -- it writes tests/metric.txt and
#     uploads it as a CI artifact but has no failure threshold yet.
#
# mh_style and mh_lint already exit 0 when there are no errors / warnings,
# so we run them with their default behavior and let the exit code propagate.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "== mh_style =="
# --no-style: suppress the 3500+ pedantic style messages (naming scheme,
# copyright notice on test files). Errors and warnings are still shown, and
# the exit code still propagates -- the spec only requires that errors fail
# CI, not that style messages are loud in the log.
mh_style --no-style

echo
echo "== mh_lint =="
mh_lint

echo
echo "== mh_metric =="
mkdir -p tests
mh_metric --text tests/metric.txt
echo "Wrote tests/metric.txt"
