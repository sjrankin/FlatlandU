extends Window
## Flatland's About view: a slowly turning globe, the title, version and credits.

var _earth: Node3D

func _ready() -> void:
	title = "About Flatland"
	size = Vector2i(620, 640)
	exclusive = false
	transient = true
	close_requested.connect(hide)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(600, 340)
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	svc.add_child(vp)
	vb.add_child(svc)
	_build_globe(vp)
	var name_l := Label.new()
	name_l.text = "Flatland"
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", 34)
	vb.add_child(name_l)
	var info := Label.new()
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "Version %s\nGodot port of FlatlandView\n\nFlatland was written by Stuart Rankin with design inspiration\nand assistance from Kees de Kok.\n© 2019 – 2026 Stuart Rankin\n\nAll images and sounds used in Flatland are, to the best of the\nauthor's knowledge, in the public domain." % ProjectSettings.get_setting("application/config/version", "1.0")
	vb.add_child(info)
	var close := Button.new()
	close.text = "Close"
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(hide)
	vb.add_child(close)
	Settings.changed.connect(func(k: String, _v: Variant) -> void:
		if k == "map_type": _apply_map())
	MapCatalog.texture_ready.connect(func(_f: String, _t: Texture2D) -> void: _apply_map())

var _mat: StandardMaterial3D

func _build_globe(vp: SubViewport) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.45, 0.6)
	env.ambient_light_energy = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, 35, 0)
	light.light_energy = 1.5
	vp.add_child(light)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 27)
	cam.fov = 45.0
	vp.add_child(cam)
	_earth = Node3D.new()
	vp.add_child(_earth)
	var sphere := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 10.0
	sm.height = 20.0
	sm.radial_segments = 96
	sm.rings = 48
	sphere.mesh = sm
	_mat = StandardMaterial3D.new()
	_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	sphere.material_override = _mat
	_earth.add_child(sphere)
	_apply_map()

func _apply_map() -> void:
	var m := MapCatalog.map_for(Settings.get_string("map_type"))
	if m.is_empty():
		return
	var t := MapCatalog.request(str(m["globe"]))
	if t != null:
		_mat.albedo_texture = t

func _process(delta: float) -> void:
	if visible and _earth != null:
		_earth.rotate_y(delta * 0.5)
