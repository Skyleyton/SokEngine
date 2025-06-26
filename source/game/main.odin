package main

import "base:sanitizer"
import "core:log"
import "core:c"
import "base:runtime"

import "utils"

import sapp "../sokol/app"
import sg "../sokol/gfx"
import sglue "../sokol/glue"
import shelpers "../sokol/helpers"

GameState :: struct {
    pass_action: sg.Pass_Action,
    logger: log.Logger,
    vertex_buffer: sg.Buffer,
    index_buffer: sg.Buffer,
    pipeline: [2]sg.Pipeline, // 1 en mode normal, l'autre en wireframe.
    shader: sg.Shader,
    pipeline_index: int
}

state: ^GameState
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

    state = new(GameState)

    state.pass_action = {
        colors = {
            0 = {load_action = .CLEAR, clear_value = {0.75, 0.75, 0.75, 1.0}}
        }
    }

    state.shader = sg.make_shader(main_shader_desc(sg.query_backend()))

    triangle_vertices := []utils.Vertex {
        {position = {-0.5, -0.5, 0.0}, color = {1.0, 0.0, 0.0, 1.0}},
        {position = {0.5, -0.5, 0.0}, color = {1.0, 0.0, 0.0, 1.0}},
        {position = {0.0, 0.5, 0.0}, color = {1.0, 0.0, 0.0, 1.0}},
    }

    quad_vertices := []utils.Vertex {
        {position = {-0.5, -0.5, 0.0}, color = {1.0, 0.0, 0.0, 1.0}},
        {position = {0.5, -0.5, 0.0}, color = {1.0, 0.0, 0.0, 1.0}},
        {position = {0.5, 0.5, 0.0}, color = {1.0, 0.0, 0.0, 1.0}},

        {position = {-0.5, -0.5, 0.0}, color = {1.0, 0.0, 0.0, 1.0}},
        {position = {0.5, 0.5, 0.0}, color = {1.0, 0.0, 0.0, 1.0}},
        {position = {-0.5, 0.5, 0.0}, color = {1.0, 0.0, 0.0, 1.0}},
    }


    state.vertex_buffer = sg.make_buffer({
        data = utils.sg_range(quad_vertices)
    })

    state.pipeline[0] = sg.make_pipeline({
        shader = state.shader,
        primitive_type = .TRIANGLES,
        layout = {
            attrs = {
                ATTR_main_in_position = {format = .FLOAT3},
                ATTR_main_in_color = {format = .FLOAT4}
            }
        }
    })

    state.pipeline[1] = sg.make_pipeline({
        shader = state.shader,
        primitive_type = .LINES,
        layout = {
            attrs = {
                ATTR_main_in_position = {format = .FLOAT3},
                ATTR_main_in_color = {format = .FLOAT4}
            }
        }
    })

    state.pipeline_index = 0
}

frame_cb :: proc "c" () {
    context = default_context

    sg.begin_pass({
        swapchain = shelpers.glue_swapchain(),
        action = state.pass_action,
    })

    sg.apply_pipeline(state.pipeline[state.pipeline_index])
    sg.apply_bindings({
        vertex_buffers = {0 = state.vertex_buffer},
        index_buffer = state.index_buffer
    })

    sg.draw(0, 6, 1)

    sg.end_pass()

    sg.commit()
}

cleanup_cb :: proc "c" () {
    context = default_context

    sg.destroy_buffer(state.vertex_buffer)
    for pipeline in state.pipeline {
        sg.destroy_pipeline(pipeline)
    }
    sg.destroy_shader(state.shader)

    free(state)
    sg.shutdown()
}

event_cb :: proc "c" (event: ^sapp.Event) {
    #partial switch event.type {
        case .KEY_DOWN:
        if event.key_code == .ESCAPE do sapp.request_quit()
        if event.key_code == .TAB do state.pipeline_index = (len(state.pipeline) - 1) - state.pipeline_index
    }
}