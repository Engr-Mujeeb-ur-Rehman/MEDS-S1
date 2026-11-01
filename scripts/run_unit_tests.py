#!/usr/bin/env python3
# Copyright 2026 Maktab-e-Digital Systems Lahore.
# SPDX-License-Identifier: Apache-2.0
"""Discover, build and run every MEDS-S1 unit testbench.

There is no manifest to maintain: any file matching verif/unit/tb_*.sv is a
testbench, and it is compiled against every package and module under rtl/.
Verilator prunes what the testbench does not instantiate.

A testbench passes when it exits 0 AND prints a line matching "=== PASS".
Requiring both is deliberate: a testbench that compiles, runs and checks nothing
exits 0 too, and that is the failure this catches.

Usage:
    python3 scripts/run_unit_tests.py                # all
    python3 scripts/run_unit_tests.py --tb s1_alu    # one
    python3 scripts/run_unit_tests.py --jobs 4
"""
from __future__ import annotations

import argparse
import concurrent.futures
import pathlib
import re
import shutil
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
RTL = ROOT / "rtl"
UNIT = ROOT / "verif" / "unit"
WAIVERS = ROOT / "verif" / "verilator.vlt"
BUILD = ROOT / "build" / "unit"

PASS_RE = re.compile(r"===\s*PASS", re.I)
CHECKS_RE = re.compile(r"===\s*PASS\s*:\s*(\d+)\s*checks", re.I)


def rtl_sources() -> list[pathlib.Path]:
    """All RTL, packages first -- some tools care about declaration order."""
    files = sorted(RTL.rglob("*.sv"))
    pkgs = [f for f in files if f.name.endswith("_pkg.sv")]
    rest = [f for f in files if not f.name.endswith("_pkg.sv")]
    return pkgs + rest


def run_one(tb: pathlib.Path, srcs: list[pathlib.Path], keep: bool) -> dict:
    name = tb.stem                       # tb_s1_alu
    outdir = BUILD / name
    if outdir.exists() and not keep:
        shutil.rmtree(outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    incdirs = sorted({str(p.parent) for p in srcs})
    cmd = [
        "verilator", "--binary", "--timing", "-Wall",
        "--top-module", name,
        "--Mdir", str(outdir), "-o", name,
        *[f"-I{d}" for d in incdirs],
        str(WAIVERS),
        *[str(p) for p in srcs],
        str(tb),
    ]
    t0 = time.time()
    build = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT)
    if build.returncode != 0:
        return dict(name=name, ok=False, stage="build", checks=0,
                    secs=time.time() - t0, log=build.stderr[-4000:])

    exe = outdir / name
    run = subprocess.run([str(exe)], capture_output=True, text=True, cwd=ROOT,
                         timeout=600)
    out = run.stdout + run.stderr
    ok = run.returncode == 0 and bool(PASS_RE.search(out))
    m = CHECKS_RE.search(out)
    return dict(name=name, ok=ok, stage="run", checks=int(m.group(1)) if m else 0,
                secs=time.time() - t0, log=out[-4000:])


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tb", help="run only testbenches whose name contains this")
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--keep", action="store_true", help="reuse build dirs")
    args = ap.parse_args()

    if not shutil.which("verilator"):
        print("error: verilator not found; see docs/guidelines/ONBOARDING.md")
        return 2

    tbs = sorted(UNIT.glob("tb_*.sv"))
    if args.tb:
        tbs = [t for t in tbs if args.tb in t.stem]
    if not tbs:
        print(f"no testbenches matched under {UNIT.relative_to(ROOT)}")
        return 1

    srcs = rtl_sources()
    print(f"unit tests: {len(tbs)} testbench(es), {len(srcs)} RTL file(s)\n")

    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as ex:
        futs = {ex.submit(run_one, t, srcs, args.keep): t for t in tbs}
        for f in concurrent.futures.as_completed(futs):
            r = f.result()
            results.append(r)
            mark = "PASS" if r["ok"] else "FAIL"
            extra = f'{r["checks"]:>6} checks' if r["checks"] else f'{r["stage"]:>12}'
            print(f'  [{mark}] {r["name"]:<28} {extra}  {r["secs"]:5.1f}s')

    results.sort(key=lambda r: r["name"])
    failed = [r for r in results if not r["ok"]]
    for r in failed:
        print(f'\n--- {r["name"]} ({r["stage"]}) ---\n{r["log"]}')

    total = sum(r["checks"] for r in results)
    print(f'\n{len(results) - len(failed)}/{len(results)} passed, {total} checks total')
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
