#!/usr/bin/env python3
# Copyright 2026 Maktab-e-Digital Systems Lahore.
# SPDX-License-Identifier: Apache-2.0
"""Enforce the MEDS-S1 repository conventions.

This is the anti-entropy tool.  Every rule here exists because breaking it makes
the repository harder for the NEXT contributor to navigate, and no reviewer
reliably catches that by eye across thirty-one parallel projects.

Rules checked (see docs/guidelines/CODING_STANDARD.md for the reasoning):

  S1  every source directory has a README.md
  S2  every .sv and .py file carries an SPDX licence identifier
  S3  RTL module name matches its file name
  S4  RTL modules use the mandated prefixes
  S5  ports use the _i / _o / _io direction suffixes
  S6  no `always @(...)`, `logic` in place of `reg`/`wire`, no `$random`
  S7  no memory array declared outside meds_s1_sram
  S8  every testbench name matches tb_<module>.sv and a module of that name exists
  S9  configs/*.yaml parse and declare the required keys
  S10 no file over the size limit without a waiver

Exit code is the number of violations, capped at 100.

Usage:
    python3 scripts/check_structure.py
    python3 scripts/check_structure.py --fix-readmes   # stub any missing README
"""
from __future__ import annotations

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Directories that must carry a README explaining what goes in them.
README_DIRS = [
    "rtl", "rtl/core", "rtl/cache", "rtl/fabric", "rtl/peripherals",
    "rtl/socket", "rtl/common", "rtl/generated",
    "verif", "verif/unit", "verif/cosim", "verif/riscof", "verif/formal",
    "verif/conformance",
    "sw", "sw/bsp", "sw/apps", "sw/drivers",
    "gen", "configs", "boards", "extensions", "scripts",
    "docs", "docs/guidelines", "docs/modules", "docs/adr",
]

MODULE_PREFIXES = ("s1_", "meds_s1_", "meds_v_", "tb_")
MAX_LINES = 800
SIZE_WAIVER = {"scripts/gen_project_catalogue.py", "scripts/gen_diagrams.py"}

REQUIRED_CONFIG_KEYS = {"name", "isa", "privilege", "backbone", "memory_map"}


class Checker:
    def __init__(self) -> None:
        self.problems: list[tuple[str, str, str]] = []

    def bad(self, rule: str, where: pathlib.Path | str, msg: str) -> None:
        p = where if isinstance(where, str) else str(where.relative_to(ROOT))
        self.problems.append((rule, p, msg))

    # ---------------------------------------------------------------- S1
    def check_readmes(self, fix: bool) -> None:
        for d in README_DIRS:
            path = ROOT / d
            if not path.is_dir():
                continue
            rd = path / "README.md"
            if rd.exists():
                continue
            if fix:
                rd.write_text(
                    f"# `{d}/`\n\n"
                    "**TODO** — state what lives here, what does *not*, how to add "
                    "something, and the definition of done.\n\n"
                    "See `docs/guidelines/CODING_STANDARD.md` R-D1.\n")
                continue
            self.bad("S1", d, "directory has no README.md (R-D1)")

    # ---------------------------------------------------------------- S2
    def check_spdx(self) -> None:
        for f in list(ROOT.rglob("*.sv")) + list(ROOT.rglob("*.py")):
            if self._skip(f):
                continue
            head = f.read_text(errors="replace")[:800]
            if "SPDX-License-Identifier" not in head:
                self.bad("S2", f, "missing SPDX-License-Identifier header (R-D2)")

    # ------------------------------------------------------------ S3/S4/S5
    def check_rtl(self) -> None:
        mod_re = re.compile(r"^\s*module\s+([A-Za-z_][\w$]*)", re.M)
        port_re = re.compile(
            r"^\s*(?:input|output|inout)\b[^;]*?([A-Za-z_]\w*)\s*(?:\[[^\]]*\])?\s*[,)]\s*$")
        for f in sorted(ROOT.rglob("*.sv")):
            if self._skip(f):
                continue
            text = f.read_text(errors="replace")
            mods = mod_re.findall(text)
            if not mods:
                continue                              # package-only file
            if f.stem not in mods:
                self.bad("S3", f, f"no module named '{f.stem}' (found {', '.join(mods)}) (R-N1)")
            for m in mods:
                if not m.startswith(MODULE_PREFIXES):
                    self.bad("S4", f, f"module '{m}' lacks a mandated prefix "
                                      f"{MODULE_PREFIXES} (R-N2)")

            # S5 applies to module PORTS, not to task/function arguments, and
            # only to synthesisable RTL -- a testbench's task signature is not a
            # hardware interface.
            if "verif" in f.parts:
                continue
            depth = 0                                  # task/function nesting
            for line in text.splitlines():
                if re.match(r"\s*(task|function)\b", line):
                    depth += 1
                elif re.match(r"\s*end(task|function)\b", line):
                    depth = max(0, depth - 1)
                if depth:
                    continue
                m = port_re.match(line)
                if not m:
                    continue
                port = m.group(1)
                if port in ("clk_i", "rst_ni"):
                    continue
                if not port.endswith(("_i", "_o", "_io")):
                    self.bad("S5", f, f"port '{port}' lacks _i/_o/_io suffix (R-N3)")

    # ---------------------------------------------------------------- S6/S7
    def check_style(self) -> None:
        banned = [
            (re.compile(r"\balways\s*@\s*\("), "use always_ff/always_comb/always_latch (R-C1)"),
            (re.compile(r"^\s*reg\s+", re.M), "use `logic`, not `reg` (R-C2)"),
            (re.compile(r"^\s*wire\s+", re.M), "use `logic`, not `wire` (R-C2)"),
            (re.compile(r"\$random\b"), "use $urandom, which is seeded reproducibly (R-V4)"),
        ]
        mem_re = re.compile(r"^\s*logic\s*(?:\[[^\]]*\]\s*)+\w+\s*\[[^\]]*\]\s*;", re.M)
        for f in sorted(ROOT.rglob("*.sv")):
            if self._skip(f):
                continue
            text = f.read_text(errors="replace")
            for rx, msg in banned:
                if rx.search(text):
                    self.bad("S6", f, msg)
            if mem_re.search(text) and f.name not in ("meds_s1_sram.sv",):
                if "verif/" not in str(f):
                    self.bad("S7", f, "memory array declared outside meds_s1_sram "
                                      "(INTERFACES.md section 8, R-C5)")

    # ---------------------------------------------------------------- S8
    def check_testbenches(self) -> None:
        modules = {f.stem for f in ROOT.rglob("rtl/**/*.sv")}
        for tb in sorted((ROOT / "verif" / "unit").glob("*.sv")):
            if not tb.name.startswith("tb_"):
                self.bad("S8", tb, "unit testbench must be named tb_<module>.sv (R-V1)")
                continue
            dut = tb.stem[3:]
            if dut not in modules:
                self.bad("S8", tb, f"no RTL module '{dut}' for this testbench (R-V1)")

    # ---------------------------------------------------------------- S9
    def check_configs(self) -> None:
        try:
            import yaml
        except ImportError:
            return
        cfgdir = ROOT / "configs"
        if not cfgdir.is_dir():
            return
        found = list(cfgdir.glob("*.yaml"))
        if not found:
            self.bad("S9", "configs", "no configuration files (SPEC section 5.3)")
        for f in sorted(found):
            try:
                data = yaml.safe_load(f.read_text()) or {}
            except Exception as e:
                self.bad("S9", f, f"YAML does not parse: {e}")
                continue
            missing = REQUIRED_CONFIG_KEYS - set(data)
            if missing:
                self.bad("S9", f, f"missing required keys: {', '.join(sorted(missing))}")

    # ---------------------------------------------------------------- S10
    def check_size(self) -> None:
        for f in list(ROOT.rglob("*.sv")) + list(ROOT.rglob("*.py")):
            if self._skip(f):
                continue
            rel = str(f.relative_to(ROOT))
            if rel in SIZE_WAIVER:
                continue
            n = len(f.read_text(errors="replace").splitlines())
            if n > MAX_LINES:
                self.bad("S10", f, f"{n} lines exceeds the {MAX_LINES}-line limit; "
                                   "split it or add a waiver with a reason (R-C6)")

    @staticmethod
    def _skip(f: pathlib.Path) -> bool:
        parts = set(f.parts)
        return bool(parts & {".git", "build", "__pycache__", "ext", "node_modules"}) \
            or "rtl/generated" in str(f)

    def report(self) -> int:
        if not self.problems:
            print("structure check: OK")
            return 0
        by_rule: dict[str, list] = {}
        for rule, path, msg in self.problems:
            by_rule.setdefault(rule, []).append((path, msg))
        print(f"structure check: {len(self.problems)} violation(s)\n")
        for rule in sorted(by_rule):
            print(f"  [{rule}]")
            for path, msg in sorted(by_rule[rule]):
                print(f"    {path}: {msg}")
            print()
        print("See docs/guidelines/CODING_STANDARD.md for the rule that each code maps to.")
        return min(len(self.problems), 100)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--fix-readmes", action="store_true",
                    help="create a stub README.md in any directory missing one")
    args = ap.parse_args()

    c = Checker()
    c.check_readmes(args.fix_readmes)
    c.check_spdx()
    c.check_rtl()
    c.check_style()
    c.check_testbenches()
    c.check_configs()
    c.check_size()
    return c.report()


if __name__ == "__main__":
    sys.exit(main())
