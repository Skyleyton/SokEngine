package main

import "core:c"
import "core:strings"
import "core:strconv"
import "core:os"
import "core:fmt"
import "core:log"

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

Obj_FaceIndex :: struct {
    pos: uint,
}

ObjData :: struct {
    positions: []Vec3f,
    uvs: []Vec2f,
    faces: []Obj_FaceIndex
}

parse_string_to_f32 :: proc(float_str: string) -> f32 {
    val, ok := strconv.parse_f32(float_str); assert(ok)
    return val
}

parse_string_to_uint :: proc(uint_str: string) -> uint {
    val, ok := strconv.parse_uint(uint_str); assert(ok)
    return val
}

extract_separated :: proc(s: ^string, sep: byte) -> string {
    sub, ok := strings.split_by_byte_iterator(s, sep); assert(ok)
    return sub
}

parse_v :: proc(v_data: string) -> Vec3f {
    v_data := v_data
    x := parse_string_to_f32(extract_separated(&v_data, ' '))
    y := parse_string_to_f32(extract_separated(&v_data, ' '))
    z := parse_string_to_f32(extract_separated(&v_data, ' '))

    return {x, y, z}
}

parse_vt :: proc(vt_data: string) -> Vec2f {
    vt_data := vt_data
    u := parse_string_to_f32(extract_separated(&vt_data, ' '))
    v := parse_string_to_f32(extract_separated(&vt_data, ' '))

    return {u, v}
}

parse_vn :: proc(vn_data: string) -> Vec3f {
    vn_data := vn_data
    x := parse_string_to_f32(extract_separated(&vn_data, ' '))
    y := parse_string_to_f32(extract_separated(&vn_data, ' '))
    z := parse_string_to_f32(extract_separated(&vn_data, ' '))

    return {x, y, z}
}

parse_f :: proc(f_data: string) -> [3]Obj_FaceIndex {
    f_data := f_data
    t1_index := parse_string_to_uint(extract_separated(&f_data, ' ')) - 1
    t2_index := parse_string_to_uint(extract_separated(&f_data, ' ')) - 1
    t3_index := parse_string_to_uint(extract_separated(&f_data, ' ')) - 1
    
    return {
        {pos = t1_index},
        {pos = t2_index},
        {pos = t3_index}
    }
}

load_model_from_file :: proc(filename: string) -> ObjData {
    data, ok := os.read_entire_file_from_filename(filename, context.temp_allocator); defer delete(data, context.temp_allocator)
    assert(ok)

    positions := make([dynamic]Vec3f, allocator=context.temp_allocator)
    uvs := make([dynamic]Vec2f, allocator=context.temp_allocator)
    faces := make([dynamic]Obj_FaceIndex, allocator=context.temp_allocator)

    it := string(data)
    for line in strings.split_lines_iterator(&it) {
        if len(line) == 0 do continue

        switch line[0] {
            case 'v':
                switch line[1] {
                    case ' ':
                        append(&positions, parse_v(line[2:]))
                    case 'n':
                        continue
                    case 't':
                        // append(&positions, parse_v(line[2:]))
                        append(&uvs, Vec2f{0.0, 0.0})
                    case:
                        continue

                }
            case 'f':
                indices := parse_f(line[2:])
                append_elems(&faces, indices[0], indices[1], indices[2])
            case:
                continue
        }
    }

    return {
        positions = positions[:],
        uvs = uvs[:],
        faces = faces[:]
    }
}

obj_destroy :: proc(obj: ObjData) {
    delete(obj.positions)
    delete(obj.faces)
    delete(obj.uvs)
}