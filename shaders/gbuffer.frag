in vec3 v_world_pos;
in vec3 v_norm;
in vec2 v_uv;
in vec4 v_color;

uniform sampler2D u_albedo_tex;
uniform vec4 u_tint;
uniform vec3 u_mat_mr;

layout(location = 0) out vec4 o_gb_albedo_met;
layout(location = 1) out vec4 o_gb_norm_rough;
layout(location = 2) out vec4 o_gb_pos_ao;

void main() {
    vec4 tex = texture(u_albedo_tex, v_uv) * v_color * u_tint;
    if (tex.a < 0.1) discard;
    o_gb_albedo_met = vec4(tex.rgb, u_mat_mr.x);
    o_gb_norm_rough = vec4(normalize(v_norm) * 0.5 + 0.5, u_mat_mr.y);
    o_gb_pos_ao = vec4(v_world_pos, 1.0);
}
