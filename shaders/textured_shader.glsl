@header package shaders
@header import sg "../sokol/gfx"

@ctype mat4 Mat4 // Sorte de remplacement de code en fait.

@vs vs_textured
in vec3 in_position;
in vec4 in_color;
in vec2 in_uv;

layout(binding = 0) uniform textured_vs_params {
    mat4 mvp;
};

out vec4 color;
out vec2 out_uv;

void main() {
    gl_Position = mvp * vec4(in_position, 1.0);
    color = in_color;
    out_uv = in_uv;
}
@end


@fs fs_textured
in vec4 color;
in vec2 out_uv;

layout(binding = 0) uniform texture2D my_texture;
layout(binding = 1) uniform sampler smp;

out vec4 frag_color;

void main() {
    frag_color = texture(sampler2D(my_texture, smp), out_uv) * color;
}
@end

@program textured vs_textured fs_textured