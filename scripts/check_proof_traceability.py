#!/usr/bin/env python3
"""Proof-to-OpenSpec traceability check.

Ensures each formal proof source under `proofs/` is explicitly referenced by
repo-relative path in `proofs/traceability.md`. This keeps the traceability
matrix honest when new Lean, TLA+, or Cryptol proof artifacts are added.
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PROOFS_DIR = REPO_ROOT / "proofs"
TRACEABILITY_FILE = PROOFS_DIR / "traceability.md"

PROOF_EXTENSIONS = {".lean", ".tla", ".cry"}
IGNORED_DIRS = {".git", ".lake", "__pycache__", "build"}


def is_ignored(path: Path) -> bool:
    return any(part in IGNORED_DIRS for part in path.relative_to(REPO_ROOT).parts)


def collect_proof_sources() -> list[Path]:
    if not PROOFS_DIR.exists():
        return []
    return sorted(
        path
        for path in PROOFS_DIR.rglob("*")
        if path.is_file()
        and path.suffix in PROOF_EXTENSIONS
        and not is_ignored(path)
    )


def main() -> int:
    if not TRACEABILITY_FILE.exists():
        print(f"ERROR: missing {TRACEABILITY_FILE.relative_to(REPO_ROOT)}")
        return 1

    traceability = TRACEABILITY_FILE.read_text(encoding="utf-8")
    proof_sources = collect_proof_sources()

    missing = [
        path.relative_to(REPO_ROOT).as_posix()
        for path in proof_sources
        if path.relative_to(REPO_ROOT).as_posix() not in traceability
    ]

    referenced = len(proof_sources) - len(missing)
    print(
        f"Proof traceability: {referenced}/{len(proof_sources)} proof source "
        "files referenced in proofs/traceability.md."
    )

    if missing:
        print()
        print("Missing proof traceability rows/references:")
        for rel_path in missing:
            print(f"  {rel_path}")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
