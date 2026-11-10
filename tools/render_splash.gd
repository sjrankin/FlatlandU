extends SceneTree
## Renders the splash image (Assets/Splash.png): the sun, drawn with the app's own sky shader, in the
## middle of a black square. Run (not headless, it needs a renderer):
##   godot --path . -s tools/render_splash.gd

const SIZE := 2048
const SUN_RADIUS_PX := 260.0   # radius of the sun's disk in the image

func _init() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/sky.gdshader")
	var sphere := SphereMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.material_override = mat
	mi.scale = Vector3.ONE * 50.0
	var cam := Camera3D.new()
	# The sun is in the +Z direction. Pick the field of view so its disk is SUN_RADIUS_PX across.
	var sun_deg: float = mat.get_shader_parameter("sun_radius_deg") if mat.get_shader_parameter("sun_radius_deg") != null else 0.4
	cam.fov = SIZE / SUN_RADIUS_PX * sun_deg
	cam.near = 0.1
	cam.far = 200.0
	cam.rotation.y = PI
	vp.add_child(cam)
	cam.add_child(mi)
	mi.rotation.y = PI
	for i in range(10):
		await process_frame
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	# The sun's glow is wide; fade the picture to pure black toward the edges so the background is black.
	var data := img.get_data()
	var half := SIZE * 0.5
	for y in range(SIZE):
		for x in range(SIZE):
			var r := Vector2(x - half + 0.5, y - half + 0.5).length() / half
			var f := 1.0 - smoothstep(0.35, 0.95, r)
			var i := (y * SIZE + x) * 3
			data[i] = int(data[i] * f)
			data[i + 1] = int(data[i + 1] * f)
			data[i + 2] = int(data[i + 2] * f)
	img = Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGB8, data)
	img.save_png("res://Assets/Splash.png")
	print("Saved Assets/Splash.png ", img.get_size())
	quit()
