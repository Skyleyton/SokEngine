package main

import "base:runtime"
import "core:log"
import "core:fmt"
import "core:math/linalg"

import sapp "sokol/app"
import sg "sokol/gfx"
import sglue "sokol/glue"
import shelpers "sokol/helpers"
import sgl "sokol/gl"

import shader "shaders_code"

State :: struct {
    pass_action: sg.Pass_Action,
    logger: log.Logger,
    vertex_buffer: sg.Buffer,
    index_buffer: sg.Buffer,
    pipeline: [2]sg.Pipeline,
    shader: [2]sg.Shader,
    texture: sg.Image,
    sampler: sg.Sampler,
    pipeline_index: int,
    rotation: f32
}

state: ^State
obj: ObjData
model: ObjModel
default_context: runtime.Context

main :: proc() {
    context.logger = log.create_console_logger()
    default_context = context

    sapp.run({
        width = 800,
        height = 600,
        window_title = "Sokengine",

        logger = sapp.Logger(shelpers.logger(&default_context)),
        allocator = sapp.Allocator(shelpers.allocator(&default_context)),

        init_cb = init_cb,
        frame_cb = frame_cb,
        cleanup_cb = cleanup_cb,
        event_cb = event_cb
    })
}

init_cb :: proc "c" () {
    context = default_context

    sg.setup({
        environment = shelpers.glue_environment(),
        allocator = sg.Allocator(shelpers.allocator(&default_context)),
        logger = sg.Logger(shelpers.logger(&default_context))
    })

    state = new(State)

    state.pass_action = {
        colors = {
            0 = {load_action = .CLEAR, clear_value = {0.75, 0.75, 0.75, 1.0}}
        }
    }

    state.shader[0] = sg.make_shader(shader.textured_shader_desc(sg.query_backend()))
    state.shader[1] = sg.make_shader(shader.textured_points_shader_desc(sg.query_backend()))

    obj = load_ObjData_from_file("assets/models/bullet-foam-thick.obj")
    model = ObjModel_from_ObjData(obj, "assets/textures/colormap.png")

    new_vertices := make([]Vertex, len(obj.faces), context.temp_allocator)
    new_indices := make([]u16, len(obj.faces), context.temp_allocator)

    for face, i in obj.faces {
        if obj.with_slash {
            new_vertices[i] = {
                position = obj.positions[face.pos],
                color = {1.0, 1.0, 1.0, 1.0},
                uv = obj.uvs[face.uv]
            }
        }
        else {
            new_vertices[i] = {
                position = obj.positions[face.pos],
                color = {1.0, 1.0, 1.0, 1.0},
                uv = {}
            }
        }
        
        new_indices[i] = cast(u16)i
    }

    state.vertex_buffer = sg.make_buffer({
        data = sg_range(new_vertices)
    })

    state.index_buffer = sg.make_buffer({
        usage = {
            index_buffer = true
        },
        data = sg_range(new_indices)
    })

    state.pipeline[0] = sg.make_pipeline({
        shader = state.shader[0],
        primitive_type = .TRIANGLES,
        index_type = .UINT16,
        layout = {
            attrs = {
                shader.ATTR_textured_in_position = {format = .FLOAT3},
                shader.ATTR_textured_in_color = {format = .FLOAT4},
                shader.ATTR_textured_in_uv = {format = .FLOAT2}
            }
        },
        /*color_count = 1,
        colors = {
            0 = {
                blend = {
                    enabled = true,
                    src_factor_rgb = .SRC_ALPHA,
                    dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
                    op_rgb = .ADD,
                    src_factor_alpha = .SRC_ALPHA,
                    dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
                    op_alpha = .ADD
                }
            }
        },*/
        depth = {
            write_enabled = true,
            compare = .LESS_EQUAL
        },
        stencil = {
            enabled = true,
            read_mask = 1,
            write_mask = 1,
            back = {
                compare = .LESS_EQUAL
            },
        }
    })

    state.pipeline[1] = sg.make_pipeline({
        shader = state.shader[1],
        primitive_type = .POINTS,
        index_type = .UINT16,
        layout = {
            attrs = {
                shader.ATTR_base_points_in_position = {format = .FLOAT3},
                shader.ATTR_base_points_in_color = {format = .FLOAT4},
                shader.ATTR_textured_in_uv = {format = .FLOAT2}
            }
        },
        depth = {
            write_enabled = true,
            compare = .LESS_EQUAL
        },
        stencil = {
            enabled = true,
            read_mask = 1,
            write_mask = 1,
            back = {
                compare = .LESS_EQUAL
            },
        }
    })

    state.texture = sg_get_image("assets/textures/colormap.png")
    state.sampler = sg.make_sampler({})

    state.pipeline_index = 0
}

frame_cb :: proc "c" () {
    context = default_context

    dt := cast(f32)sapp.frame_duration()

    state.rotation += linalg.to_radians(60.0 * dt)

    proj_mat := linalg.matrix4_perspective_f32(70, sapp.widthf() / sapp.heightf(), 0.0001, 1000)
    model_mat := linalg.matrix4_translate_f32({0.0, -0.10, -2.25}) * linalg.matrix4_from_yaw_pitch_roll(state.rotation, 0.0, 0.0)

    sg.begin_pass({swapchain = shelpers.glue_swapchain(), action = state.pass_action})

    vs_params := shader.Vs_Params {
        mvp = proj_mat * model_mat
    }

    sg.apply_pipeline(state.pipeline[state.pipeline_index])
    
    binding := sg.Bindings{
        vertex_buffers = {0 = state.vertex_buffer},
        index_buffer = state.index_buffer,
        images = {shader.IMG_my_texture = state.texture},
        samplers = {shader.SMP_smp = state.sampler},
    }
    sg.apply_bindings(binding)
    
    sg.apply_uniforms(shader.UB_vs_params, sg_range(&vs_params))
    sg.draw(0, len(obj.faces), 1)

    sg.end_pass()

    sg.commit()
}

cleanup_cb :: proc "c" () {
    context = default_context

    sg.destroy_buffer(state.vertex_buffer)
    for pipeline in state.pipeline {
        sg.destroy_pipeline(pipeline)
    }

    for shader in state.shader {
        sg.destroy_shader(shader)
    }
    sg.destroy_image(state.texture)
    sg.destroy_sampler(state.sampler)
    
    ObjModel_destroy(model)
    free(state)
    free_all(context.temp_allocator)
    sg.shutdown()
}

event_cb :: proc "c" (event: ^sapp.Event) {
    #partial switch event.type {
        case .KEY_DOWN:
        if event.key_code == .ESCAPE do sapp.request_quit()
        if event.key_code == .TAB {
            state.pipeline_index += 1
            state.pipeline_index = state.pipeline_index % len(state.pipeline)
        }
    }
}