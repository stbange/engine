#!/usr/bin/env python3
"""Smoke-test the packaged Emscripten WebAssembly & WebGL2 bundle (dist/) in real headless Chrome."""

import functools
import http.server
import os
import shutil
import subprocess
import sys
import tempfile
import threading

SMOKE_SLUGS = [
    "001_catacomb_blitz",
    "008_clockwork_manor",
    "009_voxel_rail_tycoon",
    "101_giant_cleaner_mech",
]

FATAL_MARKERS = (
    "TypeError:",
    "ReferenceError:",
    "SyntaxError:",
    "RuntimeError:",
    "Aborted(",
    "Load Error:",
    "Boot failed",
)


def find_chrome():
    for name in ("google-chrome", "google-chrome-stable", "chromium", "chromium-browser"):
        p = shutil.which(name)
        if p:
            return p
    return None


def main():
    dist_dir = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "dist")
    chrome = find_chrome()
    if not chrome:
        print("[SKIP] No Chrome/Chromium binary found for web smoke test")
        return 0

    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=dist_dir)
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    port = srv.server_address[1]
    threading.Thread(target=srv.serve_forever, daemon=True).start()

    try:
        with tempfile.TemporaryDirectory() as tmp:
            for slug in SMOKE_SLUGS:
                out_png = os.path.join(tmp, f"{slug}.png")
                url = f"http://127.0.0.1:{port}/play.html?game={slug}"
                cmd = [
                    chrome, "--headless=new", "--no-sandbox", "--disable-dev-shm-usage",
                    "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
                    "--enable-webgl", "--ignore-gpu-blocklist", "--window-size=960,600",
                    "--virtual-time-budget=4000", "--enable-logging=stderr",
                    f"--screenshot={out_png}", url,
                ]
                res = subprocess.run(cmd, capture_output=True, text=True, timeout=45)
                console_lines = [ln for ln in (res.stderr or "").splitlines() if "CONSOLE" in ln]
                for ln in console_lines:
                    if any(m in ln for m in FATAL_MARKERS):
                        print(f"[WEB FAIL] {slug}: {ln}", file=sys.stderr)
                        return 1
                if not os.path.isfile(out_png) or os.path.getsize(out_png) < 8192:
                    print(f"[WEB FAIL] {slug}: missing or blank screenshot", file=sys.stderr)
                    return 1
                print(f"[WEB PASS] {slug} rendered cleanly in headless Chrome ({os.path.getsize(out_png)} bytes)")
    finally:
        srv.shutdown()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
