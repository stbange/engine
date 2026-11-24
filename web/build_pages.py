#!/usr/bin/env python3
"""Package the shared Emscripten WebAssembly engine, unbaked Lua/assets/mods,
per-game VFS manifests, optional OpenGL 2x2 contact-sheet thumbnails, and the
interactive 100-game GitHub Pages overview (dist/index.html)."""

import argparse
import concurrent.futures
import json
import os
import shutil
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def list_rel_files(base_root, rel_dir):
    out = []
    abs_dir = os.path.join(base_root, rel_dir)
    if not os.path.isdir(abs_dir):
        return out
    for dp, dns, fns in os.walk(abs_dir):
        dns[:] = [d for d in sorted(dns) if d not in ("saves", "user_saves", "__pycache__")]
        for fn in sorted(fns):
            if fn.endswith((".engsave", ".tmp.png", ".pyc")):
                continue
            full = os.path.join(dp, fn)
            out.append(os.path.relpath(full, base_root).replace("\\", "/"))
    return out


def copy_rel_files(base_root, out_dir, rel_files):
    for rel in rel_files:
        src = os.path.join(base_root, rel)
        dst = os.path.join(out_dir, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)


def detect_tags(meta, lua_src):
    tags = []
    if meta.get("flagship"):
        tags.append("flagship")
    for p in meta.get("primitives", []):
        tags.append(p)
    if "portal." in lua_src or "space." in lua_src:
        tags.append("portals")
    if "procgen" in lua_src:
        tags.append("procgen")
    if meta.get("pipeline") == "deferred":
        tags.append("deferred")
    xr = meta.get("xr_mode", "diorama")
    tags.append(f"xr:{xr}")
    return sorted(set(tags))


def capture_one_thumb(engine_bin, slug, out_png):
    gdir = os.path.join(ROOT, "games", slug)
    env = os.environ.copy()
    env["SDL_AUDIODRIVER"] = "dummy"
    cmd = [
        engine_bin, "--repo-root", ROOT, "--game", f"games/{slug}",
        "--width", "200", "--height", "150", "--max-frames", "3",
        "--seed", "42", "--capture-sheet", out_png,
    ]
    if not env.get("DISPLAY"):
        cmd.append("--headless")
    r = subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True, timeout=30)
    for fn in os.listdir(gdir):
        if fn.endswith(".engsave"):
            try:
                os.remove(os.path.join(gdir, fn))
            except OSError:
                pass
    saves_sub = os.path.join(gdir, "saves")
    if os.path.isdir(saves_sub):
        shutil.rmtree(saves_sub, ignore_errors=True)
    return r.returncode == 0 and os.path.isfile(out_png)


def build_index_html(games_meta):
    cards_json = json.dumps(games_meta, separators=(",", ":"))
    total = len(games_meta)
    flagships = sum(1 for g in games_meta if g.get("flagship"))
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Engine (stbange/engine) — {total} Playable Retro 3D, Voxel, Portal &amp; WebXR Games</title>
  <style>
    :root {{
      --bg:#0a0d14; --card:#131926; --card-hi:#192234; --border:#253147;
      --accent:#4be3b0; --accent2:#6cb6ff; --gold:#f2cc60; --text:#e6edf3; --muted:#8b949e;
    }}
    * {{ box-sizing:border-box; }}
    body {{ margin:0; background:var(--bg); color:var(--text); font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif; line-height:1.45; }}
    header {{ max-width:1280px; margin:0 auto; padding:36px 20px 20px; border-bottom:1px solid var(--border); }}
    h1 {{ margin:0 0 8px; font-size:28px; letter-spacing:-0.02em; }}
    h1 span {{ color:var(--accent); }}
    .sub {{ color:var(--muted); max-width:920px; margin:0 0 16px; font-size:15px; }}
    .clone-box {{ background:#0f141f; border:1px solid var(--border); border-radius:8px; padding:10px 14px; font-family:ui-monospace,SFMono-Regular,Menlo,monospace; font-size:13px; color:var(--accent2); display:inline-block; max-width:100%; overflow-x:auto; margin-bottom:14px; }}
    .toolbar {{ max-width:1280px; margin:18px auto; padding:0 20px; display:flex; flex-wrap:wrap; gap:10px; align-items:center; }}
    #search {{ flex:1; min-width:220px; background:var(--card); color:var(--text); border:1px solid var(--border); border-radius:6px; padding:9px 12px; font-size:14px; }}
    .chip {{ background:var(--card); color:var(--muted); border:1px solid var(--border); border-radius:999px; padding:6px 13px; font-size:12px; font-weight:600; cursor:pointer; }}
    .chip.active, .chip:hover {{ border-color:var(--accent); color:var(--accent); background:#112925; }}
    #count-lbl {{ color:var(--muted); font-size:13px; margin-left:auto; }}
    .grid {{ max-width:1280px; margin:0 auto 56px; padding:0 20px; display:grid; grid-template-columns:repeat(auto-fill, minmax(290px, 1fr)); gap:14px; }}
    .card {{ background:var(--card); border:1px solid var(--border); border-radius:10px; overflow:hidden; display:flex; flex-direction:column; justify-content:space-between; transition:transform .12s, border-color .12s; }}
    .card:hover {{ transform:translateY(-2px); border-color:var(--accent); background:var(--card-hi); }}
    .card.flagship {{ border-color:#5a4a22; }}
    .thumb {{ width:100%; aspect-ratio:4/3; background-color:#0c111b; background-repeat:no-repeat; background-size:200% 200%; background-position:0% 0%; border-bottom:1px solid var(--border); position:relative; transition:background-size .2s ease; image-rendering:pixelated; }}
    .card:hover .thumb {{ background-size:100% 100%; }}
    .thumb-hint {{ position:absolute; right:6px; bottom:6px; background:rgba(10,13,20,0.78); color:var(--muted); font-size:10px; padding:2px 6px; border-radius:4px; font-family:ui-monospace,monospace; }}
    .cbody {{ padding:14px; display:flex; flex-direction:column; flex:1; justify-content:space-between; }}
    .cid {{ font-family:ui-monospace,monospace; font-size:11px; color:var(--muted); }}
    .ctitle {{ margin:4px 0 6px; font-size:17px; font-weight:700; display:flex; align-items:center; gap:6px; }}
    .badge-flag {{ background:#3b2e11; color:var(--gold); border:1px solid #755b1e; font-size:10px; padding:1px 6px; border-radius:4px; text-transform:uppercase; }}
    .cdesc {{ color:var(--muted); font-size:13px; margin:0 0 12px; flex:1; }}
    .tags {{ display:flex; flex-wrap:wrap; gap:5px; margin-bottom:12px; }}
    .tag {{ font-size:11px; padding:2px 7px; border-radius:4px; background:#1c2538; color:#9ecbff; font-family:ui-monospace,monospace; }}
    .tag.p {{ background:#142e28; color:var(--accent); }}
    .actions {{ display:flex; gap:8px; flex-wrap:wrap; }}
    .btn-play {{ flex:1; text-align:center; background:var(--accent); color:#071712; text-decoration:none; font-weight:700; font-size:13px; padding:7px 10px; border-radius:6px; }}
    .btn-sec {{ background:#1d2638; color:var(--text); text-decoration:none; font-size:12px; padding:7px 9px; border-radius:6px; border:1px solid var(--border); }}
    .btn-sec:hover {{ border-color:var(--accent2); color:var(--accent2); }}
    footer {{ text-align:center; padding:24px; color:var(--muted); font-size:12px; border-top:1px solid var(--border); }}
  </style>
</head>
<body>
  <header>
    <h1><span>Engine</span> — Agent-First C11 / SDL3 / OpenGL / Lua / WebXR 3D Engine</h1>
    <p class="sub">
      100% pure MIT C11 core + unbaked Lua 5.1 scripts, greedy AO voxels, 8-way sprites, Forward &amp; Deferred PBR/Retro pipelines,
      <b>Bigger-on-the-Inside</b> stencil pocket portals, deterministic <b>Procedural Generation</b> (solvable dungeons, 3D planets, DNA animals, NPCs),
      automatic mobile touch controls, and Stereo WebXR — powering one shared <code>engine.wasm</code> across all <b>{total}</b> games ({flagships} multi-level flagships).
    </p>
    <div class="clone-box">git clone https://github.com/stbange/engine.git &amp;&amp; cmake -B build &amp;&amp; cmake --build build -j</div>
  </header>

  <div class="toolbar">
    <input id="search" type="search" placeholder="Search {total} games by title, genre, portal, voxel, planet, VR..." />
    <button class="chip active" data-filter="all">All ({total})</button>
    <button class="chip" data-filter="flagship">Flagships ({flagships})</button>
    <button class="chip" data-filter="portals">Bigger on the Inside</button>
    <button class="chip" data-filter="procgen">Procedural Gen</button>
    <button class="chip" data-filter="voxel">Voxel</button>
    <button class="chip" data-filter="sprite">Sprites</button>
    <button class="chip" data-filter="deferred">Deferred</button>
    <button class="chip" data-filter="xr6dof">WebXR 6DoF / Cockpit</button>
    <span id="count-lbl"></span>
  </div>

  <main class="grid" id="grid"></main>

  <footer>
    MIT License &bull; <a href="https://github.com/stbange/engine" style="color:#4be3b0">github.com/stbange/engine</a> &bull;
    Hover any thumbnail to inspect its 2&times;2 Multimodal Contact Sheet &bull; Auto Touch HUD on Mobile &bull; WebXR Ready
  </footer>

  <script>
    const GAMES = {cards_json};
    let activeFilter = 'all';
    const grid = document.getElementById('grid');
    const search = document.getElementById('search');
    const countLbl = document.getElementById('count-lbl');

    function esc(s) {{
      return String(s || '').replace(/[&<>"']/g, c => ({{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}}[c]));
    }}

    function render() {{
      const q = search.value.trim().toLowerCase();
      const filtered = GAMES.filter(g => {{
        if (activeFilter === 'flagship' && !g.flagship) return false;
        if (activeFilter === 'portals' && !g.tags.includes('portals')) return false;
        if (activeFilter === 'procgen' && !g.tags.includes('procgen')) return false;
        if (activeFilter === 'voxel' && !g.tags.includes('voxel')) return false;
        if (activeFilter === 'sprite' && !g.tags.includes('sprite')) return false;
        if (activeFilter === 'deferred' && !g.tags.includes('deferred')) return false;
        if (activeFilter === 'xr6dof' && !(g.xr_mode === '6dof' || g.xr_mode === 'cockpit' || g.xr_mode === 'first_person')) return false;
        if (!q) return true;
        const hay = (g.slug + ' ' + g.title + ' ' + g.genre + ' ' + g.description + ' ' + g.tags.join(' ')).toLowerCase();
        return hay.includes(q);
      }});
      countLbl.textContent = filtered.length + ' / ' + GAMES.length + ' shown';
      grid.innerHTML = filtered.map(g => {{
        const flagBadge = g.flagship ? '<span class="badge-flag">Flagship</span>' : '';
        const tHtml = g.tags.map(t => `<span class="tag ${{t==='portals'||t==='procgen'?'p':''}}">${{esc(t)}}</span>`).join('');
        const thumbHtml = g.thumb
          ? `<a href="play.html?game=${{encodeURIComponent(g.slug)}}" class="thumb" style="display:block;background-image:url('thumbs/${{encodeURIComponent(g.slug)}}.png')"><span class="thumb-hint">2&times;2 hover</span></a>`
          : '';
        return `<article class="card ${{g.flagship?'flagship':''}}">
          ${{thumbHtml}}
          <div class="cbody">
            <div>
              <div class="cid">${{esc(g.slug)}} &bull; ${{esc(g.genre)}} &bull; touch:${{esc(g.touch_preset)}}</div>
              <div class="ctitle">${{esc(g.title)}} ${{flagBadge}}</div>
              <p class="cdesc">${{esc(g.description)}}</p>
              <div class="tags">${{tHtml}}</div>
            </div>
            <div class="actions">
              <a class="btn-play" href="play.html?game=${{encodeURIComponent(g.slug)}}">&#9654; Play</a>
              <a class="btn-sec" href="play.html?game=${{encodeURIComponent(g.slug)}}&amp;mod=example_retro_pack" title="Launch with Amber CRT &amp; PS1 Mod">+Mod</a>
              <a class="btn-sec" href="games/${{encodeURIComponent(g.slug)}}/scripts/main.lua" target="_blank">Lua</a>
            </div>
          </div>
        </article>`;
      }}).join('');
    }}

    document.querySelectorAll('.chip').forEach(btn => {{
      btn.onclick = () => {{
        document.querySelectorAll('.chip').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        activeFilter = btn.getAttribute('data-filter');
        render();
      }};
    }});
    search.oninput = render;
    render();
  </script>
</body>
</html>
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wasm-dir", default=os.path.join(ROOT, "build-web"))
    ap.add_argument("--engine-bin", default="", help="Optional native engine binary to render 2x2 gallery thumbnails")
    ap.add_argument("--out-dir", default=os.path.join(ROOT, "dist"))
    args = ap.parse_args()

    out_dir = os.path.abspath(args.out_dir)
    thumbs_dir = os.path.join(out_dir, "thumbs")
    os.makedirs(out_dir, exist_ok=True)
    os.makedirs(os.path.join(out_dir, "manifests"), exist_ok=True)

    # 1. Copy compiled Emscripten runner + player shell
    for fn in ("engine.js", "engine.wasm", "engine.data"):
        src = os.path.join(args.wasm_dir, fn)
        if os.path.isfile(src):
            shutil.copy2(src, os.path.join(out_dir, fn))
    shutil.copy2(os.path.join(ROOT, "web", "shell_play.html"), os.path.join(out_dir, "play.html"))
    with open(os.path.join(out_dir, ".nojekyll"), "w", encoding="utf-8") as f:
        f.write("")

    # 2. Copy shared unbaked runtime files (shaders, lua stdlib, shared assets, mods)
    shared_files = (
        list_rel_files(ROOT, "shaders")
        + list_rel_files(ROOT, "lua/eng")
        + list_rel_files(ROOT, "assets/shared")
    )
    mod_files = list_rel_files(ROOT, "mods/example_retro_pack")
    copy_rel_files(ROOT, out_dir, shared_files + mod_files)

    # 3. Package each game + emit per-game HTTP VFS manifest
    games_root = os.path.join(ROOT, "games")
    slugs = []
    games_meta = []
    if os.path.isdir(games_root):
        for slug in sorted(os.listdir(games_root)):
            gdir = os.path.join(games_root, slug)
            gjson_path = os.path.join(gdir, "game.json")
            if not os.path.isfile(gjson_path):
                continue
            slugs.append(slug)
            with open(gjson_path, "r", encoding="utf-8") as f:
                meta = json.load(f)
            lua_path = os.path.join(gdir, meta.get("entry_script", "scripts/main.lua"))
            lua_src = ""
            if os.path.isfile(lua_path):
                with open(lua_path, "r", encoding="utf-8") as lf:
                    lua_src = lf.read()

            g_files = list_rel_files(ROOT, f"games/{slug}")
            copy_rel_files(ROOT, out_dir, g_files)

            manifest = {
                "id": meta.get("id", slug),
                "title": meta.get("title", slug),
                "files": shared_files + g_files,
                "mod_files": mod_files,
            }
            with open(os.path.join(out_dir, "manifests", f"{slug}.json"), "w", encoding="utf-8") as mf:
                json.dump(manifest, mf, separators=(",", ":"))

            games_meta.append({
                "slug": slug,
                "title": meta.get("title", slug),
                "description": meta.get("description", ""),
                "genre": meta.get("genre", "3d"),
                "flagship": bool(meta.get("flagship", False)),
                "touch_preset": meta.get("touch_preset", "dual_stick"),
                "xr_mode": meta.get("xr_mode", "diorama"),
                "tags": detect_tags(meta, lua_src),
                "thumb": False,
            })

    # 4. Optional parallel OpenGL 2x2 contact-sheet thumbnail rendering
    engine_bin = os.path.abspath(args.engine_bin) if args.engine_bin else ""
    if engine_bin and os.path.isfile(engine_bin) and slugs:
        os.makedirs(thumbs_dir, exist_ok=True)
        with concurrent.futures.ThreadPoolExecutor(max_workers=min(8, max(1, os.cpu_count() or 4))) as pool:
            futs = {
                slug: pool.submit(capture_one_thumb, engine_bin, slug, os.path.join(thumbs_dir, f"{slug}.png"))
                for slug in slugs
            }
            for gm in games_meta:
                gm["thumb"] = bool(futs[gm["slug"]].result())

    # 5. Write interactive overview hub index.html
    with open(os.path.join(out_dir, "index.html"), "w", encoding="utf-8") as f:
        f.write(build_index_html(games_meta))

    thumbs_ok = sum(1 for g in games_meta if g["thumb"])
    print(f"Packaged GitHub Pages bundle in '{out_dir}' with {len(games_meta)} games ({thumbs_ok} thumbnails) and 1 shared engine.wasm.")


if __name__ == "__main__":
    main()
