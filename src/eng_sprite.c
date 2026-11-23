#include "engine/eng_sprite.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

int eng_sprite_dir8_index(eng_vec3_t cam_pos, eng_vec3_t sprite_pos, float sprite_yaw_rad) {
    float dx = cam_pos.x - sprite_pos.x;
    float dz = cam_pos.z - sprite_pos.z;
    float view_yaw = atan2f(-dx, -dz); /* 0 when looking along -Z */
    float rel = view_yaw - sprite_yaw_rad;
    while (rel < 0.0f) rel += 2.0f * ENG_PI;
    while (rel >= 2.0f * ENG_PI) rel -= 2.0f * ENG_PI;
    int idx = (int)floorf((rel + (ENG_PI / 8.0f)) / (ENG_PI / 4.0f)) & 7;
    return idx;
}

size_t eng_sprite_build_batch(const eng_sprite_item_t *items, size_t count,
                              uint16_t active_pocket, eng_vec3_t cam_pos, eng_vec3_t cam_right, eng_vec3_t cam_up,
                              eng_mesh_data_t *out_mesh) {
    if (!out_mesh) return 0;
    eng_mesh_data_init(out_mesh);
    if (!items || count == 0) return 0;

    out_mesh->verts = (eng_vertex_t *)malloc(count * 4u * sizeof(eng_vertex_t));
    out_mesh->indices = (uint32_t *)malloc(count * 6u * sizeof(uint32_t));
    if (!out_mesh->verts || !out_mesh->indices) {
        eng_mesh_data_free(out_mesh);
        return 0;
    }
    out_mesh->vert_cap = count * 4u;
    out_mesh->idx_cap = count * 6u;

    size_t emitted = 0;
    for (size_t i = 0; i < count; i++) {
        const eng_sprite_item_t *sp = &items[i];
        if (sp->pocket_id != active_pocket) continue;

        eng_vec3_t right = cam_right;
        eng_vec3_t up = (sp->mode == ENG_SPRITE_BILLBOARD_SPHERICAL) ? cam_up : eng_v3(0.0f, 1.0f, 0.0f);
        if (sp->mode != ENG_SPRITE_BILLBOARD_SPHERICAL) {
            eng_vec3_t to_cam = eng_v3(cam_pos.x - sp->pos.x, 0.0f, cam_pos.z - sp->pos.z);
            eng_vec3_t fwd = eng_v3_norm(to_cam);
            if (eng_v3_dot(fwd, fwd) < 0.1f) fwd = eng_v3(0.0f, 0.0f, 1.0f);
            right = eng_v3_cross(up, fwd);
        }

        eng_vec4_t uv = sp->uv_rect;
        if (sp->mode == ENG_SPRITE_DIRECTIONAL_8) {
            int dir8 = eng_sprite_dir8_index(cam_pos, sp->pos, sp->facing_yaw_rad);
            float du = (uv.z - uv.x) * 0.125f;
            uv.x = uv.x + (float)dir8 * du;
            uv.z = uv.x + du;
        }

        eng_vec3_t rx = eng_v3_scale(right, sp->size.x * 0.5f);
        eng_vec3_t ry = eng_v3_scale(up, sp->size.y);
        eng_vec3_t nrm = eng_v3_norm(eng_v3_sub(cam_pos, sp->pos));
        if (eng_v3_dot(nrm, nrm) < 0.1f) nrm = eng_v3(0.0f, 0.0f, 1.0f);

        eng_vec3_t corners[4] = {
            eng_v3_sub(sp->pos, rx),
            eng_v3_add(sp->pos, rx),
            eng_v3_add(eng_v3_add(sp->pos, rx), ry),
            eng_v3_add(eng_v3_sub(sp->pos, rx), ry)
        };
        float uvs[4][2] = {{uv.x, uv.w}, {uv.z, uv.w}, {uv.z, uv.y}, {uv.x, uv.y}};

        uint32_t base = (uint32_t)out_mesh->vert_count;
        for (int k = 0; k < 4; k++) {
            eng_vertex_t vt;
            memset(&vt, 0, sizeof(vt));
            vt.pos[0] = corners[k].x; vt.pos[1] = corners[k].y; vt.pos[2] = corners[k].z;
            vt.norm[0] = nrm.x; vt.norm[1] = nrm.y; vt.norm[2] = nrm.z;
            vt.uv[0] = uvs[k][0]; vt.uv[1] = uvs[k][1];
            vt.color[0] = sp->tint.x; vt.color[1] = sp->tint.y; vt.color[2] = sp->tint.z; vt.color[3] = sp->tint.w;
            vt.weights[0] = 1.0f;
            out_mesh->verts[out_mesh->vert_count++] = vt;
        }
        out_mesh->indices[out_mesh->idx_count++] = base + 0;
        out_mesh->indices[out_mesh->idx_count++] = base + 1;
        out_mesh->indices[out_mesh->idx_count++] = base + 2;
        out_mesh->indices[out_mesh->idx_count++] = base + 0;
        out_mesh->indices[out_mesh->idx_count++] = base + 2;
        out_mesh->indices[out_mesh->idx_count++] = base + 3;
        emitted++;
    }
    return emitted;
}
