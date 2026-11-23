layout(location = 0) in vec2 a_pos;

uniform mat4 u_inv_vp;

out vec3 v_ray_dir;

void main() {
    vec4 far_pt = u_inv_vp * vec4(a_pos, 1.0, 1.0);
    vec4 near_pt = u_inv_vp * vec4(a_pos, -1.0, 1.0);
    v_ray_dir = (far_pt.xyz / max(far_pt.w, 0.0001)) - (near_pt.xyz / max(near_pt.w, 0.0001));
    gl_Position = vec4(a_pos, 0.9999, 1.0);
}
