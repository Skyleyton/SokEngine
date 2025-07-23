@header package shaders
@header import sg "../sokol/gfx"

@vs vs_base_points
in vec3 in_position;

layout(binding = 0) uniform base_points_vs_params {
    mat4 mvp;
};

out vec4 out_color;

void main() {
    gl_PointSize = 10.0;
    gl_Position = mvp * vec4(in_position, 1.0);
    out_color = vec4(0.0, 0.0, 0.0, 1.0);
}

@end

@fs fs_base_points
in vec4 out_color;

out vec4 frag_color;

void main() {
    frag_color = out_color;
}
@end

// Le nom du shader
@program base_points vs_base_points fs_base_points