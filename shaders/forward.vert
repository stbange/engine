#include "shaders/common.glsl"

layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec3 a_norm;
layout(location = 2) in vec2 a_uv;
layout(location = 3) in vec4 a_color;
layout(location = 4) in vec4 a_inst0;
layout(location = 5) in vec4 a_inst1;
layout(location = 6) in vec4 a_inst2;
layout(location = 7) in vec4 a_inst3;
layout(location = 8) in vec4 a_joints;
layout(location = 9) in vec4 a_weights;

uniform mat4 u_vp;
uniform mat4 u_light_vp;
uniform float u_vertex_snap;
uniform int u_skinned;
uniform mat4 u_bones[64];

out vec3 v_world_pos;
out vec3 v_norm;
out vec2 v_uv;
out vec4 v_color;
out vec4 v_shadow_coord;

void main() {
    mat4 model = mat4(a_inst0, a_inst1, a_inst2, a_inst3);
    vec4 local_pos = vec4(a_pos, 1.0);
    vec3 local_nrm = a_norm;
    if (u_skinned != 0) {
        ivec4 j = ivec4(a_joints + 0.5);
        mat4 skin = a_weights.x * u_bones[j.x]
                  + a_weights.y * u_bones[j.y]
                  + a_weights.z * u_bones[j.z]
                  + a_weights.w * u_bones[j.w];
        local_pos = skin * local_pos;
        local_nrm = mat3(skin) * local_nrm;
    }
    vec4 wp = model * local_pos;
    v_world_pos = wp.xyz;
    v_norm = normalize(mat3(model) * local_nrm);
    v_uv = a_uv;
    v_color = a_color;
    v_shadow_coord = u_light_vp * wp;
    gl_Position = eng_snap_vertex(u_vp * wp, u_vertex_snap);
}
