package main

import "core:log"
import "base:runtime"
import "core:mem"

/* Sokol import */
import sapp "sokol/app"
import sg "sokol/gfx"
import sglue "sokol/glue"
import shelpers "sokol/helpers"

/* My utils */
import "utils"

default_context: runtime.Context

Globals :: struct {
	shader: sg.Shader,
	pipeline: sg.Pipeline,
	vertex_buffer: sg.Buffer
}

global: ^Globals

main :: proc() {
	context.logger = log.create_console_logger()
	default_context = context

	log.debug("SokEngine")

	sapp.run({
		init_cb = init_cb,
		frame_cb = frame_cb,
		cleanup_cb = cleanup_cb,
		event_cb = event_cb,
		window_title = cstring("SokEngine"),
		width = 800,
		height = 600,
		allocator = sapp.Allocator(shelpers.allocator(&default_context)),
		logger = sapp.Logger(shelpers.logger(&default_context))
	})
}

init_cb :: proc "c"() {
	context = default_context	

	sg.setup({environment = sglue.environment(),
		allocator = sg.Allocator(shelpers.allocator(&default_context)),
		logger = sg.Logger(shelpers.logger(&default_context))
	})

	global = new(Globals)
	global.shader = sg.make_shader(main_shader_desc(sg.query_backend()))
	global.pipeline = sg.make_pipeline({
		shader = global.shader,
		layout = {
			attrs = {
				ATTR_main_in_position = {format = .FLOAT2},
				ATTR_main_in_color = {format = .FLOAT4}
			}
		}
	})

	vertices := []utils.VertexData {
		{position = {0.0, 0.5}, color = {1, 0, 0, 1}},
		{position = {-0.5, -0.5}, color = {0, 1, 0, 1}},
		{position = {0.5, -0.5}, color = {0, 0, 1, 1}},
	}

	global.vertex_buffer = sg.make_buffer({
		data = { ptr = raw_data(vertices), size = len(vertices) * size_of(vertices[0])}
	})
}

// Render code here
frame_cb :: proc "c"() {
	context = default_context

	sg.begin_pass({swapchain = shelpers.glue_swapchain()})
	// Draw here
	sg.apply_pipeline(global.pipeline)
	sg.apply_bindings({
		vertex_buffers = {0 = global.vertex_buffer}
	})
	sg.draw(0, 3, 1)
	
	sg.end_pass()

	sg.commit()
}

cleanup_cb :: proc "c"() {
	context = default_context

	sg.destroy_buffer(global.vertex_buffer)
	sg.destroy_pipeline(global.pipeline)
	sg.destroy_shader(global.shader)

	free(global)
	sg.shutdown()
}

event_cb :: proc "c"(event: ^sapp.Event) {
	context = default_context

	if event.key_code == .ESCAPE {
		sapp.request_quit()
	}
}
