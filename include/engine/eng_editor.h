#ifndef ENG_EDITOR_H
#define ENG_EDITOR_H

#include "eng_portal.h"
#include "eng_profiler.h"
#include "eng_scene.h"
#include "eng_ui.h"
#include "eng_voxel.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    ENG_GIZMO_TRANSLATE = 0,
    ENG_GIZMO_ROTATE,
    ENG_GIZMO_SCALE
} eng_gizmo_mode_t;

typedef struct eng_editor_s eng_editor_t;

eng_editor_t *eng_editor_create(void);
void eng_editor_destroy(eng_editor_t *ed);

/* Toggleable F1 Editor mode */
void eng_editor_toggle(eng_editor_t *ed);
bool eng_editor_is_open(const eng_editor_t *ed);

/* Selection, Pocket Space switcher & ProcGen seed inspector */
void eng_editor_select(eng_editor_t *ed, eng_entity_t ent);
eng_entity_t eng_editor_selected(const eng_editor_t *ed);

void eng_editor_set_active_pocket(eng_editor_t *ed, uint16_t pocket_id);
uint16_t eng_editor_active_pocket(const eng_editor_t *ed);

void eng_editor_set_seed(eng_editor_t *ed, uint32_t seed);
uint32_t eng_editor_step_seed(eng_editor_t *ed, int delta);
uint32_t eng_editor_seed(const eng_editor_t *ed);

/* 3D Translate / Rotate / Scale gizmo manipulation & viewport ray-picking/dragging */
void eng_editor_set_gizmo_mode(eng_editor_t *ed, eng_gizmo_mode_t mode);
eng_gizmo_mode_t eng_editor_gizmo_mode(const eng_editor_t *ed);
bool eng_editor_apply_gizmo_delta(eng_editor_t *ed, eng_scene_t *scene, eng_vec3_t delta);
eng_entity_t eng_editor_viewport_interact(eng_editor_t *ed, eng_scene_t *scene,
                                          eng_vec3_t ray_origin, eng_vec3_t ray_dir,
                                          bool mouse_pressed, bool mouse_down,
                                          float drag_dx, float drag_dy);

/* Two-step interactive portal linker (mark source entity -> link to selected destination entity) */
void eng_editor_mark_portal_source(eng_editor_t *ed, eng_entity_t src_ent);
int eng_editor_link_portal_to_selected(eng_editor_t *ed, eng_portal_sys_t *portals,
                                       eng_scene_t *scene, float w, float h);

/* Voxel & Prefab brushes */
bool eng_editor_voxel_paint(eng_editor_t *ed, eng_voxel_chunk_t *chunk, int x, int y, int z, uint8_t block_id);
eng_entity_t eng_editor_spawn_prefab(eng_editor_t *ed, eng_scene_t *scene, const char *name, eng_vec3_t pos);

/* F5 Play-in-Editor (PIE): captures pre-play JSON snapshot and restores cleanly on stop */
bool eng_editor_toggle_pie(eng_editor_t *ed, eng_scene_t *scene, char *err_buf, size_t err_cap);
bool eng_editor_is_playing(const eng_editor_t *ed);

/* Save active scene to disk as valid JSON (scenes/<name>.json) */
bool eng_editor_save_scene_file(const eng_editor_t *ed, const eng_scene_t *scene, const char *disk_path);

/* Render Nuklear hierarchy/pocket-dropdown/inspector panels and emit 3D gizmos + portal frames */
void eng_editor_draw_ui(eng_editor_t *ed, eng_ui_t *ui, eng_scene_t *scene,
                        eng_portal_sys_t *portals, eng_profiler_t *prof);

#ifdef __cplusplus
}
#endif

#endif /* ENG_EDITOR_H */
