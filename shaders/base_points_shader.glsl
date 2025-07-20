@header package shaders
@header import sg "../sokol/gfx"

@vs vs
in vec3 in_position;
in vec4 in_color;

out vec4 out_color;

void main() {
    gl_PointSize = 10.0;
    gl_Position = vec4(in_position, 1.0);
    out_color = in_color;
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