package main

import "base:runtime"
import "base:intrinsics"
import t "core:time"
import "core:fmt"
import "core:os"
import "core:math"
import "core:math/linalg"
import "core:math/ease"
import "core:math/rand"
import "core:mem"

import sapp "../sokol/app"
import sg "../sokol/gfx"
import sglue "../sokol/glue"
import slog "../sokol/log"

import stbi "vendor:stb/image"
import stbrp "vendor:stb/rect_pack"
import stbtt "vendor:stb/truetype"

app_state: struct {
	pass_action: sg.Pass_Action,
	pip: sg.Pipeline,
	bind: sg.Bindings,
	input_state: Input_State,
	game: Game_State,
	message_queue: [dynamic]Message,
	user_id: UserID,
	camera_pos: Vector2,
}

UserID :: u64

window_w :: 1280
window_h :: 720

main :: proc() {
	sapp.run({
		init_cb = init,
		frame_cb = frame,
		cleanup_cb = cleanup,
		event_cb = event,
		width = window_w,
		height = window_h,
		window_title = "quad",
		icon = { sokol_default = true },
		logger = { func = slog.func },
	})
}

init :: proc "c" () {
	using linalg, fmt
	context = runtime.default_context()
	
	init_time = t.now()

	sg.setup({
		environment = sglue.environment(),
		logger = { func = slog.func },
		d3d11_shader_debugging = ODIN_DEBUG,
	})
	
	// :init
	init_images()
	init_fonts()
	first_time_init_game_state(&app_state.game)
	
	rand.reset(auto_cast runtime.read_cycle_counter())
	app_state.user_id = rand.uint64()
	// todo - cache this out to disc || replace with steamid in future
	//loggie(app_state.user_id)
	
	// make the vertex buffer
	app_state.bind.vertex_buffers[0] = sg.make_buffer({
		usage = {dynamic_update = true},
		size = size_of(Quad) * len(draw_frame.quads),
	})
	
	// make & fill the index buffer
	index_buffer_count :: MAX_QUADS*6
	indices : [index_buffer_count]u16;
	i := 0;
	for i < index_buffer_count {
		// vertex offset pattern to draw a quad
		// { 0, 1, 2,  0, 2, 3 }
		indices[i + 0] = auto_cast ((i/6)*4 + 0)
		indices[i + 1] = auto_cast ((i/6)*4 + 1)
		indices[i + 2] = auto_cast ((i/6)*4 + 2)
		indices[i + 3] = auto_cast ((i/6)*4 + 0)
		indices[i + 4] = auto_cast ((i/6)*4 + 2)
		indices[i + 5] = auto_cast ((i/6)*4 + 3)
		i += 6;
	}
	app_state.bind.index_buffer = sg.make_buffer({
		usage = {index_buffer = true},
		data = { ptr = &indices, size = size_of(indices) },
	})
	
	// image stuff
	app_state.bind.samplers[SMP_default_sampler] = sg.make_sampler({})
	
	// setup pipeline
	pipeline_desc : sg.Pipeline_Desc = {
		shader = sg.make_shader(quad_shader_desc(sg.query_backend())),
		index_type = .UINT16,
		layout = {
			attrs = {
				ATTR_quad_position = { format = .FLOAT2 },
				ATTR_quad_color0 = { format = .FLOAT4 },
				ATTR_quad_uv0 = { format = .FLOAT2 },
				ATTR_quad_bytes0 = { format = .UBYTE4N },
				ATTR_quad_color_override0 = { format = .FLOAT4 }
			},
		}
	}
	blend_state : sg.Blend_State = {
		enabled = true,
		src_factor_rgb = .SRC_ALPHA,
		dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
		op_rgb = .ADD,
		src_factor_alpha = .ONE,
		dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
		op_alpha = .ADD,
	}
	pipeline_desc.colors[0] = { blend = blend_state }
	app_state.pip = sg.make_pipeline(pipeline_desc)

	// default pass action
	app_state.pass_action = {
		colors = {
			0 = { load_action = .CLEAR, clear_value = { 0, 0, 0, 1 }},
		},
	}
}

//
// :frame
last_time : t.Time
accumulator: f64
sims_per_second :: 1.0 / 30.0

last_sim_time :f64= 0.0

frame :: proc "c" () {	
	// this'll run at refresh rate (most likely)
	// turning vsync off via the swap_interval at runtime isn't supported yet
	// https://github.com/floooh/sokol/issues/693
	// but if we need it when shipping, it's trivial to patch it in
	// For now, don't need to care about this and just force vsync
	
	using runtime, linalg
	context = runtime.default_context()
	
	current_time := t.now()
	frame_time :f64= t.duration_seconds(t.diff(last_time, current_time))
	last_time = current_time
	// should we use this manually calculated dt, or the sokol frame_duration that's smoothed?
	// not sure, will experiment later
	frame_time = sapp.frame_duration()
	//loggie(frame_time)
	
	// only tick the game state at the rate of sims_per_second
	// https://gafferongames.com/post/fix_your_timestep/
	accumulator += frame_time
	for (accumulator >= sims_per_second) {
		sim_game_state(&app_state.game, sims_per_second, app_state.message_queue[:])
		last_sim_time = seconds_since_init()
		clear(&app_state.message_queue)
		accumulator -= sims_per_second
	}
	
	draw_frame.reset = {}
	
	smooth_rendering := true
	if smooth_rendering {
		dt := seconds_since_init()-last_sim_time
		
		temp_gs := new_clone(app_state.game)
		sim_game_state(temp_gs, dt, app_state.message_queue[:])
	
		draw_game_state(temp_gs^, app_state.input_state, &app_state.message_queue)
	} else {
		draw_game_state(app_state.game, app_state.input_state, &app_state.message_queue)
	}
	reset_input_state_for_next_frame(&app_state.input_state)
	
	for i in 0..<draw_frame.sucffed_deferred_quad_count {
		draw_frame.quads[draw_frame.quad_count] = draw_frame.scuffed_deferred_quads[i]
		draw_frame.quad_count += 1
	}
	
	app_state.bind.images[IMG_tex0] = atlas.sg_image
	app_state.bind.images[IMG_tex1] = images[font.img_id].sg_img
	
	sg.update_buffer(
		app_state.bind.vertex_buffers[0],
		{ ptr = &draw_frame.quads[0], size = size_of(Quad) * len(draw_frame.quads) }
	)
	sg.begin_pass({ action = app_state.pass_action, swapchain = sglue.swapchain() })
	sg.apply_pipeline(app_state.pip)
	sg.apply_bindings(app_state.bind)
	sg.draw(0, 6*draw_frame.quad_count, 1)
	sg.end_pass()
	sg.commit()
	
	free_all(context.temp_allocator)
}

cleanup :: proc "c" () {
	context = runtime.default_context()
	sg.shutdown()
}

//
// :input

Key_Code :: enum {
	// copied from sokol_app
	INVALID = 0,
	SPACE = 32,
	APOSTROPHE = 39,
	COMMA = 44,
	MINUS = 45,
	PERIOD = 46,
	SLASH = 47,
	_0 = 48,
	_1 = 49,
	_2 = 50,
	_3 = 51,
	_4 = 52,
	_5 = 53,
	_6 = 54,
	_7 = 55,
	_8 = 56,
	_9 = 57,
	SEMICOLON = 59,
	EQUAL = 61,
	A = 65,
	B = 66,
	C = 67,
	D = 68,
	E = 69,
	F = 70,
	G = 71,
	H = 72,
	I = 73,
	J = 74,
	K = 75,
	L = 76,
	M = 77,
	N = 78,
	O = 79,
	P = 80,
	Q = 81,
	R = 82,
	S = 83,
	T = 84,
	U = 85,
	V = 86,
	W = 87,
	X = 88,
	Y = 89,
	Z = 90,
	LEFT_BRACKET = 91,
	BACKSLASH = 92,
	RIGHT_BRACKET = 93,
	GRAVE_ACCENT = 96,
	WORLD_1 = 161,
	WORLD_2 = 162,
	ESCAPE = 256,
	ENTER = 257,
	TAB = 258,
	BACKSPACE = 259,
	INSERT = 260,
	DELETE = 261,
	RIGHT = 262,
	LEFT = 263,
	DOWN = 264,
	UP = 265,
	PAGE_UP = 266,
	PAGE_DOWN = 267,
	HOME = 268,
	END = 269,
	CAPS_LOCK = 280,
	SCROLL_LOCK = 281,
	NUM_LOCK = 282,
	PRINT_SCREEN = 283,
	PAUSE = 284,
	F1 = 290,
	F2 = 291,
	F3 = 292,
	F4 = 293,
	F5 = 294,
	F6 = 295,
	F7 = 296,
	F8 = 297,
	F9 = 298,
	F10 = 299,
	F11 = 300,
	F12 = 301,
	F13 = 302,
	F14 = 303,
	F15 = 304,
	F16 = 305,
	F17 = 306,
	F18 = 307,
	F19 = 308,
	F20 = 309,
	F21 = 310,
	F22 = 311,
	F23 = 312,
	F24 = 313,
	F25 = 314,
	KP_0 = 320,
	KP_1 = 321,
	KP_2 = 322,
	KP_3 = 323,
	KP_4 = 324,
	KP_5 = 325,
	KP_6 = 326,
	KP_7 = 327,
	KP_8 = 328,
	KP_9 = 329,
	KP_DECIMAL = 330,
	KP_DIVIDE = 331,
	KP_MULTIPLY = 332,
	KP_SUBTRACT = 333,
	KP_ADD = 334,
	KP_ENTER = 335,
	KP_EQUAL = 336,
	LEFT_SHIFT = 340,
	LEFT_CONTROL = 341,
	LEFT_ALT = 342,
	LEFT_SUPER = 343,
	RIGHT_SHIFT = 344,
	RIGHT_CONTROL = 345,
	RIGHT_ALT = 346,
	RIGHT_SUPER = 347,
	MENU = 348,
	
	// randy: adding the mouse buttons on the end here so we can unify the enum and not need to use sapp.Mousebutton
	LEFT_MOUSE = 400,
	RIGHT_MOUSE = 401,
	MIDDLE_MOUSE = 402,
}
MAX_KEYCODES :: sapp.MAX_KEYCODES
map_sokol_mouse_button :: proc "c" (sokol_mouse_button: sapp.Mousebutton) -> Key_Code {
	#partial switch sokol_mouse_button {
		case .LEFT: return .LEFT_MOUSE
		case .RIGHT: return .RIGHT_MOUSE
		case .MIDDLE: return .MIDDLE_MOUSE
	}
	return nil
}

Input_State_Flags :: enum {
	down,
	just_pressed,
	just_released,
	repeat,
}

Input_State :: struct {
	keys: [MAX_KEYCODES]bit_set[Input_State_Flags],
}

reset_input_state_for_next_frame :: proc(state: ^Input_State) {
	for &set in state.keys {
		set -= {.just_pressed, .just_released, .repeat}
	}
}

key_just_pressed :: proc(input_state: Input_State, code: Key_Code) -> bool {
	return .just_pressed in input_state.keys[code]
}
key_down :: proc(input_state: Input_State, code: Key_Code) -> bool {
	return .down in input_state.keys[code]
}
key_just_released :: proc(input_state: Input_State, code: Key_Code) -> bool {
	return .just_released in input_state.keys[code]
}
key_repeat :: proc(input_state: Input_State, code: Key_Code) -> bool {
	return .repeat in input_state.keys[code]
}

event :: proc "c" (event: ^sapp.Event) {
	// see this for example of events: https://floooh.github.io/sokol-html5/events-sapp.html
	input_state := &app_state.input_state
	
	#partial switch event.type {
		case .MOUSE_UP:
		if .down in input_state.keys[map_sokol_mouse_button(event.mouse_button)] {
			input_state.keys[map_sokol_mouse_button(event.mouse_button)] -= { .down }
			input_state.keys[map_sokol_mouse_button(event.mouse_button)] += { .just_released }
		}
		case .MOUSE_DOWN:
		if !(.down in input_state.keys[map_sokol_mouse_button(event.mouse_button)]) {
			input_state.keys[map_sokol_mouse_button(event.mouse_button)] += { .down, .just_pressed }
		}
	
		case .KEY_UP:
		if .down in input_state.keys[event.key_code] {
			input_state.keys[event.key_code] -= { .down }
			input_state.keys[event.key_code] += { .just_released }
		}
		case .KEY_DOWN:
		if !event.key_repeat && !(.down in input_state.keys[event.key_code]) {
			input_state.keys[event.key_code] += { .down, .just_pressed }
		}
		if event.key_repeat {
			input_state.keys[event.key_code] += { .repeat }
		}
	}
}

//
// :UTILS

DEFAULT_UV :: v4{0, 0, 1, 1}
Vector2i :: [2]int
Vector2 :: [2]f32
Vector3 :: [3]f32
Vector4 :: [4]f32
v2 :: Vector2
v3 :: Vector3
v4 :: Vector4
Matrix4 :: linalg.Matrix4f32;

COLOR_WHITE :: Vector4 {1,1,1,1}
COLOR_RED :: Vector4 {1,0,0,1}

// might do something with these later on
loggie :: fmt.println // log is already used........
log_error :: fmt.println
log_warning :: fmt.println

init_time: t.Time;
seconds_since_init :: proc() -> f64 {
	using t
	if init_time._nsec == 0 {
		log_error("invalid time")
		return 0
	}
	return duration_seconds(since(init_time))
}

xform_translate :: proc(pos: Vector2) -> Matrix4 {
	return linalg.matrix4_translate(v3{pos.x, pos.y, 0})
}
xform_rotate :: proc(angle: f32) -> Matrix4 {
	return linalg.matrix4_rotate(math.to_radians(angle), v3{0,0,1})
}
xform_scale :: proc(scale: Vector2) -> Matrix4 {
	return linalg.matrix4_scale(v3{scale.x, scale.y, 1});
}

Pivot :: enum {
	bottom_left,
	bottom_center,
	bottom_right,
	center_left,
	center_center,
	center_right,
	top_left,
	top_center,
	top_right,
}
scale_from_pivot :: proc(pivot: Pivot) -> Vector2 {
	switch pivot {
		case .bottom_left: return v2{0.0, 0.0}
		case .bottom_center: return v2{0.5, 0.0}
		case .bottom_right: return v2{1.0, 0.0}
		case .center_left: return v2{0.0, 0.5}
		case .center_center: return v2{0.5, 0.5}
		case .center_right: return v2{1.0, 0.5}
		case .top_center: return v2{0.5, 1.0}
		case .top_left: return v2{0.0, 1.0}
		case .top_right: return v2{1.0, 1.0}
	}
	return {};
}

sine_breathe :: proc(p: $T) -> T where intrinsics.type_is_float(T) {
	return (math.sin((p - .25) * 2.0 * math.PI) / 2.0) + 0.5
}

//
// :RENDER STUFF
//
// API ordered highest -> lowest level

draw_sprite :: proc(pos: Vector2, img_id: Image_Id, pivot:= Pivot.bottom_left, xform := Matrix4(1), color_override:= v4{0,0,0,0}, deferred:=false,) {
	image := images[img_id]
	size := v2{auto_cast image.width, auto_cast image.height}
	
	xform0 := Matrix4(1)
	xform0 *= xform_translate(pos)
	xform0 *= xform // we slide in here because rotations + scales work nicely at this point
	xform0 *= xform_translate(size * -scale_from_pivot(pivot))
	
	draw_rect_xform(xform0, size, img_id=img_id, color_override=color_override, deferred=deferred)
}

draw_rect_aabb :: proc(
	pos: Vector2,
	size: Vector2,
	col: Vector4=COLOR_WHITE,
	uv: Vector4=DEFAULT_UV,
	img_id: Image_Id=.nil,
	color_override:= v4{0,0,0,0},
	deferred:=false,
) {
	xform := linalg.matrix4_translate(v3{pos.x, pos.y, 0})
	draw_rect_xform(xform, size, col, uv, img_id, color_override, deferred=deferred)
}

draw_rect_xform :: proc(
	xform: Matrix4,
	size: Vector2,
	col: Vector4=COLOR_WHITE,
	uv: Vector4=DEFAULT_UV,
	img_id: Image_Id=.nil,
	color_override:= v4{0,0,0,0},
	deferred:=false,
) {
	draw_rect_projected(draw_frame.projection * draw_frame.camera_xform * xform, size, col, uv, img_id, color_override, deferred=deferred)
}

Vertex :: struct {
	pos: Vector2,
	col: Vector4,
	uv: Vector2,
	tex_index: u8,
	_pad: [3]u8,
	color_override: Vector4,
}

Quad :: [4]Vertex;

MAX_QUADS :: 8192
MAX_VERTS :: MAX_QUADS * 4

Draw_Frame :: struct {

	scuffed_deferred_quads: [MAX_QUADS/4]Quad,
	quads: [MAX_QUADS]Quad,
	projection: Matrix4,
	camera_xform: Matrix4,
	
	using reset: struct {
		quad_count: int,
		sucffed_deferred_quad_count: int,
	}
}
draw_frame : Draw_Frame;

// below is the lower level draw rect stuff

draw_rect_projected :: proc(
	world_to_clip: Matrix4,
	size: Vector2,
	col: Vector4=COLOR_WHITE,
	uv: Vector4=DEFAULT_UV,
	img_id: Image_Id=.nil,
	color_override:= v4{0,0,0,0},
	deferred:=false,
) {

	bl := v2{ 0, 0 }
	tl := v2{ 0, size.y }
	tr := v2{ size.x, size.y }
	br := v2{ size.x, 0 }
	
	uv0 := uv
	if uv == DEFAULT_UV {
		uv0 = images[img_id].atlas_uvs
	}
	
	tex_index :u8= images[img_id].tex_index
	if img_id == .nil {
		tex_index = 255 // bypasses texture sampling
	}
	
	draw_quad_projected(world_to_clip, {bl, tl, tr, br}, {col, col, col, col}, {uv0.xy, uv0.xw, uv0.zw, uv0.zy}, {tex_index,tex_index,tex_index,tex_index}, {color_override,color_override,color_override,color_override}, deferred=deferred)

}

draw_quad_projected :: proc(
	world_to_clip:   Matrix4, 
	positions:       [4]Vector2,
	colors:          [4]Vector4,
	uvs:             [4]Vector2,
	tex_indicies:       [4]u8,
	//flags:           [4]Quad_Flags,
	color_overrides: [4]Vector4,
	//hsv:             [4]Vector3
	deferred:=false,
) {
	using linalg

	if draw_frame.quad_count >= MAX_QUADS {
		log_error("max quads reached")
		return
	}
		
	verts := cast(^[4]Vertex)&draw_frame.quads[draw_frame.quad_count];
	if deferred {
		// randy: me no like this, but it was needed for #debug_draw_on_sim so we could see what's
		// happening.
		verts = cast(^[4]Vertex)&draw_frame.scuffed_deferred_quads[draw_frame.sucffed_deferred_quad_count];
		draw_frame.sucffed_deferred_quad_count += 1
	} else {
		draw_frame.quad_count += 1;
	}
	
	
	verts[0].pos = (world_to_clip * Vector4{positions[0].x, positions[0].y, 0.0, 1.0}).xy
	verts[1].pos = (world_to_clip * Vector4{positions[1].x, positions[1].y, 0.0, 1.0}).xy
	verts[2].pos = (world_to_clip * Vector4{positions[2].x, positions[2].y, 0.0, 1.0}).xy
	verts[3].pos = (world_to_clip * Vector4{positions[3].x, positions[3].y, 0.0, 1.0}).xy
	
	verts[0].col = colors[0]
	verts[1].col = colors[1]
	verts[2].col = colors[2]
	verts[3].col = colors[3]

	verts[0].uv = uvs[0]
	verts[1].uv = uvs[1]
	verts[2].uv = uvs[2]
	verts[3].uv = uvs[3]
	
	verts[0].tex_index = tex_indicies[0]
	verts[1].tex_index = tex_indicies[1]
	verts[2].tex_index = tex_indicies[2]
	verts[3].tex_index = tex_indicies[3]
	
	verts[0].color_override = color_overrides[0]
	verts[1].color_override = color_overrides[1]
	verts[2].color_override = color_overrides[2]
	verts[3].color_override = color_overrides[3]
}

//
// :IMAGE STUFF
//
Image_Id :: enum {
	nil,
	player,
	crawler,
}

Image :: struct {
	width, height: i32,
	tex_index: u8,
	sg_img: sg.Image,
	data: [^]byte,
	atlas_uvs: Vector4,
}
images: [128]Image
image_count: int

init_images :: proc() {
	using fmt

	img_dir := "res/images/"
	
	highest_id := 0;
	for img_name, id in Image_Id {
		if id == 0 { continue }
		
		if id > highest_id {
			highest_id = id
		}
	
		path := tprint(img_dir, img_name, ".png", sep="")
		fmt.println(path)
		png_data, succ := os.read_entire_file(path)
		assert(succ)
		
		stbi.set_flip_vertically_on_load(1)
		width, height, channels: i32
		img_data := stbi.load_from_memory(raw_data(png_data), auto_cast len(png_data), &width, &height, &channels, 4)
		assert(img_data != nil, "stbi load failed, invalid image?")
			
		img : Image;
		img.width = width
		img.height = height
		img.data = img_data
		
		images[id] = img
	}
	image_count = highest_id + 1
	
	pack_images_into_atlas()
}

Atlas :: struct {
	w, h: int,
	sg_image: sg.Image,
}
atlas: Atlas
// We're hardcoded to use just 1 atlas now since I don't think we'll need more
// It would be easy enough to extend though. Just add in more texture slots in the shader
pack_images_into_atlas :: proc() {

	// TODO - add a single pixel of padding for each so we avoid the edge oversampling issue

	// 8192 x 8192 is the WGPU recommended max I think
	atlas.w = 128
	atlas.h = 128
	
	cont : stbrp.Context
	nodes : [128]stbrp.Node // #volatile with atlas.w
	stbrp.init_target(&cont, auto_cast atlas.w, auto_cast atlas.h, &nodes[0], auto_cast atlas.w)
	
	rects : [dynamic]stbrp.Rect
	for img, id in images {
		if img.width == 0 {
			continue
		}
		append(&rects, stbrp.Rect{ id=auto_cast id, w=auto_cast img.width, h=auto_cast img.height })
	}
	
	succ := stbrp.pack_rects(&cont, &rects[0], auto_cast len(rects))
	if succ == 0 {
		assert(false, "failed to pack all the rects, ran out of space?")
	}
	
	// allocate big atlas
	raw_data, err := mem.alloc(atlas.w * atlas.h * 4)
	defer mem.free(raw_data)
	mem.set(raw_data, 255, atlas.w*atlas.h*4)
	
	// copy rect row-by-row into destination atlas
	for rect in rects {
		img := &images[rect.id]
		
		// copy row by row into atlas
		for row in 0..<rect.h {
			src_row := mem.ptr_offset(&img.data[0], row * rect.w * 4)
			dest_row := mem.ptr_offset(cast(^u8)raw_data, ((rect.y + row) * auto_cast atlas.w + rect.x) * 4)
			mem.copy(dest_row, src_row, auto_cast rect.w * 4)
		}
		
		// yeet old data
		stbi.image_free(img.data)
		img.data = nil;
		
		// img.atlas_x = auto_cast rect.x
		// img.atlas_y = auto_cast rect.y
		
		img.atlas_uvs.x = cast(f32)rect.x / cast(f32)atlas.w
		img.atlas_uvs.y = cast(f32)rect.y / cast(f32)atlas.h
		img.atlas_uvs.z = img.atlas_uvs.x + cast(f32)img.width / cast(f32)atlas.w
		img.atlas_uvs.w = img.atlas_uvs.y + cast(f32)img.height / cast(f32)atlas.h
	}
	
	stbi.write_png("atlas.png", auto_cast atlas.w, auto_cast atlas.h, 4, raw_data, 4 * auto_cast atlas.w)
	
	// setup image for GPU
	desc : sg.Image_Desc
	desc.width = auto_cast atlas.w
	desc.height = auto_cast atlas.h
	desc.pixel_format = .RGBA8
	desc.data.subimage[0][0] = {ptr=raw_data, size=auto_cast (atlas.w*atlas.h*4)}
	atlas.sg_image = sg.make_image(desc)
	if atlas.sg_image.id == sg.INVALID_ID {
		log_error("failed to make image")
	}
}

//
// :FONT
//
draw_text :: proc(pos: Vector2, text: string, scale:= 1.0) {
	using stbtt
	
	x: f32
	y: f32

	for char in text {
		
		advance_x: f32
		advance_y: f32
		q: aligned_quad
		GetBakedQuad(&font.char_data[0], font_bitmap_w, font_bitmap_h, cast(i32)char - 32, &advance_x, &advance_y, &q, false)
		// this is the the data for the aligned_quad we're given, with y+ going down
		// x0, y0,     s0, t0, // top-left
		// x1, y1,     s1, t1, // bottom-right
		
		
		size := v2{ abs(q.x0 - q.x1), abs(q.y0 - q.y1) }
		
		bottom_left := v2{ q.x0, -q.y1 }
		top_right := v2{ q.x1, -q.y0 }
		assert(bottom_left + size == top_right)
		
		offset_to_render_at := v2{x,y} + bottom_left
		
		uv := v4{ q.s0, q.t1,
							q.s1, q.t0 }
		
		xform := Matrix4(1)
		xform *= xform_translate(pos)
		xform *= xform_scale(v2{auto_cast scale, auto_cast scale})
		xform *= xform_translate(offset_to_render_at)
		draw_rect_xform(xform, size, uv=uv, img_id=font.img_id)
		
		x += advance_x
		y += -advance_y
	}

}

font_bitmap_w :: 256
font_bitmap_h :: 256
char_count :: 96
Font :: struct {
	char_data: [char_count]stbtt.bakedchar,
	img_id: Image_Id,
}
font: Font

init_fonts :: proc() {
	using stbtt
	
	bitmap, _ := mem.alloc(font_bitmap_w * font_bitmap_h)
	font_height := 15 // for some reason this only bakes properly at 15 ? it's a 16px font dou...
	path := "res/fonts/alagard.ttf"
	ttf_data, err := os.read_entire_file(path)
	assert(ttf_data != nil, "failed to read font")
	
	ret := BakeFontBitmap(raw_data(ttf_data), 0, auto_cast font_height, auto_cast bitmap, font_bitmap_w, font_bitmap_h, 32, char_count, &font.char_data[0])
	assert(ret > 0, "not enough space in bitmap")
	
	stbi.write_png("font.png", auto_cast font_bitmap_w, auto_cast font_bitmap_h, 1, bitmap, auto_cast font_bitmap_w)
	
	// setup font atlas so we can use it in the shader
	desc : sg.Image_Desc
	desc.width = auto_cast font_bitmap_w
	desc.height = auto_cast font_bitmap_h
	desc.pixel_format = .R8
	desc.data.subimage[0][0] = {ptr=bitmap, size=auto_cast (font_bitmap_w*font_bitmap_h)}
	sg_img := sg.make_image(desc)
	if sg_img.id == sg.INVALID_ID {
		log_error("failed to make image")
	}
	
	id := store_image(font_bitmap_w, font_bitmap_h, 1, sg_img)
	font.img_id = id
}
// kind scuffed...
// but I'm abusing the Images to store the font atlas by just inserting it at the end with the next id
store_image :: proc(w: int, h: int, tex_index: u8, sg_img: sg.Image) -> Image_Id {

	img : Image
	img.width = auto_cast w
	img.height = auto_cast h
	img.tex_index = tex_index
	img.sg_img = sg_img
	img.atlas_uvs = DEFAULT_UV
	
	id := image_count
	images[id] = img
	image_count += 1
	
	return auto_cast id
}

//
// :GAME


// :tile
Tile :: struct {
	type: u8,
	debug_tile:bool,
}

// #volatile with the map image dimensions
WORLD_W :: 128
WORLD_H :: 80

Tile_Pos :: [2]int

get_tile :: proc(gs: Game_State, tile_pos: Tile_Pos) -> Tile {
	local := world_tile_to_array_tile_pos(tile_pos)
	return gs.tiles[local.x + local.y * WORLD_W]
}
get_tile_pointer :: proc(gs: ^Game_State, tile_pos: Tile_Pos) -> ^Tile {
	local := world_tile_to_array_tile_pos(tile_pos)
	return &gs.tiles[local.x + local.y * WORLD_W]
}

get_tiles_in_box_radius :: proc(world_pos: Vector2, box_radius: Vector2i) -> []Tile_Pos {

	tiles: [dynamic]Tile_Pos
	tiles.allocator = context.temp_allocator
	
	tile_pos := world_pos_to_tile_pos(world_pos)
	
	for x := tile_pos.x - box_radius.x; x < tile_pos.x + box_radius.x; x += 1 {
		for y := tile_pos.y - box_radius.y; y < tile_pos.y + box_radius.y; y += 1 {
			append(&tiles, (Tile_Pos){x, y})
		}
	}
	
	return tiles[:]
}

// :tile load
load_map_into_tiles :: proc(tiles: []Tile) {

	png_data, succ := os.read_entire_file("res/map.png")
	assert(succ, "map.png not found")

	width, height, channels: i32
	img_data :[^]byte= stbi.load_from_memory(raw_data(png_data), auto_cast len(png_data), &width, &height, &channels, 4)
	
	for x in 0..<WORLD_W {
		for y in 0..<WORLD_H {
		
			index := (x + y * WORLD_W) * 4
			pixel : []u8 = img_data[index:index+4]
			
			r := pixel[0]
			g := pixel[1]
			b := pixel[2]
			a := pixel[3]
			
			t := &tiles[x + y * WORLD_W]
			
			if r == 255 {
				t.type = 1
			}
		}
	}

}

world_tile_to_array_tile_pos :: proc(world_tile: Tile_Pos) -> Vector2i {
	x_index := world_tile.x + int(math.floor(f32(WORLD_W * 0.5)))
	y_index := world_tile.y + int(math.floor(f32(WORLD_H * 0.5)))
	return { x_index, y_index }
}

array_tile_pos_to_world_tile :: proc(x: int, y: int) -> Tile_Pos {
	x_index := x - int(math.floor(f32(WORLD_W * 0.5)))
	y_index := y - int(math.floor(f32(WORLD_H * 0.5)))
	return (Tile_Pos){ x_index, y_index }
}

TILE_LENGTH :: 16

tile_pos_to_world_pos :: proc(tile_pos: Tile_Pos) -> Vector2 {
	return (Vector2){ auto_cast tile_pos.x * TILE_LENGTH, auto_cast tile_pos.y * TILE_LENGTH }
}

world_pos_to_tile_pos :: proc(world_pos: Vector2) -> Tile_Pos {
	return (Tile_Pos){ auto_cast math.floor(world_pos.x / TILE_LENGTH), auto_cast math.floor(world_pos.y / TILE_LENGTH) }
}

// :tile
draw_tiles :: proc(gs: Game_State, player: Entity) {

	player_tile := world_pos_to_tile_pos(player.pos)
	
	tile_view_radius_x := 24
	tile_view_radius_y := 20
	
	tiles := get_tiles_in_box_radius(player.pos, {24, 20})
	for tile_pos in tiles {
		tile_pos_world := tile_pos_to_world_pos(tile_pos)
			
		tile := get_tile(gs, tile_pos)
		if tile.type != 0 {
			col := COLOR_WHITE
			if tile.debug_tile {
				col = COLOR_RED
			}
			draw_rect_aabb(tile_pos_world, v2{TILE_LENGTH, TILE_LENGTH}, col=col)
		}
	}
}

first_time_init_game_state :: proc(gs: ^Game_State) {
	load_map_into_tiles(gs.tiles[:])
}


Game_State :: struct {
	tick_index: u64,
	entities: [128]Entity,
	latest_entity_handle: Entity_Handle,
	
	tiles: [WORLD_W * WORLD_H]Tile,
}

Message_Kind :: enum {
	move_left,
	move_right,
	jump,
	create_player,
}

Message :: struct {
	kind: Message_Kind,
	from_entity: Entity_Handle,
	using variant: struct #raw_union {
		create_player: struct {
			user_id: UserID,
		}
	}
}

add_message :: proc(messages: ^[dynamic]Message, new_message: Message) -> ^Message {

	for msg in messages {
		#partial switch msg.kind {
			case:
			if msg.kind == new_message.kind {
				return nil;
			}
		}
	}

	index := append(messages, new_message) - 1
	return &messages[index]
}

//
// :ENTITY

Entity_Flags :: enum {
	allocated,
	physics
}

Entity_Kind :: enum {
	nil,
	player,
}

Entity :: struct {
	id: Entity_Handle,
	kind: Entity_Kind,
	flags: bit_set[Entity_Flags],
	pos: Vector2,
	vel: Vector2,
	acc: Vector2,
	user_id: UserID,
	
	frame: struct{
		input_axis: Vector2,
	}
}

Entity_Handle :: u64

handle_to_entity :: proc(gs: ^Game_State, handle: Entity_Handle) -> ^Entity {
	for &en in gs.entities {
		if (.allocated in en.flags) && en.id == handle {
			return &en
		}
	}
	log_error("entity no longer valid")
	return nil
}

entity_to_handle :: proc(gs: Game_State, entity: Entity) -> Entity_Handle {
	return entity.id
}

entity_create :: proc(gs:^Game_State) -> ^Entity {
	spare_en : ^Entity
	for &en in gs.entities {
		if !(.allocated in en.flags) {
			spare_en = &en
			break
		}
	}
	
	if spare_en == nil {
		log_error("ran out of entities, increase size")
		return nil
	} else {
		spare_en.flags = { .allocated }
		gs.latest_entity_handle += 1
		spare_en.id = gs.latest_entity_handle
		return spare_en
	}
}

entity_destroy :: proc(gs:^Game_State, entity: ^Entity) {
	mem.set(entity, 0, size_of(Entity))
}

setup_player :: proc(e: ^Entity) {
	e.kind = .player
	e.flags |= { .physics }
}


//
// THE GAMEPLAY LINE
//

//
// :sim

sim_game_state :: proc(gs: ^Game_State, delta_t: f64, messages: []Message) {
	defer gs.tick_index += 1
	
	for &en in gs.entities {
		en.frame = {}
	}
	
	for msg in messages {
		#partial switch msg.kind {
			case .create_player: {
			
				user_id := msg.create_player.user_id
				assert(user_id != 0, "invalid user id")
				
				existing_user := false
				for en in gs.entities {
					if en.user_id == user_id {
						existing_user = true
						break
					}
				}
			
				if !existing_user {
					e := entity_create(gs)
					setup_player(e)
					e.user_id = user_id
				}
				
			}
		}
	}
	
	for msg in messages {
		en := handle_to_entity(gs, msg.from_entity)
		#partial switch msg.kind {
			case .move_left: {
				en.frame.input_axis.x += -1.0
			}
			case .move_right: {
				en.frame.input_axis.x += 1.0
			}
			case .jump: {
				en.vel.y = 300.0
			}
		}
	}
	
	for &en in gs.entities {
		// :player
		if en.kind == .player {
			speed := 200.0
			//loggie(en.frame.input_axis)
			//en.pos += en.frame.input_axis * auto_cast (speed * delta_t)
			en.vel.x = en.frame.input_axis.x * auto_cast (speed)
		}
	}
	
	// :physics
	for &en in gs.entities {
		if .physics in en.flags {
		
			en.acc.y -= 980.0
			
			en.vel += en.acc * f32(delta_t)
			next_pos := en.pos + en.vel * f32(delta_t)
			en.acc = {}
			
			tiles := get_tiles_in_box_radius(next_pos, {4, 4})
			for tile_pos in tiles {
				
				tile := get_tile(gs^, tile_pos)
				if tile.type == 0 {
					continue
				}
			
				self_aabb := get_aabb_from_entity(en)
				self_aabb = aabb_shift(self_aabb, next_pos)
				against_aabb := aabb_make(tile_pos_to_world_pos(tile_pos), v2{TILE_LENGTH,TILE_LENGTH}, Pivot.bottom_left)
				// #debug_draw_on_sim
				//draw_rect_aabb(self_aabb.xy, (self_aabb.zw-self_aabb.xy), col=COLOR_RED, deferred=true)
				//draw_rect_aabb(against_aabb.xy, (against_aabb.zw-against_aabb.xy), col=COLOR_RED, deferred=true)
				
				collide, depth := aabb_collide_aabb(self_aabb, against_aabb)
				if collide {
					next_pos += depth
					
					if math.abs(linalg.vector_dot(linalg.normalize(depth), v2{0, 1})) > 0.9 {
						en.vel.y = 0
					}
				}
				
				
			}
			
			en.pos = next_pos
			
			// auto step
			if en.vel.x != 0 {
			
				wall_sample_pos := en.pos + v2{0, TILE_LENGTH * 0.5} + linalg.normalize(en.vel) * 10
				tile_pos := world_pos_to_tile_pos(wall_sample_pos)
				
				tile_next := get_tile_pointer(gs, tile_pos)
				//tile_next.debug_tile = true
				tile_up := get_tile_pointer(gs, tile_pos + {0, 1})
				//tile_up.debug_tile = true
				
				if tile_next.type != 0 && tile_up.type == 0 {
					en.pos.y += TILE_LENGTH
				}
			}
			
			// if en.pos.y < 0 {
			// 	en.pos.y = 0
			// 	en.vel.y = 0
			// }
			
		}
	}
}

//
// :draw :user

draw_game_state :: proc(gs: Game_State, input_state: Input_State, messages_out: ^[dynamic]Message) {
	using linalg
	
	draw_frame.projection = matrix_ortho3d_f32(window_w * -0.5, window_w * 0.5, window_h * -0.5, window_h * 0.5, -1, 1)
	
	// :camera
	{
		draw_frame.camera_xform = Matrix4(1)
		draw_frame.camera_xform *= xform_scale(2)
		draw_frame.camera_xform *= xform_translate(app_state.camera_pos)
	}
	alpha := f32(math.mod(seconds_since_init() * 0.2, 1.0))
	xform := xform_rotate(alpha * 360.0)
	xform *= xform_scale(1.0 + 1 * sine_breathe(alpha))
	draw_sprite(v2{0, 0}, .crawler, xform=xform, pivot=.center_center)

	// Trouver un meilleur endroit pour placer les inputs.
	if key_just_pressed(app_state.input_state, .ESCAPE) {
		sapp.request_quit()
	}
}

draw_player :: proc(en: Entity) {

	img := Image_Id.player
	
	xform := Matrix4(1)
	xform *= xform_scale(v2{1,1})
	
	draw_sprite(en.pos, img, pivot=.bottom_center, xform=xform)

}

//
// :COLLISION STUFF
//

AABB :: Vector4
get_aabb_from_entity :: proc(en: Entity) -> AABB {

	#partial switch en.kind {
		case .player: {
			return aabb_make(v2{16, 32}, .bottom_center)
		}
	}

	return {}
}

aabb_collide_aabb :: proc(a: AABB, b: AABB) -> (bool, Vector2) {
	// Calculate overlap on each axis
	dx := (a.z + a.x) / 2 - (b.z + b.x) / 2;
	dy := (a.w + a.y) / 2 - (b.w + b.y) / 2;

	overlap_x := (a.z - a.x) / 2 + (b.z - b.x) / 2 - abs(dx);
	overlap_y := (a.w - a.y) / 2 + (b.w - b.y) / 2 - abs(dy);

	// If there is no overlap on any axis, there is no collision
	if overlap_x <= 0 || overlap_y <= 0 {
		return false, Vector2{};
	}

	// Find the penetration vector
	penetration := Vector2{};
	if overlap_x < overlap_y {
		penetration.x = overlap_x if dx > 0 else -overlap_x;
	} else {
		penetration.y = overlap_y if dy > 0 else -overlap_y;
	}

	return true, penetration;
}

aabb_get_center :: proc(a: Vector4) -> Vector2 {
	min := a.xy;
	max := a.zw;
	return { min.x + 0.5 * (max.x-min.x), min.y + 0.5 * (max.y-min.y) };
}

// aabb_make :: proc(pos_x: float, pos_y: float, size_x: float, size_y: float) -> Vector4 {
// 	return {pos_x, pos_y, pos_x + size_x, pos_y + size_y};
// }
aabb_make_with_pos :: proc(pos: Vector2, size: Vector2, pivot: Pivot) -> Vector4 {
	aabb := (Vector4){0,0,size.x,size.y};
	aabb = aabb_shift(aabb, pos - scale_from_pivot(pivot) * size);
	return aabb;
}
aabb_make_with_size :: proc(size: Vector2, pivot: Pivot) -> Vector4 {
	return aabb_make({}, size, pivot);
}

aabb_make :: proc{
	aabb_make_with_pos,
	aabb_make_with_size,
}

aabb_shift :: proc(aabb: Vector4, amount: Vector2) -> Vector4 {
	return {aabb.x + amount.x, aabb.y + amount.y, aabb.z + amount.x, aabb.w + amount.y};
}

aabb_contains :: proc(aabb: Vector4, p: Vector2) -> bool {
	return (p.x >= aabb.x) && (p.x <= aabb.z) &&
           (p.y >= aabb.y) && (p.y <= aabb.w);
}


animate_to_target_f32 :: proc(value: ^f32, target: f32, delta_t: f32, rate:f32= 15.0, good_enough:f32= 0.001) -> bool
{
	value^ += (target - value^) * (1.0 - math.pow_f32(2.0, -rate * delta_t));
	if almost_equals(value^, target, good_enough)
	{
		value^ = target;
		return true; // reached
	}
	return false;
}

animate_to_target_v2 :: proc(value: ^Vector2, target: Vector2, delta_t: f32, rate :f32= 15.0)
{
	value.x += (target.x - value.x) * (1.0 - math.pow_f32(2.0, -rate * delta_t));
	value.y += (target.y - value.y) * (1.0 - math.pow_f32(2.0, -rate * delta_t));
}

almost_equals :: proc(a: f32, b: f32, epsilon: f32 = 0.001) -> bool
{
	return abs(a - b) <= epsilon;
}
