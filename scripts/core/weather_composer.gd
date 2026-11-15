extends Node
## Weather-satellite compositor: merges the whole-world pictures of GOES-West, GOES-East and Himawari into one picture
## by drawing them through `shaders/weather_composite.gdshader` into an off-screen SubViewport and reading the result
## back. Done on the GPU because blending 8 million pixels one by one in GDScript would take many seconds.
##
## Used by [MapCatalog] (as a child node) for the two weather maps. See [method compose].

## The compositing shader.
const SHADER := preload("res://shaders/weather_composite.gdshader")
## Width of the composed picture, in pixels (the same as the downloaded pictures).
const WIDTH := 4096
## Height of the composed picture, in pixels.
const HEIGHT := 2048
## The satellite names [method compose] accepts as keys of its `images` argument, in the order of the shader's
## uniforms. Each entry is [name, shader uniform, "have" uniform].
const SLOTS := [
	["GOES-West", "goes_west", "have_west"],
	["GOES-East", "goes_east", "have_east"],
	["Himawari", "himawari", "have_himawari"],
]

## Composes the satellite pictures into one whole-world picture. This is a coroutine: call it with `await`.
##
## [param images]: Dictionary of satellite name ("GOES-West", "GOES-East", "Himawari") to its whole-world [Image]. A
## satellite that is missing (failed to download) is left out; its area becomes base or black.
## [param base]: the picture to show behind and between the satellites in blend mode (the NOAA-21 map), or null.
## [param blend]: true to fade the satellites into [param base]; false to show only the satellites, with black where
## none of them sees (the weather-only map).
## Returns: the composed RGBA8 [Image] (4096 by 2048), or null if the render could not be read back.
func compose(images: Dictionary, base: Image, blend: bool) -> Image:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(WIDTH, HEIGHT)
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(WIDTH, HEIGHT)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	var blank := ImageTexture.create_from_image(Image.create_empty(2, 2, false, Image.FORMAT_RGB8))
	for slot: Array in SLOTS:
		var img: Image = images.get(slot[0])
		mat.set_shader_parameter(slot[2], img != null)
		mat.set_shader_parameter(slot[1], ImageTexture.create_from_image(img) if img != null else blank)
	mat.set_shader_parameter("have_base", base != null)
	mat.set_shader_parameter("base_map", ImageTexture.create_from_image(base) if base != null else blank)
	mat.set_shader_parameter("blend_with_base", blend)
	rect.material = mat
	viewport.add_child(rect)
	add_child(viewport)
	# The viewport draws on the next frame; wait for it to finish before reading it.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var result := viewport.get_texture().get_image()
	viewport.queue_free()
	if result == null or result.is_empty():
		return null
	result.convert(Image.FORMAT_RGBA8)
	return result
