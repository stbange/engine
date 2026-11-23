#!/usr/bin/env python3
"""Generate pure-MIT shared 3D meshes (.obj), MagicaVoxel (.vox), retro textures (.png),
retro SFX (.wav), and assets/shared/catalog.json with exact metric bounds for LLM agents."""

import json
import math
import os
import struct
import wave
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHARED = os.path.join(ROOT, "assets", "shared")


def write_png(path, w, h, rgba_bytes):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        raw.extend(rgba_bytes[y * w * 4 : (y + 1) * w * 4])

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def write_obj_box_parts(path, boxes):
    """boxes: list of (cx, cy, cz, sx, sy, sz)"""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    lines = ["# MIT procedural shared mesh (+X right, +Y up, -Z forward)"]
    v_off = 1
    faces_def = [
        ((0, 0, 1), [(-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]),
        ((0, 0, -1), [(1, -1, -1), (-1, -1, -1), (-1, 1, -1), (1, 1, -1)]),
        ((1, 0, 0), [(1, -1, 1), (1, -1, -1), (1, 1, -1), (1, 1, 1)]),
        ((-1, 0, 0), [(-1, -1, -1), (-1, -1, 1), (-1, 1, 1), (-1, 1, -1)]),
        ((0, 1, 0), [(-1, 1, 1), (1, 1, 1), (1, 1, -1), (-1, 1, -1)]),
        ((0, -1, 0), [(-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1)]),
    ]
    uvs = [(0, 0), (1, 0), (1, 1), (0, 1)]
    for cx, cy, cz, sx, sy, sz in boxes:
        hx, hy, hz = sx * 0.5, sy * 0.5, sz * 0.5
        for (nx, ny, nz), verts in faces_def:
            for (vx, vy, vz), (u, v) in zip(verts, uvs):
                lines.append(f"v {cx + vx * hx:.4f} {cy + vy * hy:.4f} {cz + vz * hz:.4f}")
                lines.append(f"vt {u:.2f} {v:.2f}")
                lines.append(f"vn {nx:.2f} {ny:.2f} {nz:.2f}")
            a, b, c, d = v_off, v_off + 1, v_off + 2, v_off + 3
            lines.append(f"f {a}/{a}/{a} {b}/{b}/{b} {c}/{c}/{c}")
            lines.append(f"f {a}/{a}/{a} {c}/{c}/{c} {d}/{d}/{d}")
            v_off += 4
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def write_vox(path, sx, sy, sz, voxels, palette_rgb):
    """Write MagicaVoxel .vox v150 binary."""
    os.makedirs(os.path.dirname(path), exist_ok=True)

    def vchunk(cid, content, children=b""):
        return cid + struct.pack("<II", len(content), len(children)) + content + children

    size_c = vchunk(b"SIZE", struct.pack("<III", sx, sy, sz))
    xyzi_payload = struct.pack("<I", len(voxels)) + b"".join(struct.pack("<BBBB", x, y, z, c) for x, y, z, c in voxels)
    xyzi_c = vchunk(b"XYZI", xyzi_payload)
    pal_bytes = bytearray(256 * 4)
    for idx, (r, g, b) in palette_rgb.items():
        if 1 <= idx <= 255:
            off = (idx - 1) * 4
            pal_bytes[off : off + 4] = bytes((r, g, b, 255))
    rgba_c = vchunk(b"RGBA", bytes(pal_bytes))
    main_c = vchunk(b"MAIN", b"", size_c + xyzi_c + rgba_c)
    with open(path, "wb") as f:
        f.write(b"VOX " + struct.pack("<I", 150) + main_c)


def write_wav(path, fn_sample, dur_sec=0.22, rate=22050):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    n = int(dur_sec * rate)
    samples = bytearray()
    for i in range(n):
        t = i / rate
        env = min(1.0, i / (0.01 * rate)) * max(0.0, 1.0 - i / n)
        val = max(-1.0, min(1.0, fn_sample(t) * env * 0.45))
        samples.extend(struct.pack("<h", int(val * 32767)))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(bytes(samples))


def main():
    # 1. Shared .obj meshes (pivot specified clearly, +X right, +Y up, -Z forward)
    write_obj_box_parts(os.path.join(SHARED, "meshes", "crate.obj"), [(0, 0.5, 0, 1.0, 1.0, 1.0)])
    write_obj_box_parts(
        os.path.join(SHARED, "meshes", "pillar.obj"),
        [(0, 0.15, 0, 0.9, 0.3, 0.9), (0, 1.5, 0, 0.6, 2.4, 0.6), (0, 2.85, 0, 0.9, 0.3, 0.9)],
    )
    write_obj_box_parts(
        os.path.join(SHARED, "meshes", "archway.obj"),
        [(-0.95, 1.25, 0, 0.4, 2.5, 0.4), (0.95, 1.25, 0, 0.4, 2.5, 0.4), (0, 2.7, 0, 2.3, 0.4, 0.5)],
    )
    write_obj_box_parts(
        os.path.join(SHARED, "meshes", "starfighter.obj"),
        [(0, 0, 0, 0.9, 0.5, 2.8), (0, 0, 0.3, 3.2, 0.14, 1.0), (0, 0.32, -0.2, 0.55, 0.35, 0.9)],
    )
    write_obj_box_parts(
        os.path.join(SHARED, "meshes", "crystal.obj"),
        [(0, 0.6, 0, 0.5, 1.2, 0.5), (0, 0.6, 0, 0.7, 0.6, 0.7)],
    )
    write_obj_box_parts(
        os.path.join(SHARED, "meshes", "chest.obj"),
        [(0, 0.25, 0, 0.9, 0.5, 0.6), (0, 0.58, 0, 0.94, 0.2, 0.64)],
    )

    # 2. Shared MagicaVoxel .vox models
    lantern_vox = []
    for z in range(8):
        for y in range(4):
            for x in range(4):
                if z in (0, 7) or (x in (0, 3) and y in (0, 3)):
                    lantern_vox.append((x, y, z, 1))
                elif 2 <= z <= 5 and 1 <= x <= 2 and 1 <= y <= 2:
                    lantern_vox.append((x, y, z, 2))
    write_vox(os.path.join(SHARED, "voxels", "lantern.vox"), 4, 4, 8, lantern_vox, {1: (60, 65, 80), 2: (255, 210, 90)})

    # 3. Shared retro PNG textures & sprites
    chk = bytearray(32 * 32 * 4)
    for y in range(32):
        for x in range(32):
            on = ((x // 8) + (y // 8)) % 2 == 0
            c = (215, 220, 230, 255) if on else (68, 76, 94, 255)
            chk[(y * 32 + x) * 4 : (y * 32 + x + 1) * 4] = bytes(c)
    write_png(os.path.join(SHARED, "textures", "checker.png"), 32, 32, chk)

    orb = bytearray(32 * 32 * 4)
    for y in range(32):
        for x in range(32):
            dx, dy = (x - 15.5) / 14.0, (y - 15.5) / 14.0
            d2 = dx * dx + dy * dy
            if d2 <= 1.0:
                glow = int(255 * (1.0 - d2 * 0.65))
                orb[(y * 32 + x) * 4 : (y * 32 + x + 1) * 4] = bytes((80, glow, 255, 255))
    write_png(os.path.join(SHARED, "sprites", "orb_sprite.png"), 32, 32, orb)

    # 4. Shared WAV SFX
    write_wav(os.path.join(SHARED, "audio", "pickup.wav"), lambda t: math.sin(2 * math.pi * (520 + 680 * t) * t), 0.18)
    write_wav(os.path.join(SHARED, "audio", "laser.wav"), lambda t: (1.0 if math.sin(2 * math.pi * (880 - 2200 * t) * t) >= 0 else -1.0), 0.16)
    write_wav(os.path.join(SHARED, "audio", "portal_hum.wav"), lambda t: 0.6 * math.sin(2 * math.pi * 140 * t) + 0.4 * math.sin(2 * math.pi * 211 * t), 0.30)

    # 5. Catalog JSON with exact metric bounds and coordinate conventions
    catalog = {
        "schema_version": "0.1.0",
        "coordinate_system": {"right": "+X", "up": "+Y", "forward": "-Z", "unit": "1.0 = 1 meter"},
        "license": "MIT",
        "assets": [
            {"id": "mesh.crate", "path": "assets/shared/meshes/crate.obj", "type": "mesh", "bounds_m": [1.0, 1.0, 1.0], "pivot": "bottom_center", "tags": ["prop", "crate", "physics"]},
            {"id": "mesh.pillar", "path": "assets/shared/meshes/pillar.obj", "type": "mesh", "bounds_m": [0.9, 3.0, 0.9], "pivot": "bottom_center", "tags": ["architecture", "temple", "dungeon"]},
            {"id": "mesh.archway", "path": "assets/shared/meshes/archway.obj", "type": "mesh", "bounds_m": [2.3, 2.9, 0.5], "pivot": "bottom_center", "doorway_opening_m": [1.5, 2.5], "tags": ["portal", "doorway", "architecture"]},
            {"id": "mesh.starfighter", "path": "assets/shared/meshes/starfighter.obj", "type": "mesh", "bounds_m": [3.2, 0.75, 2.8], "pivot": "center", "forward": "-Z", "tags": ["vehicle", "space", "cockpit"]},
            {"id": "mesh.crystal", "path": "assets/shared/meshes/crystal.obj", "type": "mesh", "bounds_m": [0.7, 1.2, 0.7], "pivot": "bottom_center", "tags": ["pickup", "magic", "sci-fi"]},
            {"id": "mesh.chest", "path": "assets/shared/meshes/chest.obj", "type": "mesh", "bounds_m": [0.94, 0.68, 0.64], "pivot": "bottom_center", "tags": ["loot", "dungeon", "prop"]},
            {"id": "voxel.lantern", "path": "assets/shared/voxels/lantern.vox", "type": "voxel", "grid": [4, 4, 8], "pivot": "origin", "tags": ["light", "voxel", "prop"]},
            {"id": "tex.checker", "path": "assets/shared/textures/checker.png", "type": "texture", "resolution": [32, 32], "tileable": True, "tags": ["grid", "retro", "floor"]},
            {"id": "sprite.orb", "path": "assets/shared/sprites/orb_sprite.png", "type": "sprite", "resolution": [32, 32], "tags": ["projectile", "particle", "pickup"]},
            {"id": "sfx.pickup", "path": "assets/shared/audio/pickup.wav", "type": "audio", "duration_s": 0.18, "tags": ["sfx", "pickup", "positive"]},
            {"id": "sfx.laser", "path": "assets/shared/audio/laser.wav", "type": "audio", "duration_s": 0.16, "tags": ["sfx", "weapon", "retro"]},
            {"id": "sfx.portal_hum", "path": "assets/shared/audio/portal_hum.wav", "type": "audio", "duration_s": 0.30, "tags": ["sfx", "portal", "ambient"]},
            {"id": "font.proggy_clean", "path": "assets/shared/fonts/proggy_clean.ttf", "type": "font", "license": "MIT (Tristan Grimmer)", "tags": ["ui", "hud", "sdf"]},
        ],
    }
    with open(os.path.join(SHARED, "catalog.json"), "w", encoding="utf-8") as f:
        json.dump(catalog, f, indent=2)
        f.write("\n")

    # Also write gold checker texture for mods/example_retro_pack override
    mod_chk = bytearray(32 * 32 * 4)
    for y in range(32):
        for x in range(32):
            on = ((x // 8) + (y // 8)) % 2 == 0
            c = (255, 215, 85, 255) if on else (90, 52, 24, 255)
            mod_chk[(y * 32 + x) * 4 : (y * 32 + x + 1) * 4] = bytes(c)
    write_png(os.path.join(ROOT, "mods", "example_retro_pack", "assets", "shared", "textures", "checker.png"), 32, 32, mod_chk)
    print(f"Generated {len(catalog['assets'])} shared assets + catalog.json + mod override texture.")


if __name__ == "__main__":
    main()
