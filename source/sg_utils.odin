package main

import sg "sokol/gfx"
import stbi "vendor:stb/image"

// Retourne un sg.Range via un array (slice) de tout type.
sg_range :: proc(array: []$T) -> sg.Range {
    return {
        ptr = raw_data(array),
        size = len(array) * size_of(array[0])
    }
}

sg_get_image :: proc(filename: cstring) -> sg.Image {
    texture_dim: Vec2i
    texture_data := stbi.load(filename, &texture_dim.x, &texture_dim.y, nil, 4)
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