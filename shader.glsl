@header package main
@header import sg "sokol/gfx"

@vs vs
in vec2 in_position;
in vec4 in_color;

out vec4 color;

void main() {
    gl_Position = vec4(in_position, 0.0, 1.0);
    color = in_color;
}
@end

@fs fs
in vec4 color;

out vec4 frag_color;

void main() {
    frag_color = color;
}
@end

@program main vs fs