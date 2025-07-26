#!/bin/bash

./tools/sokol-shdc -i shaders/textured_shader.glsl -o source/shaders_code/textured_shader.odin -l glsl430 -f sokol_odin
./tools/sokol-shdc -i shaders/textured_points_shader.glsl -o source/shaders_code/textured_points_shader.odin -l glsl430 -f sokol_odin
./tools/sokol-shdc -i shaders/base_points_shader.glsl -o source/shaders_code/base_points_shader.odin -l glsl430 -f sokol_odin

