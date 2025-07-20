package main

import "core:strings"
import "core:strconv"
import "core:os"
import "core:fmt"

Vec2i :: [2]i32
Vec3i :: [3]i32
Vec4i :: [4]i32

Vec2f :: [2]f32 // xy
Vec3f :: [3]f32 // xyz
Vec4f :: [4]f32 // rgba

Vertex :: struct {
    position: Vec3f,
    color: Vec4f,
    uv: Vec2f
}

Model :: struct {
    vertices: []Vertex,
    indices: []u16
}

parse_v :: proc(v_data: string) -> Vec3f {
    v_data := v_data // Shadowing
    array: Vec3f
    i: int
    for v in strings.split_by_byte_iterator(&v_data, ' ') {
        v_number := cast(f32)strconv.atof(v)
        array[i] = v_number
        i += 1
    }

    return array
}

parse_vt :: proc(vt_data: string) -> Vec2f {
    return {}
}

parse_vn :: proc(vn_data: string) -> Vec3f {
    return {}
}

parse_f :: proc(f_data: string) -> []u16 {
    f_data := f_data
    array: [dynamic]u16
    for f in strings.split_by_byte_iterator(&f_data, ' ') {
        f_number := cast(u16)strconv.atoi(f)
        append(&array, f_number - 1) // -1 pour correspondre à l'indexation des tableaux.
    }
    
    return array[:]
}

load_model_from_file :: proc(filename: string) -> Model {
    data, ok := os.read_entire_file_from_filename(filename, context.temp_allocator); defer delete(data, context.temp_allocator)
    assert(ok)

    vertices: [dynamic]Vertex
    indices: [dynamic]u16

    it := string(data)
    for line in strings.split_lines_iterator(&it) {
        if len(line) != 0 {
            if line[0] == 'v' { // vertices
                pos_data := parse_v(line[2:])
                vertex := Vertex{
                    position = pos_data,
                    color = {1.0, 1.0, 1.0, 1.0},
                    uv = {0.0, 0.0}
                }
                append(&vertices, vertex)
            }
            else if line[0] == 'v' && line[1] == 't' { // textures
                continue
            }
            else if line[0] == 'v' && line[1] == 'n' { // normals
                continue
            }
            else if line[0] == 'f' { // faces
                append(&indices, ..parse_f(line[2:]))
            }
        }
    }

    return {
        vertices = vertices[:],
        indices = indices[:]
    }
}