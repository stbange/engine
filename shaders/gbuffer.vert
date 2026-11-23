#include "shaders/common.glsl"

layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec3 a_norm;
layout(location = 2) in vec2 a_uv;
layout(location = 3) in vec4 a_color;
layout(location = 4) in vec4 a_inst0;
layout(location = 5) in vec4 a_inst1;
layout(location = 6) in vec4 a_inst2;
layout(location = 7) in vec4 a_inst3;

uniform mat4 u_vp;
uniform float u_vertex_snap;

out vec3 v_world_pos;
out vec3 v_norm;
out vec2 v_uv;
out vec4 v_color;

void main() {
    mat4 model = mat4(a_inst0, a_inst1, a_inst2, a_inst3);
    vec4 wp = model * vec4(a_pos, 1.0);
    v_world_pos = wp.xyz;
    v_norm = normalize(mat3(model) * a_norm);
    v_uv = a_uv;
    v_color = a_color;
    gl_Position = eng_snap_vertex(u_vp * wp, u_vertex_snap);
}
