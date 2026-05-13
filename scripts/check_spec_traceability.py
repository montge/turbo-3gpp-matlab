#!/usr/bin/env python3
"""Spec-to-test traceability check.

Scans `openspec/specs/<capability>/spec.md` (for the eligible capabilities only)
for `#### Scenario:` blocks and matches each one against a `function test_<name>`
declaration somewhere under `tests/`. Exits 0 when every scenario has at least
one matching test, non-zero otherwise.

The eligible capability set excludes `simulation` (Monte Carlo / plotting drivers
are MATLAB-graphics-bound) and `octave-compatibility` (exercised by
`test_octave_smoke.m`).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SPECS_DIR = REPO_ROOT / "openspec" / "specs"
TESTS_DIR = REPO_ROOT / "tests"

ELIGIBLE_CAPABILITIES = {
    "crc",
    "internal-interleaver",
    "turbo-encoder",
    "turbo-decoder",
    "rate-matching",
    "code-block-segmentation",
    "coding-chain",
}

SCENARIO_HEADER_RE = re.compile(r"^#### Scenario:\s*(.+?)\s*$")
TEST_FUNCTION_RE = re.compile(r"^\s*function\s+(?:[^=]+=\s*)?(test_[A-Za-z0-9_]+)\b")


def scenario_to_test_name(title: str) -> str:
    """Lower-case, replace non-alphanumerics with underscores, collapse, strip."""
    name = re.sub(r"[^A-Za-z0-9]+", "_", title.lower())
    name = name.strip("_")
    return f"test_{name}"


def collect_scenarios() -> list[tuple[str, str, Path, int]]:
    """Return (capability, scenario_title, spec_path, line_number) tuples."""
    out: list[tuple[str, str, Path, int]] = []
    for spec_path in sorted(SPECS_DIR.glob("*/spec.md")):
        capability = spec_path.parent.name
        if capability not in ELIGIBLE_CAPABILITIES:
            continue
        with spec_path.open() as fh:
            for line_no, line in enumerate(fh, start=1):
                m = SCENARIO_HEADER_RE.match(line)
                if m:
                    out.append((capability, m.group(1), spec_path, line_no))
    return out


def collect_test_names() -> set[str]:
    """Return the set of test function names declared anywhere under tests/."""
    names: set[str] = set()
    if not TESTS_DIR.exists():
        return names
    for path in TESTS_DIR.rglob("*.m"):
        # Skip the vendored MOxUnit submodule -- its own self-tests do not
        # satisfy the source spec.
        if "MOxUnit" in path.parts:
            continue
        with path.open() as fh:
            for line in fh:
                m = TEST_FUNCTION_RE.match(line)
                if m:
                    names.add(m.group(1))
    return names


def main() -> int:
    scenarios = collect_scenarios()
    test_names = collect_test_names()

    unmatched: list[tuple[str, str, str, Path, int]] = []
    matched_count = 0
    for capability, title, spec_path, line_no in scenarios:
        expected = scenario_to_test_name(title)
        if expected in test_names:
            matched_count += 1
        else:
            unmatched.append((capability, title, expected, spec_path, line_no))

    total = len(scenarios)
    print(
        f"Scenario coverage: {matched_count}/{total} matched "
        f"({len(unmatched)} missing) across {len(ELIGIBLE_CAPABILITIES)} "
        "eligible capabilities."
    )
    if unmatched:
        print()
        print("Missing tests:")
        for capability, title, expected, spec_path, line_no in unmatched:
            rel = spec_path.relative_to(REPO_ROOT)
            print(
                f"  {capability:>26}  '{title}'\n"
                f"    expected: function {expected}\n"
                f"    spec    : {rel}:{line_no}"
            )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
