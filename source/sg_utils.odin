package main

import "base:intrinsics"
import "core:strings"

import sg "sokol/gfx"
import stbi "vendor:stb/image"


// Retourne un sg.Range via un array (slice) de tout type.
sg_range_from_slice :: proc(array: []$T) -> sg.Range {
    return {
        ptr = raw_data(array),
        size = len(array) * size_of(array[0])
    }
}

sg_range_from_struct :: proc(s: ^$T) -> sg.Range where intrinsics.type_is_struct(T) {
    return {
        ptr = s,
        size = size_of(T)
    }
}

sg_range :: proc {
    sg_range_from_slice,
    sg_range_from_struct,
}

sg_get_image :: proc(filename: string, flip_image_on_load: i32 = 1) -> sg.Image {
    texture_dim: Vec2i
    stbi.set_flip_vertically_on_load(flip_image_on_load)
    texture_data := stbi.load(strings.unsafe_string_to_cstring(filename), &texture_dim.x, &texture_dim.y, nil, 4)
    assert(texture_data != nil)

    image := sg.make_image({
        width = texture_dim.x,
        height = texture_dim.y,
        pixel_format = .RGBA8,
        data = {
            subimage = {
                0 = {
                    0 = {
                        ptr = texture_data,
                        size = cast(uint)(texture_dim.x * texture_dim.y * 4)
                    }
                }
            }
        }
    })

    stbi.image_free(texture_data)
    return image
}
