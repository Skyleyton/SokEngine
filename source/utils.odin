package main

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