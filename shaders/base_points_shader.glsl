@header package shaders
@header import sg "../sokol/gfx"

@module base_points

@vs vs
in vec3 in_position;
in vec4 in_color;
in vec2 in_uv;

layout(binding = 0) uniform vs_params {
    mat4 mvp;
};

out vec4 out_color;

void main() {
    gl_Position = mvp * vec4(in_position, 1.0);
    gl_PointSize = 10.0;
    out_color = vec4(0.0, 0.0, 0.0, 1.0);
}

@end

@fs fs
in vec4 out_color;

out vec4 frag_color;

void main() {
    frag_color = out_color;
}
@end

// Le nom du shader
@program base_points vs fs