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
    rotation: f32,
    camera: Camera,
    world: []i32
}

state: ^State
obj: ObjData
model: ObjModel
default_context: runtime.Context

mouse_move: Vec2f
key_down: #sparse[sapp.Keycode]bool
indices_len: i32

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

    sapp.show_mouse(false)
    sapp.lock_mouse(true)

    state = new(State)

    state.camera = {
        position = {0.0, 0.0, 2.0},
        target = {0.0, 0.0, 1.0}
    }

    state.pass_action = {
        colors = {
            0 = {load_action = .CLEAR, clear_value = {0.75, 0.75, 0.75, 1.0}}
        }
    }

    state.shader[0] = sg.make_shader(shader.textured_shader_desc(sg.query_backend()))
    state.shader[1] = sg.make_shader(shader.base_points_shader_desc(sg.query_backend()))

    obj = load_ObjData_from_file("assets/models/blaster-a.obj")
    model = ObjModel_from_ObjData(obj, "assets/textures/colormap.png")

    vertices, indices := generate_flat_vertices()

    new_vertices := make([]Vertex, len(obj.faces), context.temp_allocator)
    new_indices := make([]u16, len(obj.faces), context.temp_allocator)

    indices_len = cast(i32)len(indices)

    ObjData_buffers_settings(obj, new_vertices, new_indices)

    state.vertex_buffer = sg.make_buffer({
        data = sg_range(vertices)
    })

    state.index_buffer = sg.make_buffer({
        usage = {
            index_buffer = true
        },
        data = sg_range(indices)
    })

    state.pipeline[0] = sg.make_pipeline({
        shader = state.shader[0],
        primitive_type = .TRIANGLES,
        index_type = .UINT16,
        layout = {
            attrs = {
                shader.ATTR_textured_textured_in_position = {format = .FLOAT3},
                shader.ATTR_textured_textured_in_color = {format = .FLOAT4},
                shader.ATTR_textured_textured_in_uv = {format = .FLOAT2}
            }
        },
        depth = {
            write_enabled = true,
            compare = .LESS_EQUAL
        },
    })

    state.pipeline[1] = sg.make_pipeline({
        shader = state.shader[1],
        primitive_type = .POINTS,
        index_type = .UINT16,
        layout = {
            attrs = {
                shader.ATTR_base_points_base_points_in_position = {format = .FLOAT3},
                shader.ATTR_base_points_base_points_in_color = {format = .FLOAT4},
                shader.ATTR_base_points_base_points_in_uv = {format = .FLOAT2}
            }
        },
        depth = {
            write_enabled = true,
            compare = .LESS_EQUAL
        },
    })

    state.texture = sg_get_image("assets/textures/colormap.png")
    state.sampler = sg.make_sampler({})

    state.pipeline_index = 0

    // GAME
    init_world()
    log.debug(state.world)
}

frame_cb :: proc "c" () {
    context = default_context

    if key_down[.ESCAPE] == true {
        sapp.request_quit()
    }
    if key_down[.LEFT_ALT] == true {
        sapp.lock_mouse(false)
        sapp.show_mouse(true)
    }
    else {
        sapp.lock_mouse(true)
        sapp.show_mouse(false)
    }

    dt := cast(f32)sapp.frame_duration()

    update_camera(dt)

    // state.rotation += linalg.to_radians(60.0 * dt)

    p := linalg.matrix4_perspective_f32(70, sapp.widthf() / sapp.heightf(), 0.0001, 1000)
    m := linalg.matrix4_translate_f32({0.0, -0.10, -2.25}) * linalg.matrix4_from_yaw_pitch_roll(state.rotation, 0.0, 0.0)
    v := linalg.matrix4_look_at_f32(state.camera.position, state.camera.target, {0.0, 1.0, 0.0})
    
    sg.begin_pass({swapchain = shelpers.glue_swapchain(), action = state.pass_action})

    vs_params := shader.Textured_Vs_Params {
        mvp = p * v * m
    }

    sg.apply_pipeline(state.pipeline[0])
    binding := sg.Bindings{
        vertex_buffers = {0 = state.vertex_buffer},
        index_buffer = state.index_buffer,
        images = {shader.IMG_textured_my_texture = state.texture},
        samplers = {shader.SMP_textured_smp = state.sampler},
    }
    sg.apply_bindings(binding)
    sg.apply_uniforms(shader.UB_textured_vs_params, sg_range(&vs_params))
    sg.draw(0, indices_len, 1)

    // sg.apply_pipeline(state.pipeline[1])
    // binding = sg.Bindings{
    //     vertex_buffers = {0 = state.vertex_buffer},
    //     index_buffer = state.index_buffer,
    // }
    // sg.apply_bindings(binding)
    // sg.apply_uniforms(shader.UB_base_points_vs_params, sg_range(&vs_params))
    // sg.draw(0, indices_len, 1)

    sg.end_pass()

    sg.commit()

    mouse_move = {}
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
            if event.key_code == .TAB {
                state.pipeline_index += 1
                state.pipeline_index = state.pipeline_index % len(state.pipeline)
            }
            key_down[event.key_code] = true
        
        case .KEY_UP:
            key_down[event.key_code] = false
        
        case .MOUSE_MOVE:
            mouse_move += {event.mouse_dx, event.mouse_dy}
    }
}