#!/usr/bin/env python3
"""Conformity linter for stbange/engine games.

Audits one or more game directories against the real C11/Lua 5.1 engine
contract (parsed live from src/eng_lua.c & src/eng_procgen.c when available)
and prints concrete, actionable propositions.
"""

import argparse
import glob
import json
import os
import re
import sys

DEFAULT_OPT_KEYS = {
    "eng.render.set_retro": {"vertex_snap", "dither", "color_bits", "fog_density", "fog_color", "fog_height", "bloom", "crt"},
    "eng.scene.set_mesh": {"color", "emissive", "tex", "metallic", "roughness", "cast_shadow", "occluder"},
    "eng.render.add_light": {"type", "pocket", "pos", "dir", "color", "range", "shadow"},
    "eng.render.set_light": {"pos", "dir", "color", "range", "pocket"},
    "eng.physics.add_body": {
        "shape", "motion", "pocket", "radius", "half_height",
        "half_extents", "vel", "restitution", "trigger", "voxel_id",
    },
    "eng.particles.create": {
        "pos", "dir", "rate", "pocket", "tex", "seed", "spread", "speed", "life",
        "color_start", "color_end", "size_start", "size_end", "gravity", "drag", "additive", "cap",
    },
}
DEFAULT_TEX_RECIPES = {
    "stone_brick", "wood_planks", "wood_grain", "grass", "rust_metal",
    "metal_rivets", "sci_fi_panel", "water_caustics", "marble", "lava_cracks", "cobble",
}
DEFAULT_ACTIONS = {
    "left", "right", "up", "down", "jump", "fire", "interact",
    "p1_up", "p1_down", "p1_left", "p1_right", "p1_act",
    "p2_up", "p2_down", "p2_left", "p2_right", "p2_act",
    "p3_up", "p3_down", "p3_left", "p3_right", "p3_act",
    "switch_crew", "toggle_cam",
}
VALID_BODY_SHAPES = {"aabb", "sphere", "capsule", "voxel"}
VALID_BODY_MOTIONS = {"static", "kinematic", "dynamic"}
VALID_ANIMALS = {"quadruped", "biped", "avian", "insectoid", "aquatic", "serpentine"}
VALID_WAVES = {"square", "saw", "triangle", "sine", "noise"}
VALID_XR = {"diorama", "cockpit", "first_person", "6dof"}
VALID_PIPELINES = {"forward", "deferred"}
VALID_GAME_RETRO_KEYS = {
    "vertex_snap", "nearest_textures", "dither_bayer",
    "color_bits", "crt_scanlines", "fog_density", "fog_color", "fog_height", "bloom",
}
# Games whose fixed-target look_at is an intentional diorama/cube/alley focus camera
INTENTIONAL_FOCUS_LOOKAT = {
    "029_voxel_snake_3d",
    "065_magnet_polarity",
    "074_voxel_bowling",
}
# Games that use eng.procgen.dungeon purely as a distant/scenic backdrop, not a walkable maze
SCENIC_DUNGEON_GAMES = {
    "022_magma_riser",
    "030_castle_cannon_siege",
    "041_grid_grimrock",
    "053_traffic_director_3d",
}
# Games whose pocket space is purely a flight/diorama stage without walking through doorways
NON_WALKABLE_PORTAL_GAMES = {
    "003_nebula_wing_6dof",
    "010_prism_sanctum_xr",
}


def find_repo_root(start):
    cur = os.path.abspath(start)
    for _ in range(6):
        if os.path.isfile(os.path.join(cur, "src", "eng_lua.c")):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            break
        cur = parent
    return os.path.abspath(start)


def load_engine_contract(root):
    opt_keys = {k: set(v) for k, v in DEFAULT_OPT_KEYS.items()}
    recipes = set(DEFAULT_TEX_RECIPES)
    actions = set(DEFAULT_ACTIONS)

    lua_c = os.path.join(root, "src", "eng_lua.c")
    if os.path.isfile(lua_c):
        src = open(lua_c, encoding="utf-8").read()
        fn_map = {
            "l_render_retro": "eng.render.set_retro",
            "l_scene_set_mesh": "eng.scene.set_mesh",
            "l_render_add_light": "eng.render.add_light",
            "l_render_set_light": "eng.render.set_light",
            "l_phys_add_body": "eng.physics.add_body",
            "l_part_create": "eng.particles.create",
        }
        for cfn, lfn in fn_map.items():
            m = re.search(rf'static int {cfn}\(lua_State \*L\)\s*\{{(.*?)\n\}}', src, re.S)
            if m:
                parsed = set(re.findall(r'lua_getfield\(\s*L\s*,\s*\d+\s*,\s*"([^"]+)"\s*\)', m.group(1)))
                if parsed:
                    opt_keys[lfn] = parsed
        bound = set(re.findall(r'eng_input_bind_(?:key|mouse_button)\([^,]+,\s*"([^"]+)"', src))
        if bound:
            actions = bound

    proc_c = os.path.join(root, "src", "eng_procgen.c")
    if os.path.isfile(proc_c):
        src = open(proc_c, encoding="utf-8").read()
        parsed_r = set(re.findall(r'strcmp\(\s*recipe\s*,\s*"([^"]+)"\s*\)\s*==\s*0', src))
        if parsed_r:
            parsed_r.add("cobble")  # Explicit fallback comment in eng_procgen_texture
            recipes = parsed_r

    return opt_keys, recipes, actions


def strip_lua_comments(src):
    src = re.sub(r'--\[\[.*?\]\]', lambda m: "\n" * m.group(0).count("\n"), src, flags=re.S)
    return re.sub(r'--[^\n]*', '', src)


def find_calls(code, prefix):
    out = []
    i = 0
    needle = prefix + "("
    while True:
        idx = code.find(needle, i)
        if idx < 0:
            break
        if idx > 0 and (code[idx - 1].isalnum() or code[idx - 1] in "_."):
            i = idx + 1
            continue
        start = idx + len(needle)
        depth = 1
        in_str = None
        j = start
        while j < len(code) and depth > 0:
            ch = code[j]
            if in_str:
                if ch == "\\" and j + 1 < len(code):
                    j += 2
                    continue
                if ch == in_str:
                    in_str = None
            else:
                if ch in ('"', "'"):
                    in_str = ch
                elif ch == "(":
                    depth += 1
                elif ch == ")":
                    depth -= 1
            j += 1
        line = code.count("\n", 0, idx) + 1
        out.append((line, code[start : j - 1]))
        i = j
    return out


def extract_top_table_keys(tbl_src):
    """Extract only top-level `key =` entries from a Lua `{ ... }` literal."""
    brace = 0
    paren = 0
    in_str = None
    buf = []
    for i, ch in enumerate(tbl_src):
        if in_str:
            if ch == "\\" and i + 1 < len(tbl_src):
                continue
            if ch == in_str:
                in_str = None
            continue
        if ch in ('"', "'"):
            in_str = ch
            continue
        if ch == "{":
            brace += 1
            if brace == 1:
                continue
        elif ch == "}":
            brace -= 1
            if brace == 0:
                break
            continue
        elif ch == "(":
            paren += 1
            continue
        elif ch == ")":
            paren = max(0, paren - 1)
            continue
        if brace == 1 and paren == 0:
            buf.append(ch)
    flat = "".join(buf)
    # Match `ident =` where `=` is not `==` and not preceded by `~`, `<`, `>`, `=`
    return re.findall(r'(?:^|[,;\s])([A-Za-z_]\w*)\s*=(?!=)', flat)


def extract_fn_body(code, fn_name):
    m = re.search(rf'(?:^|\n)\s*function\s+{fn_name}\s*\([^)]*\)(.*?)(?=\n(?:local\s+)?function\s|\Z)', code, re.S)
    return m.group(1) if m else ""


def num(s):
    try:
        return float(s.strip())
    except ValueError:
        return None


def audit_game(root, gdir, opt_keys, recipes, actions):
    slug = os.path.basename(gdir)
    findings = []

    def report(sev, rule, line, msg, fix):
        findings.append({
            "slug": slug, "severity": sev, "rule": rule,
            "line": line, "message": msg, "proposal": fix,
        })

    gjson_p = os.path.join(gdir, "game.json")
    main_p = os.path.join(gdir, "scripts", "main.lua")
    if not os.path.isfile(gjson_p) or not os.path.isfile(main_p):
        report("ERROR", "missing-core-files", 0, "Missing game.json or scripts/main.lua",
               "Restore game.json and scripts/main.lua per unbaked folder contract.")
        return findings

    meta = json.load(open(gjson_p, encoding="utf-8"))
    raw = open(main_p, encoding="utf-8").read()
    code = strip_lua_comments(raw)
    lines = raw.splitlines()

    # 1. Option table keys
    for fn, valid in opt_keys.items():
        for ln, arg in find_calls(code, fn):
            bi = arg.find("{")
            if bi >= 0:
                keys = extract_top_table_keys(arg[bi:])
                bad = [k for k in keys if k not in valid]
                if bad:
                    report("ERROR", "unknown-option-key", ln,
                           f"{fn} passes ignored option key(s) {bad}",
                           f"Use only supported keys {sorted(valid)} (or expose the option in src/eng_lua.c).")
            if fn == "eng.physics.add_body" and bi >= 0:
                m_sh = re.search(r'shape\s*=\s*"([^"]+)"', arg[bi:])
                if m_sh and m_sh.group(1) not in VALID_BODY_SHAPES:
                    report("ERROR", "invalid-enum-value", ln,
                           f"add_body uses unsupported shape '{m_sh.group(1)}'",
                           f"Use one of {sorted(VALID_BODY_SHAPES)}.")
                m_mo = re.search(r'motion\s*=\s*"([^"]+)"', arg[bi:])
                if m_mo and m_mo.group(1) not in VALID_BODY_MOTIONS:
                    report("ERROR", "invalid-enum-value", ln,
                           f"add_body uses unsupported motion '{m_mo.group(1)}'",
                           f"Use one of {sorted(VALID_BODY_MOTIONS)}.")

    # 2. String enums
    for ln, arg in find_calls(code, "eng.procgen.texture"):
        m = re.match(r'\s*"([^"]+)"', arg)
        if m and m.group(1) not in recipes:
            report("ERROR", "invalid-enum-value", ln,
                   f"eng.procgen.texture('{m.group(1)}') silently falls back to default cobble",
                   f"Implement '{m.group(1)}' in src/eng_procgen.c or switch to one of {sorted(recipes)}.")
    for ln, arg in find_calls(code, "eng.procgen.animal"):
        m = re.search(r'"([^"]+)"', arg)
        if m and m.group(1) not in VALID_ANIMALS:
            report("ERROR", "invalid-enum-value", ln,
                   f"eng.procgen.animal archetype '{m.group(1)}' unsupported",
                   f"Use one of {sorted(VALID_ANIMALS)}.")
    for ln, arg in find_calls(code, "eng.audio.synth"):
        m = re.match(r'\s*"([^"]+)"', arg)
        if m and m.group(1) not in VALID_WAVES:
            report("ERROR", "invalid-enum-value", ln,
                   f"eng.audio.synth wave '{m.group(1)}' unsupported",
                   f"Use one of {sorted(VALID_WAVES)}.")
    for ln, arg in find_calls(code, "eng.xr.set_mode"):
        m = re.match(r'\s*"([^"]+)"', arg)
        if m and m.group(1) not in VALID_XR:
            report("ERROR", "invalid-enum-value", ln,
                   f"eng.xr.set_mode('{m.group(1)}') unsupported",
                   f"Use one of {sorted(VALID_XR)}.")
    for ln, arg in find_calls(code, "eng.render.set_pipeline"):
        m = re.match(r'\s*"([^"]+)"', arg)
        if m and m.group(1) not in VALID_PIPELINES:
            report("ERROR", "invalid-enum-value", ln,
                   f"eng.render.set_pipeline('{m.group(1)}') unsupported",
                   f"Use one of {sorted(VALID_PIPELINES)}.")

    # 3. Unbound input action names (skip concatenated dynamic strings like `p .. "_up"`)
    for fn in ("eng.input.down", "eng.input.pressed", "eng.input.axis2d"):
        for ln, arg in find_calls(code, fn):
            if ".." in arg:
                continue
            for act in re.findall(r'"([^"]+)"', arg):
                if act not in actions:
                    report("ERROR", "unbound-input-action", ln,
                           f"{fn}('{act}') is not bound to any keyboard/mouse key",
                           f"Use a bound action from {sorted(actions)} or bind '{act}' in src/eng_lua.c.")

    # 4. Non-deterministic RNG & Lua 5.2+ syntax
    for pat, rule, fix in [
        (r'\b(?:math\.random|math\.randomseed|os\.time|os\.clock)\b', "nondeterministic-rng",
         "Use eng.math.rand()/eng.math.range() with explicit seeds."),
        (r'\b(?:table\.unpack|bit32)\b|\bgoto\s+\w+', "lua52-incompatible",
         "Use strict Lua 5.1 + bit.* (unpack, bit.band/bor/lshift)."),
    ]:
        m = re.search(pat, code)
        if m:
            ln = code.count("\n", 0, m.start()) + 1
            report("ERROR", rule, ln, f"Disallowed call/syntax '{m.group(0)}'", fix)

    # 5. Missing assets, description, locale parity
    if not meta.get("description"):
        report("ERROR", "missing-asset-or-locale", 0, "game.json missing 'description'",
               "Add a concise one-line description (powers the built-in H help overlay).")
    if isinstance(meta.get("retro"), dict):
        bad_r = [k for k in meta["retro"] if k not in VALID_GAME_RETRO_KEYS]
        if bad_r:
            report("ERROR", "unknown-option-key", 0, f"game.json retro has unknown keys {bad_r}",
                   f"Use only {sorted(VALID_GAME_RETRO_KEYS)}.")
    en_p = os.path.join(gdir, "locales", "en.json")
    de_p = os.path.join(gdir, "locales", "de.json")
    en_keys = set(json.load(open(en_p, encoding="utf-8")).keys()) if os.path.isfile(en_p) else set()
    de_keys = set(json.load(open(de_p, encoding="utf-8")).keys()) if os.path.isfile(de_p) else set()
    if not en_keys:
        report("ERROR", "missing-asset-or-locale", 0, "Missing locales/en.json",
               "Add locales/en.json with at least a 'title' key.")
    elif de_keys and en_keys != de_keys:
        report("WARN", "missing-asset-or-locale", 0, f"Locale key drift between en.json and de.json",
               "Sync missing keys across locales/en.json and locales/de.json.")
    for ln, arg in find_calls(code, "eng.i18n.t"):
        m = re.match(r'\s*"([^"]+)"', arg)
        if m and en_keys and m.group(1) not in en_keys:
            report("ERROR", "missing-asset-or-locale", ln,
                   f"eng.i18n.t('{m.group(1)}') missing in locales/en.json",
                   f"Add '{m.group(1)}' to locales/en.json and locales/de.json.")
    for fn in ("eng.asset.load_mesh", "eng.asset.load_texture"):
        for ln, arg in find_calls(code, fn):
            m = re.match(r'\s*"([^"]+)"', arg)
            if m:
                vp = m.group(1)
                if not os.path.isfile(os.path.join(root, vp)) and not os.path.isfile(os.path.join(gdir, vp)):
                    report("ERROR", "missing-asset-or-locale", ln,
                           f"{fn}('{vp}') points to nonexistent file",
                           "Fix asset path to an existing file in assets/shared/ or game assets/.")

    # 6. Lifecycle misuse (allocations in update/draw, draw_sprite or ui in update)
    upd_body = extract_fn_body(code, "update")
    drw_body = extract_fn_body(code, "draw")
    for bname, body in (("update", upd_body), ("draw", drw_body)):
        if not body:
            continue
        for leak in (
            "eng.asset.box", "eng.asset.sphere", "eng.asset.cylinder",
            "eng.asset.load_mesh", "eng.asset.load_texture",
            "eng.procgen.texture", "eng.audio.synth",
        ):
            if leak in body:
                report("ERROR", "lifecycle-misuse", 0, f"{leak} called inside {bname}()",
                       f"Cache {leak} once in init() and reuse its handle.")
    if upd_body:
        if "eng.render.draw_sprite" in upd_body:
            report("ERROR", "lifecycle-misuse", 0, "eng.render.draw_sprite called in update()",
                   "Move draw_sprite() calls into draw().")
        if re.search(r'\beng\.ui\.(?:label|bar|button|panel)\b', upd_body):
            report("ERROR", "lifecycle-misuse", 0, "eng.ui.* called in update()",
                   "Move eng.ui.* calls into draw().")

    # 7. Physics & Wall Collision conformity
    has_static = (
        bool(re.search(r'motion\s*=\s*"static"', code))
        or "create_pocket_building" in code
        or "attach_vehicle_interior" in code
        or "create_steerable_vehicle" in code
        or "spawn_dungeon_entity" in code
        or "cut_wall_with_door" in code
    )
    has_slide_or_char = ("eng.physics.slide_move" in code) or ("eng.physics.move_character" in code)
    if "eng.physics.slide_move" in code and not has_static:
        report("ERROR", "slide-move-no-static-bodies", 0,
               "Calls eng.physics.slide_move but registers ZERO static physics colliders",
               "Attach eng.physics.add_body(ent, { shape='aabb', motion='static', half_extents=... }) to arena walls/pillars.")
    if "eng.camera.fps_steer" in code and not has_slide_or_char:
        report("WARN", "fps-missing-wall-collision", 0,
               "Walkable FPS/interior camera uses eng.camera.fps_steer without slide_move or move_character",
               "Attach static colliders to walls/props/cabin and resolve dx, dz with eng.physics.slide_move(...).")
    if ("create_pocket_building" in code or "attach_vehicle_interior" in code) and slug not in NON_WALKABLE_PORTAL_GAMES and not has_slide_or_char:
        report("WARN", "pocket-building-missing-collision", 0,
               "Uses pocket building / vehicle interior helper without slide_move or move_character",
               "Resolve movement through eng.physics.slide_move(...) so solid doorway & perimeter walls block the player.")
    moves_xz = ("S.px =" in code and "S.pz =" in code) and bool(re.search(r'input\.(?:down|pressed|axis2d)\([^)]*"(?:left|right|up|down)"', code))
    has_solid_props = bool(re.search(r'spawn\(\s*"[^"]*(?:wall_pillar|bar_counter|table_|monolith|colosseum_pillar|temple_col|beacon_pillar)', code, re.I))
    if moves_xz and has_solid_props and not has_slide_or_char and slug not in {"024_voxel_bomber", "079_table_tennis_3d"}:
        report("WARN", "walkable-props-missing-collision", 0,
               "Walkable game spawns solid pillars/counters/tables without static colliders or slide_move",
               "Attach static AABB colliders to props and resolve player movement via eng.physics.slide_move(...).")
    if "eng.procgen.dungeon(" in code and slug not in SCENIC_DUNGEON_GAMES:
        if "voxel_id" not in code and "spawn_dungeon_entity" not in code:
            report("ERROR", "dungeon-missing-collider", 0,
                   "Walkable eng.procgen.dungeon missing static voxel wall collider",
                   "Attach eng.physics.add_body(d_ent, { shape='voxel', motion='static', voxel_id=d.voxel_id }).")
        if re.search(r'floor.*set_mesh|set_mesh\([^,]*floor', code, re.I):
            report("ERROR", "coplanar-z-fighting", 0,
                   "Renders separate floor mesh on top of procedural dungeon floor tiles",
                   "Keep floor collider physics-only (remove set_mesh) or offset Y by >= 0.02m.")

    # 8. Collider order & scale mismatch + coplanar top-face Z-fighting in init()
    init_body = extract_fn_body(code, "init")
    if init_body:
        for ln, arg in find_calls(code, "eng.physics.add_body"):
            m_ent = re.match(r'\s*([A-Za-z_][\w\.]*)\s*,', arg)
            ent = m_ent.group(1) if m_ent else ""
            if 'motion = "static"' in arg and ent:
                after = "\n".join(lines[ln : min(len(lines), ln + 5)])
                if re.search(rf'eng\.scene\.set_pos\(\s*{re.escape(ent)}\s*,', after):
                    report("ERROR", "collider-order-or-scale", ln,
                           f"set_pos({ent}) called AFTER static add_body",
                           "Call set_pos/set_pocket BEFORE eng.physics.add_body for static bodies.")
                if re.search(rf'eng\.scene\.set_pocket\(\s*{re.escape(ent)}\s*,', after):
                    report("ERROR", "collider-order-or-scale", ln,
                           f"set_pocket({ent}) called AFTER static add_body",
                           "Call set_pocket BEFORE eng.physics.add_body so the collider lives in the right pocket.")

    # 9. Coplanar sprites at y <= 0
    for ln, arg in find_calls(code, "eng.render.draw_sprite"):
        parts = [p.strip() for p in arg.split(",")]
        if len(parts) >= 2 and re.fullmatch(r'-?0(?:\.0+)?', parts[1]):
            report("WARN", "coplanar-z-fighting", ln, "eng.render.draw_sprite drawn at y=0",
                   "Lift sprite base Y above floor (>= 0.05m).")

    # 10. Camera orbiting, xr_mode/pipeline mismatch, unlit pockets, fake distant interiors, HUD overlap
    for ln, arg in find_calls(code, "eng.camera.look_at"):
        if slug in INTENTIONAL_FOCUS_LOOKAT:
            continue
        parts = [p.strip() for p in arg.split(",")]
        if len(parts) >= 6:
            eye_dyn = any(re.search(r'\bS\.\w+', p) for p in parts[:3])
            tgt_const = all(re.fullmatch(r'-?\d+(?:\.\d+)?', p) for p in parts[3:6])
            if eye_dyn and tgt_const:
                report("WARN", "camera-orbit-or-mismatch", ln,
                       f"look_at({arg}) moves eye around fixed point",
                       "Use eng.camera.fps_steer() + eng.camera.set() or translate both eye and target.")
    m_xr = re.search(r'eng\.xr\.set_mode\(\s*"([^"]+)"\s*\)', code)
    if m_xr and meta.get("xr_mode") and m_xr.group(1) != meta["xr_mode"]:
        report("WARN", "camera-orbit-or-mismatch", 0,
               f"game.json xr_mode='{meta['xr_mode']}' differs from script '{m_xr.group(1)}'",
               "Align game.json xr_mode with eng.xr.set_mode().")
    m_pl = re.search(r'eng\.render\.set_pipeline\(\s*"([^"]+)"\s*\)', code)
    if m_pl and meta.get("pipeline") and m_pl.group(1) != meta["pipeline"]:
        report("WARN", "camera-orbit-or-mismatch", 0,
               f"game.json pipeline='{meta['pipeline']}' differs from script '{m_pl.group(1)}'",
               "Align game.json pipeline with eng.render.set_pipeline().")
    pockets = re.findall(r'register_pocket\(\s*"([^"]+)"\s*\)', code)
    if pockets and "create_steerable_vehicle" not in code and not re.search(r'add_light\(\{[^}]*pocket\s*=', code):
        report("WARN", "unlit-pocket-space", 0,
               f"Registers pocket(s) {pockets} without a pocket-scoped add_light",
               "Add eng.render.add_light({ type='point', pocket=..., ... }) for each interior pocket.")
    if re.search(r'set_pos\([^)]*(?:500|1000|5000|10000)\b', code):
        report("ERROR", "fake-distant-interior", 0, "Entity positioned >= 500m away",
               "Use an isolated pocket space (eng.space.*) centered at (0, 0, 0).")
    for fn, y_idx in (("eng.ui.label", 1), ("eng.render.draw_text", 2)):
        for ln, arg in find_calls(code, fn):
            parts = [p.strip() for p in arg.split(",")]
            if len(parts) > y_idx:
                yv = num(parts[y_idx])
                if yv is not None and yv > 600.0:
                    report("WARN", "hud-overlaps-helpbar", ln,
                           f"{fn} at y={yv} overlaps bottom help bar",
                           "Anchor HUD at top_left/top_right or keep y <= 580.")

    return findings


def main():
    ap = argparse.ArgumentParser(description="Conformity audit for stbange/engine games")
    ap.add_argument("targets", nargs="*", help="Game dir(s) to check (default: all games/*)")
    ap.add_argument("--strict", action="store_true", help="Exit non-zero on WARN as well as ERROR")
    ap.add_argument("--json", action="store_true", help="Emit JSON report")
    args = ap.parse_args()

    root = find_repo_root(os.getcwd())
    opt_keys, recipes, actions = load_engine_contract(root)

    if args.targets:
        dirs = [os.path.abspath(t) for t in args.targets if os.path.isdir(t)]
    else:
        dirs = sorted(d for d in glob.glob(os.path.join(root, "games", "*")) if os.path.isdir(d))

    all_findings = []
    for d in dirs:
        all_findings.extend(audit_game(root, d, opt_keys, recipes, actions))

    errs = [f for f in all_findings if f["severity"] == "ERROR"]
    warns = [f for f in all_findings if f["severity"] == "WARN"]

    if args.json:
        print(json.dumps({"games_checked": len(dirs), "errors": len(errs), "warnings": len(warns), "findings": all_findings}, indent=2))
    else:
        for f in all_findings:
            loc = f":{f['line']}" if f["line"] else ""
            print(f"[{f['severity']}] {f['slug']}{loc} ({f['rule']}): {f['message']}")
            print(f"       -> Propose: {f['proposal']}")
        print(f"\nConformity summary: {len(dirs)} games checked — {len(errs)} error(s), {len(warns)} warning(s).")

    if errs or (args.strict and warns):
        sys.exit(1)


if __name__ == "__main__":
    main()
