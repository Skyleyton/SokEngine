package main

import "core:math/rand"

init_world :: proc() {
    world_x := 10
    world_y := 10
    world := make([]i32, world_x * world_y, context.temp_allocator)

    for x in 0..<world_x {
        for y in 0..<world_y {
            val := rand.int_max(3)
            world[x * world_x + y] = cast(i32)val
        }
    }

    state.world = world[:]
}

render_world :: proc() {
    
}