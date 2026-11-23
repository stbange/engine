#include "engine/eng_editor.h"

#define NK_INCLUDE_FIXED_TYPES
#define NK_INCLUDE_STANDARD_IO
#define NK_INCLUDE_STANDARD_VARARGS
#define NK_INCLUDE_DEFAULT_ALLOCATOR
#define NK_INCLUDE_VERTEX_BUFFER_OUTPUT
#define NK_INCLUDE_FONT_BAKING
#define NK_INCLUDE_DEFAULT_FONT
#include "nuklear.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ENG_PIE_SNAP_CAP (256 * 1024)

struct eng_editor_s {
    bool open;
    bool playing;
    eng_entity_t selected;
    uint16_t active_pocket;
    uint32_t seed;
    eng_gizmo_mode_t gizmo_mode;
    char *pie_snapshot;
};

eng_editor_t *eng_editor_create(void) {
    eng_editor_t *ed = (eng_editor_t *)calloc(1, sizeof(*ed));
    if (!ed) return NULL;
    ed->selected = ENG_ENTITY_NULL;
    ed->seed = 42u;
    ed->gizmo_mode = ENG_GIZMO_TRANSLATE;
    return ed;
}

void eng_editor_destroy(eng_editor_t *ed) {
    if (!ed) return;
    free(ed->pie_snapshot);
    free(ed);
}

void eng_editor_toggle(eng_editor_t *ed) {
    if (ed) ed->open = !ed->open;
}

bool eng_editor_is_open(const eng_editor_t *ed) {
    return ed ? ed->open : false;
}

void eng_editor_select(eng_editor_t *ed, eng_entity_t ent) {
    if (ed) ed->selected = ent;
}

eng_entity_t eng_editor_selected(const eng_editor_t *ed) {
    return ed ? ed->selected : ENG_ENTITY_NULL;
}

void eng_editor_set_active_pocket(eng_editor_t *ed, uint16_t pocket_id) {
    if (ed) ed->active_pocket = pocket_id;
}

uint16_t eng_editor_active_pocket(const eng_editor_t *ed) {
    return ed ? ed->active_pocket : 0u;
}

void eng_editor_set_seed(eng_editor_t *ed, uint32_t seed) {
    if (ed) ed->seed = seed;
}

uint32_t eng_editor_step_seed(eng_editor_t *ed, int delta) {
    if (!ed) return 0u;
    ed->seed = (uint32_t)((int64_t)ed->seed + (int64_t)delta);
    return ed->seed;
}

uint32_t eng_editor_seed(const eng_editor_t *ed) {
    return ed ? ed->seed : 0u;
}

void eng_editor_set_gizmo_mode(eng_editor_t *ed, eng_gizmo_mode_t mode) {
    if (ed) ed->gizmo_mode = mode;
}

eng_gizmo_mode_t eng_editor_gizmo_mode(const eng_editor_t *ed) {
    return ed ? ed->gizmo_mode : ENG_GIZMO_TRANSLATE;
}

bool eng_editor_apply_gizmo_delta(eng_editor_t *ed, eng_scene_t *scene, eng_vec3_t delta) {
    if (!ed || !scene || ed->selected == ENG_ENTITY_NULL) return false;
    const eng_transform_local_t *loc = eng_scene_get_local(scene, ed->selected);
    if (!loc) return false;

    bool ok = false;
    if (ed->gizmo_mode == ENG_GIZMO_TRANSLATE) {
        ok = eng_scene_set_local_pos(scene, ed->selected, eng_v3_add(loc->pos, delta));
    } else if (ed->gizmo_mode == ENG_GIZMO_ROTATE) {
        eng_quat_t dq = eng_quat_from_euler_deg(delta);
        ok = eng_scene_set_local_rot(scene, ed->selected, eng_quat_norm(eng_quat_mul(loc->rot, dq)));
    } else {
        eng_vec3_t s = eng_v3_add(loc->scale, delta);
        if (s.x < 0.01f) s.x = 0.01f;
        if (s.y < 0.01f) s.y = 0.01f;
        if (s.z < 0.01f) s.z = 0.01f;
        ok = eng_scene_set_local_scale(scene, ed->selected, s);
    }
    if (ok) eng_scene_update_transforms(scene);
    return ok;
}

bool eng_editor_voxel_paint(eng_editor_t *ed, eng_voxel_chunk_t *chunk, int x, int y, int z, uint8_t block_id) {
    if (!ed || !chunk) return false;
    return eng_voxel_set(chunk, x, y, z, block_id);
}

eng_entity_t eng_editor_spawn_prefab(eng_editor_t *ed, eng_scene_t *scene, const char *name, eng_vec3_t pos) {
    if (!ed || !scene || !name) return ENG_ENTITY_NULL;
    eng_entity_t e = eng_scene_spawn(scene, name);
    if (e != ENG_ENTITY_NULL) {
        eng_scene_set_pocket(scene, e, ed->active_pocket);
        eng_scene_set_local_pos(scene, e, pos);
        eng_scene_update_transforms(scene);
        ed->selected = e;
    }
    return e;
}

bool eng_editor_toggle_pie(eng_editor_t *ed, eng_scene_t *scene, char *err_buf, size_t err_cap) {
    if (err_buf && err_cap > 0) err_buf[0] = '\0';
    if (!ed || !scene) return false;

    if (!ed->playing) {
        if (!ed->pie_snapshot) {
            ed->pie_snapshot = (char *)malloc(ENG_PIE_SNAP_CAP);
            if (!ed->pie_snapshot) return false;
        }
        size_t n = eng_scene_save_json(scene, ed->pie_snapshot, ENG_PIE_SNAP_CAP);
        if (n == 0) return false;
        ed->playing = true;
        return true;
    } else {
        if (!ed->pie_snapshot) return false;
        /* Clear all runtime-modified / runtime-spawned entities before restoring pre-play snapshot */
        eng_ecs_t *ecs = eng_scene_ecs(scene);
        const eng_entity_t *raw = NULL;
        uint32_t count = 0;
        eng_ecs_raw_column(ecs, eng_scene_comp_local(scene), &raw, &count);
        if (count > 0) {
            eng_entity_t *copy = (eng_entity_t *)malloc(count * sizeof(eng_entity_t));
            if (copy) {
                memcpy(copy, raw, count * sizeof(eng_entity_t));
                for (uint32_t i = 0; i < count; i++) {
                    eng_scene_despawn(scene, copy[i]);
                }
                free(copy);
            }
        }
        ed->selected = ENG_ENTITY_NULL;
        ed->playing = false;
        return eng_scene_load_json(scene, ed->pie_snapshot, err_buf, err_cap);
    }
}

bool eng_editor_is_playing(const eng_editor_t *ed) {
    return ed ? ed->playing : false;
}

bool eng_editor_save_scene_file(const eng_editor_t *ed, const eng_scene_t *scene, const char *disk_path) {
    if (!ed || !scene || !disk_path) return false;
    char *buf = (char *)malloc(ENG_PIE_SNAP_CAP);
    if (!buf) return false;
    size_t n = eng_scene_save_json(scene, buf, ENG_PIE_SNAP_CAP);
    if (n == 0) {
        free(buf);
        return false;
    }
    FILE *f = fopen(disk_path, "wb");
    if (!f) {
        free(buf);
        return false;
    }
    size_t written = fwrite(buf, 1, n, f);
    fclose(f);
    free(buf);
    return written == n;
}

void eng_editor_draw_ui(eng_editor_t *ed, eng_ui_t *ui, eng_scene_t *scene,
                        const eng_portal_sys_t *portals, eng_profiler_t *prof) {
    if (!ed || !ed->open || !ui || !scene) return;
    struct nk_context *ctx = eng_ui_nk(ui);
    if (!ctx) return;

    /* Hierarchy & Pocket Space Panel */
    if (nk_begin(ctx, "Scene Editor (F1)", nk_rect(10.0f, 10.0f, 270.0f, 380.0f),
                 NK_WINDOW_BORDER | NK_WINDOW_TITLE)) {
        nk_layout_row_dynamic(ctx, 24.0f, 2);
        if (nk_button_label(ctx, ed->playing ? "Stop PIE (F5)" : "Play PIE (F5)")) {
            eng_editor_toggle_pie(ed, scene, NULL, 0);
        }
        if (nk_button_label(ctx, "Seed +1")) {
            eng_editor_step_seed(ed, 1);
        }

        char pk_lbl[64];
        const char *pk_name = eng_scene_pocket_name(scene, ed->active_pocket);
        snprintf(pk_lbl, sizeof(pk_lbl), "Pocket [%u]: %s", (unsigned)ed->active_pocket, pk_name ? pk_name : "world");
        nk_layout_row_dynamic(ctx, 20.0f, 1);
        nk_label(ctx, pk_lbl, NK_TEXT_LEFT);

        const eng_entity_t *ents = NULL;
        uint32_t count = 0;
        eng_ecs_t *ecs = eng_scene_ecs(scene);
        eng_ecs_raw_column(ecs, eng_scene_comp_local(scene), &ents, &count);
        for (uint32_t i = 0; i < count && i < 16; i++) {
            eng_entity_t e = ents[i];
            if (eng_scene_get_pocket(scene, e) != ed->active_pocket) continue;
            const char *nm = eng_ecs_get_name(ecs, e);
            if (nk_button_label(ctx, (nm && nm[0]) ? nm : "<entity>")) {
                ed->selected = e;
            }
        }
    }
    nk_end(ctx);

    /* Selected Entity Inspector + 3D Gizmos */
    if (ed->selected != ENG_ENTITY_NULL && eng_ecs_alive(eng_scene_ecs(scene), ed->selected)) {
        const eng_transform_local_t *loc = eng_scene_get_local(scene, ed->selected);
        if (loc) {
            if (nk_begin(ctx, "Inspector", nk_rect(290.0f, 10.0f, 260.0f, 220.0f),
                         NK_WINDOW_BORDER | NK_WINDOW_TITLE)) {
                nk_layout_row_dynamic(ctx, 22.0f, 3);
                if (nk_option_label(ctx, "Move", ed->gizmo_mode == ENG_GIZMO_TRANSLATE)) ed->gizmo_mode = ENG_GIZMO_TRANSLATE;
                if (nk_option_label(ctx, "Rot", ed->gizmo_mode == ENG_GIZMO_ROTATE)) ed->gizmo_mode = ENG_GIZMO_ROTATE;
                if (nk_option_label(ctx, "Scale", ed->gizmo_mode == ENG_GIZMO_SCALE)) ed->gizmo_mode = ENG_GIZMO_SCALE;

                eng_vec3_t p = loc->pos;
                nk_layout_row_dynamic(ctx, 22.0f, 1);
                nk_property_float(ctx, "Pos X", -1000.0f, &p.x, 1000.0f, 0.1f, 0.05f);
                nk_property_float(ctx, "Pos Y", -1000.0f, &p.y, 1000.0f, 0.1f, 0.05f);
                nk_property_float(ctx, "Pos Z", -1000.0f, &p.z, 1000.0f, 0.1f, 0.05f);
                eng_scene_set_local_pos(scene, ed->selected, p);
                eng_scene_update_transforms(scene);
            }
            nk_end(ctx);

            if (prof) {
                eng_vec3_t o = loc->pos;
                eng_debug_line(prof, o, eng_v3_add(o, eng_v3(1.0f, 0.0f, 0.0f)), (eng_vec4_t){1.0f, 0.2f, 0.2f, 1.0f});
                eng_debug_line(prof, o, eng_v3_add(o, eng_v3(0.0f, 1.0f, 0.0f)), (eng_vec4_t){0.2f, 1.0f, 0.2f, 1.0f});
                eng_debug_line(prof, o, eng_v3_add(o, eng_v3(0.0f, 0.0f, 1.0f)), (eng_vec4_t){0.2f, 0.5f, 1.0f, 1.0f});
                eng_aabb_t box = {eng_v3_sub(o, eng_v3_scale(loc->scale, 0.5f)),
                                  eng_v3_add(o, eng_v3_scale(loc->scale, 0.5f))};
                eng_debug_aabb(prof, box, (eng_vec4_t){1.0f, 0.9f, 0.2f, 1.0f});
            }
        }
    }

    if (portals && prof) {
        size_t pc = eng_portal_count(portals);
        for (size_t i = 0; i < pc; i++) {
            const eng_portal_t *pt = eng_portal_get(portals, i);
            if (pt && pt->src_pocket == ed->active_pocket) {
                const eng_transform_local_t *ploc = eng_scene_get_local(scene, pt->src_ent);
                if (ploc) {
                    eng_debug_portal(prof, ploc->pos, ploc->rot, pt->half_w * 2.0f, pt->half_h * 2.0f,
                                     (eng_vec4_t){0.2f, 0.95f, 1.0f, 1.0f});
                }
            }
        }
    }
}
