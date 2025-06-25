package utils

import sg "../../sokol/gfx"

// Retourne un sg.Range via un array.
sg_range :: proc(array: []$T) -> sg.Range {
    return {
        ptr = raw_data(array),
        size = len(array) * size_of(array[0])
    }
}

// Textures et 2D
Vec2 :: [2]f32 // xy

// 3D
Vec3 :: [3]f32 // xyz

// Couleurs et vecteurs avec w.
Vec4 :: [4]f32 // rgba 

Vertex :: struct {
    position: Vec3,
    color: Vec4
}