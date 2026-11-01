#!/usr/bin/env python3
# Copyright 2026 Maktab-e-Digital Systems Lahore.
# SPDX-License-Identifier: Apache-2.0
"""Documentation gates (NFR-7, CODING_STANDARD R-D3).

Every RTL module must have a page in docs/modules/.  CI checks that the page
exists and is not still the untouched template; a reviewer checks that it says
something true.  Presence is mechanical, quality is human -- do not confuse the
two.

Skeleton modules are exempt until they are implemented: a page describing an
empty module is noise.  A module is a skeleton if its header carries
[SKELETON ...] or the file has no `always`/`assign` outside its port list.
"""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MODDOCS = ROOT / "docs" / "modules"

TEMPLATE_MARKERS = ("One paragraph: what this module does",
                    "SKELETON / WIP / COMPLETE")


def is_skeleton(text: str) -> bool:
    if re.search(r"\[\s*SKELETON", text, re.I):
        return True
    # Strip block comments (DOTALL) and line comments (NOT dotall -- with
    # re.S a `//` would swallow the rest of the file).
    body = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    body = re.sub(r"//[^\n]*", "", body)
    return not re.search(r"\b(always_ff|always_comb|assign)\b", body)


def main() -> int:
    problems: list[str] = []
    modules = []
    for f in sorted(ROOT.rglob("rtl/**/*.sv")):
        if "generated" in f.parts or f.name.endswith("_pkg.sv"):
            continue
        text = f.read_text(errors="replace")
        if not re.search(r"^\s*module\s+", text, re.M):
            continue
        modules.append((f, text))

    for f, text in modules:
        rel = f.relative_to(ROOT)
        page = MODDOCS / f"{f.stem}.md"
        if is_skeleton(text):
            continue
        if not page.exists():
            problems.append(f"{rel}: no docs/modules/{f.stem}.md (R-D3, NFR-7)")
            continue
        doc = page.read_text(errors="replace")
        if any(m in doc for m in TEMPLATE_MARKERS):
            problems.append(f"docs/modules/{f.stem}.md: still the unedited template (R-D3)")
        if len(doc.split()) < 60:
            problems.append(f"docs/modules/{f.stem}.md: too short to be a contract (R-D3)")

    implemented = sum(1 for _, t in modules if not is_skeleton(t))
    print(f"documentation gate: {len(modules)} module(s), "
          f"{implemented} implemented, {len(problems)} problem(s)")
    for p in problems:
        print(f"  {p}")
    if problems:
        print("\nSee docs/modules/TEMPLATE.md for the required shape.")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
