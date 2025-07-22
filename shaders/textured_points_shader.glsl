@header package shaders
@header import sg "../sokol/gfx"

@ctype mat4 Mat4

@vs vs
in vec3 in_position;
in vec4 in_color;
in vec2 in_uv;

layout(binding = 0) uniform vs_params_points {
    mat4 mvp;
};

out vec4 out_color;
out vec2 out_uv;

void main() {
    gl_Position = mvp * vec4(in_position, 1.0);
    gl_PointSize = 10.5;
    out_color = in_color;
    out_uv = in_uv;
}
@end

@fs fs
in vec4 out_color;
in vec2 out_uv;

layout(binding = 0) uniform texture2D points_texture;
layout(binding = 1) uniform sampler points_smp;

out vec4 frag_color;

void main() {
    frag_color = texture(sampler2D(points_texture, points_smp), out_uv) * out_color;
}
@end

@program textured_points vs fs