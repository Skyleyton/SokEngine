package main

import sg "sokol/gfx"

Vec2i :: [2]i32
Vec3i :: [3]i32
Vec4i :: [4]i32

Vec2f :: [2]f32 // xy
Vec3f :: [3]f32 // xyz
Vec4f :: [4]f32 // rgba

Vertex :: struct {
    position: Vec3f,
    color: Vec4f,
}

// Retourne un sg.Range via un array (slice) de tout type.
sg_range :: proc(array: []$T) -> sg.Range {
    return {
        ptr = raw_data(array),
        size = len(array) * size_of(array[0])
    }
}