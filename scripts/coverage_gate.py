#!/usr/bin/env python3
"""Parse MOcov's Cobertura XML, write an LCOV-style summary, gate at threshold.

Usage:
    scripts/coverage_gate.py --xml <path> --summary <path> --threshold <int>

Exit codes:
    0   coverage was measured and is >= threshold
    1   coverage is below threshold (largest contributors are also reported)
    2   the XML could not be parsed or no source files were measured
"""

from __future__ import annotations

import argparse
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--xml", required=True)
    parser.add_argument("--summary", required=True)
    parser.add_argument("--threshold", type=float, required=True)
    args = parser.parse_args()

    xml_path = Path(args.xml)
    summary_path = Path(args.summary)
    threshold = float(args.threshold)

    if not xml_path.exists():
        print(f"ERROR: coverage XML not found at {xml_path}", file=sys.stderr)
        return 2

    try:
        tree = ET.parse(xml_path)
    except ET.ParseError as exc:
        print(f"ERROR: failed to parse {xml_path}: {exc}", file=sys.stderr)
        return 2

    root = tree.getroot()

    # Walk every <class> element; each represents one source .m file.
    files: list[tuple[str, int, int]] = []  # (filename, lines_covered, lines_total)
    for cls in root.iter("class"):
        filename = cls.attrib.get("filename") or cls.attrib.get("name") or "?"
        lines = list(cls.iter("line"))
        if not lines:
            continue
        total = len(lines)
        covered = sum(1 for ln in lines if int(ln.attrib.get("hits", "0")) > 0)
        files.append((filename, covered, total))

    if not files:
        print("ERROR: no measured source files found in coverage XML",
              file=sys.stderr)
        return 2

    total_lines = sum(t for _, _, t in files)
    covered_lines = sum(c for _, c, _ in files)
    pct = 100.0 * covered_lines / total_lines if total_lines > 0 else 0.0

    # Sort by missed lines descending (largest contributors to the uncovered set
    # come first).
    by_missed = sorted(files, key=lambda r: (r[2] - r[1]), reverse=True)

    lines_out: list[str] = []
    lines_out.append("Line coverage summary (produced from MOcov Cobertura XML)")
    lines_out.append(f"  total           : {covered_lines:5d} / {total_lines:5d} "
                     f"({pct:6.2f}%)")
    lines_out.append(f"  threshold       : {threshold:6.2f}%")
    lines_out.append(f"  files measured  : {len(files)}")
    lines_out.append("")
    lines_out.append("Per-file (sorted by missed lines, largest contributors first):")
    lines_out.append(f"  {'covered':>7} {'total':>7} {'pct':>6}  filename")
    for filename, covered, total in by_missed:
        file_pct = 100.0 * covered / total if total > 0 else 100.0
        lines_out.append(
            f"  {covered:>7} {total:>7} {file_pct:5.1f}%  {filename}"
        )

    summary = "\n".join(lines_out) + "\n"
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.write_text(summary)
    sys.stdout.write(summary)

    if pct + 1e-9 < threshold:
        print(f"\nFAIL: line coverage {pct:.2f}% is below the {threshold:.2f}% "
              f"threshold. Largest contributors to the uncovered set are listed "
              f"above.")
        return 1
    print(f"\nOK: line coverage {pct:.2f}% >= threshold {threshold:.2f}%.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
