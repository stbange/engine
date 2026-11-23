layout(location = 0) in vec3 a_pos;
layout(location = 4) in vec4 a_inst0;
layout(location = 5) in vec4 a_inst1;
layout(location = 6) in vec4 a_inst2;
layout(location = 7) in vec4 a_inst3;

uniform mat4 u_vp;

void main() {
    mat4 model = mat4(a_inst0, a_inst1, a_inst2, a_inst3);
    gl_Position = u_vp * (model * vec4(a_pos, 1.0));
}
