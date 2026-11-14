class_name FlatStage
extends Control
## The flat maps in 3D space, as in FlatlandView: the 2D map (north-centered, south-centered or rectangular) is
## drawn by `FlatView` into an off-screen picture, which is shown on a plane that the user can tilt and turn by
## dragging. The sun floats above the plane and casts a shadow on the map.

signal hover_changed(lat: float, lon: float, over_map: bool)
signal location_clicked(lat: float, lon: float)

const POLAR_SIZE := Vector2i(2048, 2048)
const RECT_SIZE := Vector2i(2048, 1130)
const PLANE_WIDTH := 20.0          # world units
const CAMERA_FOV := 30.0
const MIN_PITCH := deg_to_rad(12.0)
const MAX_PITCH := deg_to_rad(90.0)
const SUN_HEIGHT_FRACTION := 0.16   # height of the sun above the plane, as a fraction of its width
const SAT_HEIGHT := 1.8            # every satellite floats at this height over the map
const SAT_SCALE := 0.4
const SUN_WIDTH_FRACTION := 0.055  # the sun picture (disc and glow), as a fraction of the plane width

## Room (screen pixels) the clock takes at the top and the status bar at the bottom; set by the main window.
var reserved_top := 90.0:
	set(v):
		if not is_equal_approx(v, reserved_top):
			reserved_top = v
			_apply_camera()
var reserved_bottom := 80.0:
	set(v):
		if not is_equal_approx(v, reserved_bottom):
			reserved_bottom = v
			_apply_camera()

var view_type := Settings.VIEW_FLAT_NORTH

var _flat: FlatView
var _picture_vp: SubViewport
var _container: SubViewportContainer
var _stage_vp: SubViewport
var _camera: Camera3D
var _plane: MeshInstance3D
var _plane_mat: ShaderMaterial
var _sun: Sprite3D
var _sun_light: OmniLight3D
var _hours_root: Node3D
var _cities_root: Node3D
var _quakes_root: Node3D
var _sats_root: Node3D
var _hour_items: Array = []
var _hour_key := ""
var _city_items: Array = []
var _city_key := ""
var _quake_items: Array = []
var _quake_key := ""
var _sat_items: Dictionary = {}
var _material_cache: Dictionary = {}
var _poll := 0.0
var _picture_size := POLAR_SIZE
var _yaw := 0.0
var _pitch := MAX_PITCH
var _zoom := 1.0                   # 1 = the whole map fits
var _dragging := false
var _reset_tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# The 2D map, drawn off screen.
	_picture_vp = SubViewport.new()
	_picture_vp.size = POLAR_SIZE
	_picture_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_picture_vp)
	_flat = FlatView.new()
	_flat.stage_mode = true
	_flat.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picture_vp.add_child(_flat)
	# The 3D stage.
	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)
	_stage_vp = SubViewport.new()
	_stage_vp.own_world_3d = true
	PowerManager.register_viewport(_stage_vp)
	_container.add_child(_stage_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.77, 0.85)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	_stage_vp.add_child(we)
	_plane_mat = ShaderMaterial.new()
	_plane_mat.shader = load("res://shaders/flat_map.gdshader")
	_plane_mat.set_shader_parameter("map_tex", _picture_vp.get_texture())
	_plane = MeshInstance3D.new()
	_plane.material_override = _plane_mat
	_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage_vp.add_child(_plane)
	_hours_root = Node3D.new()
	_cities_root = Node3D.new()
	_quakes_root = Node3D.new()
	_sats_root = Node3D.new()
	for root_node in [_hours_root, _cities_root, _quakes_root, _sats_root]:
		_stage_vp.add_child(root_node)
	# The light is at the sun, so shadows point away from the sun's position.
	_sun_light = OmniLight3D.new()
	_sun_light.omni_range = 120.0
	_sun_light.omni_attenuation = 0.001
	_sun_light.light_energy = 1.4
	_sun_light.shadow_enabled = PowerManager.shadows_allowed()
	_sun_light.shadow_bias = 0.04
	_sun_light.shadow_normal_bias = 1.0
	_stage_vp.add_child(_sun_light)
	Settings.changed.connect(func(key: String, _v: Variant) -> void:
		if key == "graphics_quality":
			_sun_light.shadow_enabled = PowerManager.shadows_allowed())
	_sun = Sprite3D.new()
	_sun.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sun.shaded = false
	_sun.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	_sun.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_sun.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage_vp.add_child(_sun)
	_camera = Camera3D.new()
	_camera.fov = CAMERA_FOV
	_camera.near = 0.5
	_camera.far = 400.0
	_stage_vp.add_child(_camera)
	_camera.current = true
	_flat.hover_changed.connect(hover_changed.emit)
	resized.connect(_apply_camera)
	visibility_changed.connect(func() -> void:
		_picture_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED)
	set_view(view_type)

func set_view(type: String) -> void:
	view_type = type
	_picture_size = RECT_SIZE if type == Settings.VIEW_RECT else POLAR_SIZE
	_picture_vp.size = _picture_size
	_flat.set_view(type)
	var quad := QuadMesh.new()
	quad.size = Vector2(PLANE_WIDTH, PLANE_WIDTH * float(_picture_size.y) / float(_picture_size.x))
	_plane.mesh = quad
	_plane.rotation_degrees = Vector3(-90, 0, 0)            # faces up; the top of the picture is -Z
	if _sun.texture == null:
		_sun.texture = _make_sun_texture()
	_sun.pixel_size = PLANE_WIDTH * SUN_WIDTH_FRACTION / float(_sun.texture.get_width())
	_hour_key = ""
	_city_key = ""
	_quake_key = ""
	_reset_camera_now()

func refresh() -> void:
	_flat.refresh()

func _plane_height() -> float:
	return PLANE_WIDTH * float(_picture_size.y) / float(_picture_size.x)

## World position on the plane for a pixel of the 2D picture.
func _picture_to_world(p: Vector2) -> Vector3:
	return Vector3((p.x / _picture_size.x - 0.5) * PLANE_WIDTH, 0.0, (p.y / _picture_size.y - 0.5) * _plane_height())

# MARK: - Camera

func _reset_camera_now() -> void:
	_yaw = 0.0
	_pitch = MAX_PITCH
	_zoom = 1.0
	_apply_camera()

## Animate back to the straight-down view over one second (a double-click).
func reset_view() -> void:
	if _reset_tween != null and _reset_tween.is_valid():
		_reset_tween.kill()
	_reset_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var yaw_target := roundf(_yaw / TAU) * TAU          # unwind by the shortest way
	_reset_tween.tween_method(func(v: float) -> void: _yaw = v; _apply_camera(), _yaw, yaw_target, 1.0)
	_reset_tween.tween_method(func(v: float) -> void: _pitch = v; _apply_camera(), _pitch, MAX_PITCH, 1.0)
	_reset_tween.tween_method(func(v: float) -> void: _zoom = v; _apply_camera(), _zoom, 1.0, 1.0)

## Distance at which the whole plane fits the space left between the clock and the status bar.
func _fit_distance() -> float:
	var half := tan(deg_to_rad(CAMERA_FOV) * 0.5)
	var avail_h := maxf(100.0, size.y - reserved_top - reserved_bottom)
	var pixels_per_unit := minf(avail_h * 0.98 / _plane_height(), size.x * 0.98 / PLANE_WIDTH)
	return size.y / (2.0 * half * pixels_per_unit)

func _apply_camera() -> void:
	if _camera == null:
		return
	var dist := _fit_distance() * _zoom
	var around := Basis(Vector3.UP, _yaw)
	var pos := around * Vector3(0.0, dist * sin(_pitch), dist * cos(_pitch))
	var up := around * Vector3(0.0, cos(_pitch), -sin(_pitch))
	_camera.look_at_from_position(pos, Vector3.ZERO, up)
	# Centre the map in the space between the clock (top) and the status bar (bottom).
	var visible_height := 2.0 * dist * tan(deg_to_rad(CAMERA_FOV) * 0.5)
	_camera.v_offset = ((reserved_top - reserved_bottom) * 0.5) / maxf(1.0, size.y) * visible_height

func _process(_delta: float) -> void:
	if not visible or not PowerManager.drawing():
		return
	_update_sun()
	_poll += _delta
	var recheck := _poll >= 1.0
	if recheck:
		_poll = 0.0
	_update_hours()
	_update_cities(recheck)
	_update_quakes(recheck)
	_update_satellites()

## The sun hovers above the plane over the sub-solar point, with its shadow falling on the map.
func _update_sun() -> void:
	var show_sun := Settings.get_bool("show_sun")
	_sun.visible = show_sun
	if not show_sun:
		return
	var px := _flat.sun_picture_position()
	var ground := _picture_to_world(px)
	var height := PLANE_WIDTH * SUN_HEIGHT_FRACTION
	_sun.position = ground + Vector3(0.0, height, 0.0)
	_sun_light.position = _sun.position
	_sun_light.visible = true

# MARK: - Input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				_dragging = mb.pressed
				if mb.pressed and _reset_tween != null and _reset_tween.is_valid():
					_reset_tween.kill()
				if mb.pressed and mb.double_click:
					_dragging = false
					reset_view()
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					var p := _pick(mb.position)
					if p["hit"]:
						location_clicked.emit(p["lat"], p["lon"])
			MOUSE_BUTTON_WHEEL_UP:
				_zoom = clampf(_zoom * 0.92, 0.3, 2.5)
				_apply_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom = clampf(_zoom * 1.08, 0.3, 2.5)
				_apply_camera()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging and not _pinching:
			_yaw -= mm.relative.x * 0.006
			_pitch = clampf(_pitch + mm.relative.y * 0.006, MIN_PITCH, MAX_PITCH)
			_apply_camera()
		elif Settings.get_bool("mouse_tracking"):
			var p := _pick(mm.position)
			hover_changed.emit(p.get("lat", 0.0), p.get("lon", 0.0), p["hit"])
	elif event is InputEventMagnifyGesture:
		_zoom = clampf(_zoom / (event as InputEventMagnifyGesture).factor, 0.3, 2.5)
		_apply_camera()

## Two-finger pinch on a touch screen (driven by main.gd); see GlobeView.pinch_zoom.
var _pinching := false

func set_pinching(on: bool) -> void:
	_pinching = on

func pinch_zoom(factor: float) -> void:
	if Settings.get_bool("world_locked"):
		return
	_zoom = clampf(_zoom / factor, 0.3, 2.5)
	_apply_camera()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		hover_changed.emit(0.0, 0.0, false)

## Latitude and longitude under a screen position (through the plane, wherever it is tilted).
func _pick(screen: Vector2) -> Dictionary:
	if _camera == null:
		return {"hit": false}
	var origin := _camera.project_ray_origin(screen)
	var dir := _camera.project_ray_normal(screen)
	if absf(dir.y) < 1e-6:
		return {"hit": false}
	var t := -origin.y / dir.y
	if t <= 0.0:
		return {"hit": false}
	var hit := origin + dir * t
	var u := hit.x / PLANE_WIDTH + 0.5
	var v := hit.z / _plane_height() + 0.5
	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return {"hit": false}
	return _flat.pick(Vector2(u * _picture_size.x, v * _picture_size.y))

## The sun's picture: a soft glow around a small disc, drawn the way the sun is drawn in the globe's sky (and
## the splash screen). The glow is 50% opaque and the disc 75% opaque.
static func _make_sun_texture() -> ImageTexture:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := (n - 1) * 0.5
	var disc := 0.34                 # disc radius as a fraction of the picture's half width
	for y in range(n):
		for x in range(n):
			var r := Vector2(x - c, y - c).length() / c
			var rim := clampf(r / disc, 0.0, 1.0)
			var disc_col := Color(1.0, 0.86, 0.3).lerp(Color(1.0, 0.5, 0.08), rim * rim)
			var disc_amount := 1.0 - smoothstep(disc * 0.9, disc, r)
			var glow := exp(-pow(maxf(r - disc, 0.0) / (disc * 0.9), 1.2)) * (1.0 - smoothstep(0.8, 1.0, r))
			var glow_col := Color(1.0, 0.72, 0.2)
			var glow_alpha := 0.5 * glow                      # glow: 50% opaque
			var disc_alpha := 0.75 * disc_amount              # disc: 75% opaque
			var col := glow_col.lerp(disc_col, disc_amount)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, maxf(glow_alpha, disc_alpha)))
	return ImageTexture.create_from_image(img)

# MARK: - 3D objects on the map

## World units per pixel of the 2D picture.
func _unit() -> float:
	return PLANE_WIDTH / float(_picture_size.x)

func _color_material(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _material_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.45
		m.metallic_specular = 0.5
		m.emission_enabled = true
		m.emission = c * 0.2
		_material_cache[key] = m
	return _material_cache[key]

func _clear(node: Node3D) -> void:
	for child in node.get_children():
		child.queue_free()

## A mesh instance resting on the map (its base at height 0).
func _marker(mesh: Mesh, height: float, mat: Material, offset_y: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position.y = height + offset_y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi

func _shape_mesh(kind: String, size: float) -> Mesh:
	match kind:
		"box":
			var b := BoxMesh.new()
			b.size = Vector3(size, size, size)
			return b
		"cylinder":
			var c := CylinderMesh.new()
			c.top_radius = size * 0.5
			c.bottom_radius = size * 0.5
			c.height = size * 1.4
			return c
		"cone":
			var c := CylinderMesh.new()
			c.top_radius = 0.0
			c.bottom_radius = size * 0.55
			c.height = size * 1.6
			return c
		"pyramid":
			var c := CylinderMesh.new()
			c.top_radius = 0.0
			c.bottom_radius = size * 0.6
			c.height = size * 1.4
			c.radial_segments = 4
			return c
		"capsule":
			var c := CapsuleMesh.new()
			c.radius = size * 0.35
			c.height = size * 1.5
			return c
		"stick":
			var c := CylinderMesh.new()
			c.top_radius = size * 0.12
			c.bottom_radius = size * 0.12
			c.height = size * 2.4
			return c
	var s := SphereMesh.new()
	s.radius = size * 0.5
	s.height = size
	return s

## Half the height of a shape made by `_shape_mesh` (so it can rest on the map).
func _shape_half_height(kind: String, size: float) -> float:
	match kind:
		"box": return size * 0.5
		"cylinder": return size * 0.7
		"cone": return size * 0.8
		"pyramid": return size * 0.7
		"capsule": return size * 0.75
		"stick": return size * 1.2
	return size * 0.5

func _city_kind() -> String:
	var shape := Settings.get_string("city_shape")
	if shape.contains("Names"):
		return ""                # names only: no 3D marker
	if shape.contains("Box"):
		return "box"
	if shape.contains("Cylinder"):
		return "cylinder"
	if shape.contains("Pyramid"):
		return "pyramid"
	if shape.contains("Stick"):
		return "stick"
	return "sphere"

func _quake_kind() -> String:
	var shape := Settings.get_string("quake_shape")
	if shape.contains("Arrow"):
		return "arrow"
	for k in ["Pyramid", "Cone", "Box", "Cylinder", "Capsule"]:
		if shape.contains(k):
			return k.to_lower()
	return "sphere"           # Sphere, Pulsating Sphere, Tethered Magnitude

# --- hours: extruded 3D text lying on the map

func _update_hours() -> void:
	var specs := _flat.hour_label_specs()
	var color := Settings.get_color("color_hours_2d")
	var key := Settings.get_string("hour_type") + "|" + color.to_html() + "|" + str(view_type)
	for s in specs:
		key += "|" + str(s["text"])
	if key != _hour_key:
		_hour_key = key
		_clear(_hours_root)
		_hour_items.clear()
		var mat := _color_material(color)
		for s in specs:
			var size_units: float = float(s["size"]) * _unit()
			var tm := TextMesh.new()
			tm.text = str(s["text"])
			tm.font = Geo.heavy_font()
			tm.font_size = 64
			tm.pixel_size = size_units / 64.0
			tm.depth = size_units * 0.4
			tm.curve_step = 0.5
			var mi := MeshInstance3D.new()
			mi.mesh = tm
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			_hours_root.add_child(mi)
			_hour_items.append({"node": mi, "depth": tm.depth})
	for i in range(mini(specs.size(), _hour_items.size())):
		var item: Dictionary = _hour_items[i]
		var node: MeshInstance3D = item["node"]
		var spec: Dictionary = specs[i]
		var at := _picture_to_world(spec["pos"])
		node.transform = Transform3D(Basis(Vector3.UP, -float(spec["rot"])) * Basis(Vector3.RIGHT, -PI / 2.0),
			at + Vector3(0.0, float(item["depth"]) * 0.5 + 0.01, 0.0))

# --- cities

func _update_cities(recheck: bool) -> void:
	if recheck or _city_key == "":
		var cities: Array = CityDB.filtered_cities() if Settings.get_bool("show_cities") else []
		var key := "%s|%s|%s|%s|%d" % [_city_kind(), Settings.get_string("city_scale"), Settings.get_color("color_city_2d").to_html(),
			str(Settings.get_bool("show_cities")), cities.size()]
		if key != _city_key:
			_city_key = key
			_clear(_cities_root)
			_city_items.clear()
			var kind := _city_kind()
			if kind != "":
				var size := 0.3 * Shapes.scale_for("city_scale")
				var mesh := _shape_mesh(kind, size)
				var mat := _color_material(Settings.get_color("color_city_2d"))
				for city in cities:
					var mi := _marker(mesh, _shape_half_height(kind, size), mat)
					var holder := Node3D.new()
					holder.add_child(mi)
					_cities_root.add_child(holder)
					_city_items.append({"node": holder, "lat": float(city["Latitude"]), "lon": float(city["Longitude"])})
	for item in _city_items:
		(item["node"] as Node3D).position = _picture_to_world(_flat.project(item["lat"], item["lon"]))

# --- earthquakes

func _update_quakes(recheck: bool) -> void:
	if recheck or _quake_key == "":
		var quakes: Array = QuakeService.visible_quakes() if Settings.get_bool("enable_earthquakes") else []
		var key := "%s|%s|%d" % [_quake_kind(), Settings.get_string("quake_scale"), quakes.size()]
		for q in quakes:
			key += "|" + str(q["id"])
		if key != _quake_key:
			_quake_key = key
			_clear(_quakes_root)
			_quake_items.clear()
			var kind := _quake_kind()
			var scale := Shapes.scale_for("quake_scale")
			for q in quakes:
				var mag: float = q["magnitude"]
				var color := QuakeService.magnitude_color(mag)
				var mat := _color_material(color)
				var size := (0.22 + mag * 0.04) * scale
				var holder := Node3D.new()
				if kind == "arrow":
					# A cone pointing down at the spot, on a short shaft.
					var tip := CylinderMesh.new()
					tip.top_radius = size * 0.45
					tip.bottom_radius = 0.0
					tip.height = size * 1.1
					holder.add_child(_marker(tip, size * 0.55, mat))
					var shaft := CylinderMesh.new()
					shaft.top_radius = size * 0.14
					shaft.bottom_radius = size * 0.14
					shaft.height = size * 1.3
					holder.add_child(_marker(shaft, size * 1.1 + size * 0.65, mat))
				else:
					holder.add_child(_marker(_shape_mesh(kind, size), _shape_half_height(kind, size), mat))
				_quakes_root.add_child(holder)
				_quake_items.append({"node": holder, "lat": float(q["lat"]), "lon": float(q["lon"])})
	for item in _quake_items:
		(item["node"] as Node3D).position = _picture_to_world(_flat.project(item["lat"], item["lon"]))

# --- satellites: all at the same height over the map

func _update_satellites() -> void:
	var on := Settings.get_bool("show_satellites")
	_sats_root.visible = on
	if not on:
		return
	var now := Solar.now()
	var shown := {}
	for s in SatelliteService.positions(now):
		var id: int = s["id"]
		shown[id] = true
		if not _sat_items.has(id):
			var item := SatelliteModel.build(str(s["label"]))
			(item["holder"] as Node3D).scale = Vector3.ONE * SAT_SCALE
			(item["label"] as Label3D).pixel_size = 0.016      # the holder is scaled down, so make the label bigger
			_sats_root.add_child(item["holder"])
			_sat_items[id] = item
		var item: Dictionary = _sat_items[id]
		var here_px := _flat.project(float(s["lat"]), float(s["lon"]))
		var next_px := _flat.project(float(s["next_lat"]), float(s["next_lon"]))
		var along := Vector3(next_px.x - here_px.x, 0.0, next_px.y - here_px.y)
		if here_px.distance_to(next_px) > 100.0 * _flat._k() or along.length() < 0.0001:
			along = Vector3.RIGHT       # across the map edge or a polar jump: no sensible heading
		along = along.normalized()
		var up := Vector3.UP
		var side := along.cross(up).normalized()
		var ground := _picture_to_world(here_px)
		(item["holder"] as Node3D).transform = Transform3D(Basis(along, up, side) * Basis.from_scale(Vector3.ONE * SAT_SCALE),
			ground + Vector3(0.0, SAT_HEIGHT, 0.0))
		var km := int(round(float(s["alt_km"])))
		if km != item["km"]:
			item["km"] = km
			(item["label"] as Label3D).text = "%s  %s" % [item["name"], SatelliteService.format_altitude(float(s["alt_km"]))]
	for id in _sat_items.keys():
		((_sat_items[id] as Dictionary)["holder"] as Node3D).visible = shown.has(id)
