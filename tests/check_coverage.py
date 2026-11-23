#!/usr/bin/env python3
"""Verify >= 95.0% line coverage on first-party C (src/) and Lua (lua/eng/) code."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

THRESHOLD = 95.0


def parse_lcov(info_path: Path, repo_root: Path) -> dict[str, dict[int, int]]:
    coverage: dict[str, dict[int, int]] = {}
    current_file: str | None = None
    if not info_path.exists():
        return coverage
    for raw in info_path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if line.startswith("SF:"):
            sf = Path(line[3:]).resolve()
            try:
                rel = sf.relative_to(repo_root).as_posix()
            except ValueError:
                rel = None
            current_file = rel
            if current_file and current_file not in coverage:
                coverage[current_file] = {}
        elif line.startswith("DA:") and current_file:
            parts = line[3:].split(",")
            if len(parts) >= 2:
                lineno = int(parts[0])
                hits = int(parts[1])
                prev = coverage[current_file].get(lineno, 0)
                coverage[current_file][lineno] = max(prev, hits)
        elif line == "end_of_record":
            current_file = None
    return coverage


def merge_coverage(target: dict[str, dict[int, int]], src: dict[str, dict[int, int]]) -> None:
    for fname, lines in src.items():
        bucket = target.setdefault(fname, {})
        for lineno, hits in lines.items():
            bucket[lineno] = max(bucket.get(lineno, 0), hits)


def summarize_group(label: str, files: dict[str, dict[int, int]], required: bool) -> bool:
    if not files:
        if required:
            print(f"[FAIL] {label}: no instrumented files found!")
            return False
        print(f"[SKIP] {label}: no files present yet.")
        return True

    total_lines = 0
    hit_lines = 0
    print(f"\n=== {label} Line Coverage ===")
    for fname in sorted(files):
        line_map = files[fname]
        n_total = len(line_map)
        n_hit = sum(1 for h in line_map.values() if h > 0)
        pct = (100.0 * n_hit / n_total) if n_total else 100.0
        total_lines += n_total
        hit_lines += n_hit
        print(f"  {pct:6.2f}% ({n_hit:4d}/{n_total:4d})  {fname}")

    overall = (100.0 * hit_lines / total_lines) if total_lines else 100.0
    status = "PASS" if overall >= THRESHOLD else "FAIL"
    print(f"[{status}] {label} Total: {overall:.2f}% ({hit_lines}/{total_lines}) — required >= {THRESHOLD:.1f}%")
    return overall >= THRESHOLD


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    build_dir = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else (repo_root / "build-cov")
    c_info = build_dir / "c_coverage.info"
    lua_info = build_dir / "lua_coverage.info"

    if not c_info.exists():
        cmd = [
            "lcov",
            "--capture",
            "--directory",
            str(build_dir),
            "--output-file",
            str(c_info),
            "--ignore-errors",
            "mismatch,inconsistent,unused,empty",
        ]
        subprocess.run(cmd, check=True)

    merged: dict[str, dict[int, int]] = {}
    merge_coverage(merged, parse_lcov(c_info, repo_root))
    merge_coverage(merged, parse_lcov(lua_info, repo_root))

    c_files = {k: v for k, v in merged.items() if k.startswith("src/") and k.endswith(".c")}
    lua_files = {k: v for k, v in merged.items() if k.startswith("lua/eng/") and k.endswith(".lua")}
    has_lua_sources = any((repo_root / "lua" / "eng").glob("*.lua"))

    ok_c = summarize_group("First-Party C (src/*.c)", c_files, required=True)
    ok_lua = summarize_group("First-Party Lua (lua/eng/*.lua)", lua_files, required=has_lua_sources)
    return 0 if (ok_c and ok_lua) else 1


if __name__ == "__main__":
    raise SystemExit(main())
