#!/usr/bin/env python3
"""Parallel verification gate for all games in games/*:
1. Validates game.json required keys & schema rules
2. Runs `--headless --doctor` (and `--fuzz-seeds 3` for flagships)
3. Runs `--headless --test tests/playtest.lua --seed 42`
"""

import argparse
import concurrent.futures
import json
import os
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ALLOWED_GAME_KEYS = {
    "id", "title", "description", "genre", "flagship", "primitives",
    "engine_version", "entry_script", "initial_scene", "pipeline",
    "touch_preset", "xr_mode", "retro", "default_locale",
}
ALLOWED_PRIMS = {"mesh", "sprite", "voxel", "terrain", "particles", "sdf_text"}


def verify_one_game(engine_bin, slug):
    gdir = os.path.join(ROOT, "games", slug)
    gjson_path = os.path.join(gdir, "game.json")
    if not os.path.isfile(gjson_path):
        return slug, False, "Missing game.json"

    try:
        with open(gjson_path, "r", encoding="utf-8") as f:
            meta = json.load(f)
    except Exception as exc:
        return slug, False, f"Invalid JSON in game.json: {exc}"

    for req in ("id", "title", "engine_version", "entry_script"):
        if req not in meta:
            return slug, False, f"Missing required key '{req}' in game.json"
    extra = set(meta.keys()) - ALLOWED_GAME_KEYS
    if extra:
        return slug, False, f"Disallowed keys in game.json: {sorted(extra)}"
    for p in meta.get("primitives", []):
        if p not in ALLOWED_PRIMS:
            return slug, False, f"Invalid primitive '{p}' in game.json"

    env = os.environ.copy()
    env["SDL_VIDEODRIVER"] = "dummy"
    env["SDL_AUDIODRIVER"] = "dummy"

    rel_game = f"games/{slug}"
    doc_cmd = [engine_bin, "--repo-root", ROOT, "--headless", "--doctor", "--game", rel_game]
    if meta.get("flagship"):
        doc_cmd.extend(["--fuzz-seeds", "3"])

    r_doc = subprocess.run(doc_cmd, cwd=ROOT, env=env, capture_output=True, text=True, timeout=30)
    if r_doc.returncode != 0:
        return slug, False, f"--doctor failed:\n{r_doc.stdout}\n{r_doc.stderr}"

    pt_cmd = [engine_bin, "--repo-root", ROOT, "--headless", "--game", rel_game, "--test", "tests/playtest.lua", "--seed", "42"]
    r_pt = subprocess.run(pt_cmd, cwd=ROOT, env=env, capture_output=True, text=True, timeout=30)

    # Clean up any runtime save artifacts created during playtest
    for fn in os.listdir(gdir):
        if fn.endswith(".engsave"):
            try:
                os.remove(os.path.join(gdir, fn))
            except OSError:
                pass
    saves_sub = os.path.join(gdir, "saves")
    if os.path.isdir(saves_sub):
        shutil.rmtree(saves_sub, ignore_errors=True)

    if r_pt.returncode != 0:
        return slug, False, f"playtest.lua failed:\n{r_pt.stdout}\n{r_pt.stderr}"

    return slug, True, "OK"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("engine_bin", help="Path to compiled engine executable")
    ap.add_argument("--expect-count", type=int, default=0, help="Require at least N games")
    args = ap.parse_args()

    engine_bin = os.path.abspath(args.engine_bin)
    games_dir = os.path.join(ROOT, "games")
    slugs = sorted(d for d in os.listdir(games_dir) if os.path.isdir(os.path.join(games_dir, d))) if os.path.isdir(games_dir) else []

    if args.expect_count and len(slugs) < args.expect_count:
        print(f"[FAIL] Expected >= {args.expect_count} games, found {len(slugs)}", file=sys.stderr)
        sys.exit(1)

    t0 = time.time()
    failures = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(16, max(1, os.cpu_count() or 4))) as pool:
        for slug, ok, msg in pool.map(lambda s: verify_one_game(engine_bin, s), slugs):
            if not ok:
                failures.append((slug, msg))
                print(f"[FAIL] {slug}: {msg}", file=sys.stderr)

    dt = time.time() - t0
    if failures:
        print(f"\n[FAIL] {len(failures)}/{len(slugs)} games failed verification in {dt:.2f}s.", file=sys.stderr)
        sys.exit(1)

    print(f"[PASS] All {len(slugs)}/{len(slugs)} games passed schema, --doctor, and headless playtest in {dt:.2f}s!")


if __name__ == "__main__":
    main()
