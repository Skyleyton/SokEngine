@header package shaders
@header import sg "../sokol/gfx"

@vs vs
in vec3 in_position;
in vec4 in_color;
in vec2 in_uv;

out vec4 color;
out vec2 out_uv;

void main() {
    gl_Position = vec4(in_position, 1.0);
    color = in_color;
    out_uv = in_uv;
}
@end


@fs fs
in vec4 color;
in vec2 out_uv;

layout(binding = 0) uniform texture2D my_texture;
layout(binding = 1) uniform sampler smp;

out vec4 frag_color;

void main() {
    frag_color = texture(sampler2D(my_texture, smp), out_uv) * color;
}
@end

@program textured vs fs