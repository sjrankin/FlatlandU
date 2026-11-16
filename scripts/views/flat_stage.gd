class_name FlatStage
extends Control
## The flat maps in 3D space, as in FlatlandView: the 2D map (north-centered, south-centered or rectangular) is
## drawn by `FlatView` into an off-screen picture, which is shown on a plane that the user can tilt and turn by
## dragging. The sun floats above the plane and casts a shadow on the map.

## Emitted as the mouse moves over the map (or leaves it). Re-emitted from the 2D [FlatView] and from
## [method _gui_input].
##
## [param lat]: latitude under the mouse (0 when not over the map).
## [param lon]: longitude under the mouse.
## [param over_map]: true if over the map plane.
signal hover_changed(lat: float, lon: float, over_map: bool)
## Emitted on a right click, or a long press on a phone or tablet, so main.gd can show the context menu.
##
## [param position]: where in this control, in pixels.
signal context_requested(position: Vector2)
## Emitted when a place on the map is chosen to be looked up, so main.gd can show the What's Here popup. (Not emitted by
## the stage itself any more; the context menu's What's Here? item uses [method pick_screen] instead.)
##
## [param lat]: the latitude.
## [param lon]: the longitude.
signal location_clicked(lat: float, lon: float)

## Pixel size of the off-screen 2D picture for the polar maps (square).
const POLAR_SIZE := Vector2i(2048, 2048)
## Pixel size of the picture for the rectangular map (2:1 ratio, a little shorter for the labels).
const RECT_SIZE := Vector2i(2048, 1130)
## Width of the map plane in world units; everything on the stage is sized from it.
const PLANE_WIDTH := 20.0
## The stage camera's vertical field of view, in degrees.
const CAMERA_FOV := 30.0
## The starting angle: looking straight down (90 degrees above the map). Dragging up and down turns the camera right
## round the map, with no limit, so the map can be flipped over to show its reverse.
const MAX_PITCH := deg_to_rad(90.0)
## The polar map's radius as a fraction of the picture's width (the same as in [FlatView]: 39 percent of the side).
## The reverse of a polar map is a round plate of this radius.
const POLAR_MAP_RADIUS := 0.39
## The rendering layer of the gears on the back of the polar maps, lit only by [member _gear_light].
const GEAR_LAYER := 2
## The gear train scene node script.
const GearTrainScript := preload("res://scripts/views/gear_train.gd")
## Height of the Sun above the plane, as a fraction of the plane's width.
const SUN_HEIGHT_FRACTION := 0.16
## Every satellite floats at this height (world units) over the map.
const SAT_HEIGHT := 1.8
## Size factor of the satellite models on the map.
const SAT_SCALE := 0.4
## The Sun picture's width (disc and glow) as a fraction of the plane's width.
const SUN_WIDTH_FRACTION := 0.055

## Room in screen pixels that the clock takes at the top; set by main.gd so the map fits between the clock and the
## status bar. Changing it re-fits the camera.
var reserved_top := 90.0:
	set(v):
		if not is_equal_approx(v, reserved_top):
			reserved_top = v
			_apply_camera()
## Room in screen pixels that the status bar (and toolbar) take at the bottom; set by main.gd. Changing it re-fits the
## camera.
var reserved_bottom := 80.0:
	set(v):
		if not is_equal_approx(v, reserved_bottom):
			reserved_bottom = v
			_apply_camera()

## The flat map shown ([constant Settings.VIEW_FLAT_NORTH], [constant Settings.VIEW_FLAT_SOUTH] or
## [constant Settings.VIEW_RECT]); change it with [method set_view].
var view_type := Settings.VIEW_FLAT_NORTH

## The 2D map ([FlatView], in [member FlatView.stage_mode]) drawn into [member _picture_vp].
var _flat: FlatView
## Off-screen viewport the 2D map is drawn into; its image is the texture of [member _plane].
var _picture_vp: SubViewport
## Container that shows the 3D stage on screen.
var _container: SubViewportContainer
## The 3D stage's viewport: plane, Sun, objects and camera.
var _stage_vp: SubViewport
## The stage camera, orbiting above the plane ([method _apply_camera]).
var _camera: Camera3D
## The flat plane that carries the map picture.
var _plane: MeshInstance3D
## The plane's shader material (`shaders/flat_map.gdshader`), fed the picture.
var _plane_mat: ShaderMaterial
## The Sun, a camera-facing sprite floating above the sub-solar point.
var _sun: Sprite3D
## A point light at the Sun, so shadows point away from it.
var _sun_light: OmniLight3D
## Parent of the extruded hour labels.
var _hours_root: Node3D
## Parent of the 3D city shapes.
var _cities_root: Node3D
## Parent of the 3D earthquake shapes.
var _quakes_root: Node3D
## Parent of the satellite models.
var _sats_root: Node3D
## The hour label nodes made by [method _update_hours]: {node, depth}.
var _hour_items: Array = []
## A text summary of what the hour labels show; they are rebuilt only when it changes.
var _hour_key := ""
## The city nodes made by [method _update_cities]: {node, lat, lon}.
var _city_items: Array = []
## A summary of the city settings; the city shapes are rebuilt only when it changes.
var _city_key := ""
## The earthquake nodes made by [method _update_quakes]: {node, lat, lon}.
var _quake_items: Array = []
## A summary of the earthquake settings and ids; the shapes are rebuilt only when it changes.
var _quake_key := ""
## The Dürer engraving of the Sun, lying flat on the map at the sub-solar point; created on first use.
var _sun_art: Sprite3D
## The Dürer engraving of the Moon, lying flat on the map at the sub-lunar point, the same size as the Sun's.
var _moon_art: Sprite3D
## Satellite models by NORAD id, as made by [method SatelliteModel.build].
var _sat_items: Dictionary = {}
## Materials by color, so each color is made once ([method _color_material]).
var _material_cache: Dictionary = {}
## Seconds since the cities and quakes were last re-checked; they are re-checked once a second.
var _poll := 0.0
## Pixel size of the current 2D picture ([constant POLAR_SIZE] or [constant RECT_SIZE]).
var _picture_size := POLAR_SIZE
## Camera angle round the map (radians); dragging sideways changes it.
var _yaw := 0.0
## Camera angle above the map (radians; 90 degrees is straight down, 0 is level with the map, and below 0 the camera is
## under the map, looking at its reverse). It has no limits: dragging up and down flips the map right over, any number of
## times. See [method _viewing_back].
var _pitch := MAX_PITCH
## True while the reverse of the map is showing (the camera is under it): the 3D objects on the front are hidden then.
var _showing_back := false
## The train of gears on the reverse of the polar maps.
var _gears: Node3D
## A light under the map that shines on the gears (only them: they are on [constant GEAR_LAYER]).
var _gear_light: OmniLight3D
## Camera distance factor: 1 means the whole map fits; 0.3 to 2.5.
var _zoom := 1.0
## True while the left mouse button is down on the map.
var _dragging := false
## The Tween animating [method reset_view].
var _reset_tween: Tween

## Builds the stage: the off-screen 2D map ([FlatView]), the 3D viewport with its environment, the plane, the root
## nodes for hours, cities, quakes and satellites, the Sun light and sprite and the camera. Connects hover reports,
## resizing and visibility (the off-screen picture stops updating while hidden), then shows the first view.
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
	_gears = GearTrainScript.new()
	_gears.position = Vector3(0.0, -0.4, 0.0)
	_gears.build(PLANE_WIDTH * POLAR_MAP_RADIUS * 0.94)
	_gears.visible = false
	_stage_vp.add_child(_gears)
	_gear_light = OmniLight3D.new()
	_gear_light.position = Vector3(0.0, -14.0, 0.0)
	_gear_light.omni_range = 60.0
	_gear_light.light_energy = 2.5
	_gear_light.light_cull_mask = GEAR_LAYER
	_gear_light.visible = false
	_stage_vp.add_child(_gear_light)
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

## Switches to another flat map: resizes the picture and plane, tells the 2D map, clears the cached 3D objects so they
## are rebuilt, and returns the camera to the start view.
##
## [param type]: [constant Settings.VIEW_FLAT_NORTH], [constant Settings.VIEW_FLAT_SOUTH] or
##   [constant Settings.VIEW_RECT].
func set_view(type: String) -> void:
	view_type = type
	_picture_size = RECT_SIZE if type == Settings.VIEW_RECT else POLAR_SIZE
	_picture_vp.size = _picture_size
	_flat.set_view(type)
	var quad := QuadMesh.new()
	quad.size = Vector2(PLANE_WIDTH, PLANE_WIDTH * float(_picture_size.y) / float(_picture_size.x))
	_plane.mesh = quad
	_plane.rotation_degrees = Vector3(-90, 0, 0)            # faces up; the top of the picture is -Z
	# The reverse of a polar map is a dark plate with gears; the reverse of the rectangular map is the map itself, seen
	# from behind (a mirror image).
	_plane_mat.set_shader_parameter("plate_back", type != Settings.VIEW_RECT)
	if _sun.texture == null:
		_sun.texture = _make_sun_texture()
	_sun.pixel_size = PLANE_WIDTH * SUN_WIDTH_FRACTION / float(_sun.texture.get_width())
	_hour_key = ""
	_city_key = ""
	_quake_key = ""
	_reset_camera_now()

## Refreshes the 2D map (time, map choice, night shading); main.gd calls this when the clock changes.
func refresh() -> void:
	_flat.refresh()

## The plane's height in world units (its width times the picture's aspect).
##
## Returns: world units.
func _plane_height() -> float:
	return PLANE_WIDTH * float(_picture_size.y) / float(_picture_size.x)

## Converts a pixel of the 2D picture to a position on the plane.
##
## [param p]: pixel position in the picture.
## Returns: the world position at height 0.
func _picture_to_world(p: Vector2) -> Vector3:
	return Vector3((p.x / _picture_size.x - 0.5) * PLANE_WIDTH, 0.0, (p.y / _picture_size.y - 0.5) * _plane_height())

## Whether the Sun is up at a place (the same test as [method Solar.is_daylight], using the sub-solar point the flat view
## already computed for this frame so it is cheap enough to run for every object every frame).
##
## [param lat]: latitude in degrees.
## [param lon]: longitude in degrees.
## Returns: true in daylight.
func _is_lit(lat: float, lon: float) -> bool:
	var decl := deg_to_rad(_flat._decl)
	var latr := deg_to_rad(lat)
	var ha := deg_to_rad(lon - _flat._sub_lon)
	return sin(latr) * sin(decl) + cos(latr) * cos(decl) * cos(ha) > sin(deg_to_rad(-0.833))

## Whether the Sun is up at the place under a picture position. A position off the map (the hour labels sit on a ring
## round the polar maps, or under the rectangular one) counts as the nearest place on the map.
##
## [param p]: pixel position in the picture.
## Returns: true in daylight.
func _is_lit_at_picture(p: Vector2) -> bool:
	var q := p
	if view_type == Settings.VIEW_RECT:
		var r: Rect2 = _flat._rect_map()
		q = Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	else:
		var c: Vector2 = _flat._center()
		var rad: float = _flat._map_radius() * 0.99
		q = c + (p - c).limit_length(rad)
	var hit: Dictionary = _flat.pick(q)
	return not hit["hit"] or _is_lit(hit["lat"], hit["lon"])

## Lets the shadow-casting parts of a 3D object cast shadows by day and stops them at night: shadows come from a light
## at the Sun, which would otherwise shadow things on the night side where the Sun is not shining. Parts that never
## cast shadows (labels) are left alone.
##
## [param node]: the object (it and its descendants are included).
## [param lit]: true if the object is in daylight.
func _set_casts_shadow(node: Node, lit: bool) -> void:
	if node is GeometryInstance3D:
		var g := node as GeometryInstance3D
		if g.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
			g.set_meta("casts_shadow", true)      # remember, so it can be switched back on at dawn
		if g.has_meta("casts_shadow"):
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lit else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_set_casts_shadow(child, lit)

# MARK: - Camera

## Puts the camera at the start view (looking straight down, whole map in view) at once.
func _reset_camera_now() -> void:
	_yaw = 0.0
	_pitch = MAX_PITCH
	_zoom = 1.0
	_apply_camera()
	_show_back(false)

## Animates the camera back to the straight-down view over one second (a double click), unwinding the turns (round the
## map and over it) the shortest way.
func reset_view() -> void:
	if _reset_tween != null and _reset_tween.is_valid():
		_reset_tween.kill()
	_reset_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var yaw_target := roundf(_yaw / TAU) * TAU          # unwind by the shortest way
	_reset_tween.tween_method(func(v: float) -> void: _yaw = v; _apply_camera(), _yaw, yaw_target, 1.0)
	var pitch_target := MAX_PITCH + roundf((_pitch - MAX_PITCH) / TAU) * TAU
	_reset_tween.tween_method(func(v: float) -> void: _pitch = v; _apply_camera(), _pitch, pitch_target, 1.0)
	_reset_tween.tween_method(func(v: float) -> void: _zoom = v; _apply_camera(), _zoom, 1.0, 1.0)

## The camera distance at which the whole plane fits the space left between the clock and the status bar.
##
## Returns: world units.
func _fit_distance() -> float:
	var half := tan(deg_to_rad(CAMERA_FOV) * 0.5)
	var avail_h := maxf(100.0, size.y - reserved_top - reserved_bottom)
	var pixels_per_unit := minf(avail_h * 0.98 / _plane_height(), size.x * 0.98 / PLANE_WIDTH)
	return size.y / (2.0 * half * pixels_per_unit)

## Places the camera from [member _yaw], [member _pitch] and [member _zoom] (looking at the middle of the plane), and
## shifts the view so the map is centered between the clock and the status bar.
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

## Every frame while visible and drawing: updates the Sun, hour labels, cities, quakes, satellites and the Sun/Moon
## balls. Cities and quakes are re-checked for changes once a second.
##
## [param _delta]: seconds since the last frame.
func _process(_delta: float) -> void:
	if not visible or not PowerManager.drawing():
		return
	var back := _viewing_back()
	if back != _showing_back:
		_show_back(back)
	if back:
		return          # only the reverse shows: nothing on the front needs updating (the gears turn by themselves)
	_update_sun()
	_poll += _delta
	var recheck := _poll >= 1.0
	if recheck:
		_poll = 0.0
	_update_hours()
	_update_cities(recheck)
	_update_quakes(recheck)
	_update_satellites()
	_update_solar_lunar_points()

## Development helper (the `--cam=` flag): sets the camera's yaw and pitch directly.
##
## [param yaw_deg]: the turn round the map, in degrees.
## [param pitch_deg]: the angle above the map in degrees (90 is straight down; below 0 shows the reverse).
func set_camera(yaw_deg: float, pitch_deg: float) -> void:
	_yaw = deg_to_rad(yaw_deg)
	_pitch = deg_to_rad(pitch_deg)
	_apply_camera()

## Whether the camera is under the map, looking at its reverse.
##
## Returns: true if so.
func _viewing_back() -> bool:
	return sin(_pitch) < 0.0

## Switches between the front of the map (with the 3D objects on it) and its reverse: shows or hides the objects, and
## the gears and their light (polar maps only; the animation runs only while they are visible).
##
## [param back]: true to show the reverse.
func _show_back(back: bool) -> void:
	_showing_back = back
	for node: Node3D in [_hours_root, _cities_root, _quakes_root, _sats_root]:
		node.visible = not back
	if back:
		_sun.visible = false
		if _sun_art != null:
			_sun_art.visible = false
			_moon_art.visible = false
	var gears := back and view_type != Settings.VIEW_RECT
	_gears.visible = gears
	_gear_light.visible = gears

## Places the Dürer Sun and Moon pictures at the sub-solar and sub-lunar points on every flat map (created on first use),
## each shown according to its setting. They lie flat on the map, just above it, like the map's own markings.
func _update_solar_lunar_points() -> void:
	if _sun_art == null:
		_sun_art = _make_art(_flat._durer_sun_tex)
		_moon_art = _make_art(_flat._durer_moon_tex)
	_sun_art.visible = SolarLunarMarker.sun_enabled()
	_moon_art.visible = SolarLunarMarker.moon_enabled()
	var now := Solar.now()
	var raise := Vector3(0.0, 0.03, 0.0)
	var sun := SolarLunarMarker.sun_point(now)
	var moon := SolarLunarMarker.moon_point(now)
	_sun_art.position = _picture_to_world(_flat.project(sun.x, sun.y)) + raise
	_moon_art.position = _picture_to_world(_flat.project(moon.x, moon.y)) + raise + Vector3(0.0, 0.01, 0.0)

## Makes a flat picture (a sprite lying on the map, facing up) of the Sun or Moon engraving, both the same size. It is
## added to the stage but hidden until [method _update_solar_lunar_points] shows it.
##
## [param tex]: the engraving's texture.
## Returns: the Sprite3D.
func _make_art(tex: Texture2D) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.texture = tex
	sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sprite.axis = Vector3.AXIS_Y
	sprite.double_sided = true
	sprite.shaded = false
	sprite.modulate = Color(1.0, 1.0, 1.0, FlatView.DURER_OPACITY)      # the picture is slightly see-through, the map is not
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.pixel_size = PLANE_WIDTH * SolarLunarMarker.MAP_FRACTION * FlatView.DURER_SIZE_IN_RADII / float(tex.get_width())
	sprite.visible = false
	_stage_vp.add_child(sprite)
	return sprite

## Floats the Sun above the sub-solar point on the map and puts the Sun light there, so shadows fall away from it.
## Hidden when `show_sun` is off.
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

## Mouse handling: left drag turns and tips the map; double click resets the view; the wheel zooms; right click
## reports the place ([signal location_clicked]); movement reports the hover ([signal hover_changed]); trackpad pinch
## zooms.
##
## [param event]: the input event.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				_dragging = mb.pressed
				if mb.pressed and not mb.double_click:
					_begin_long_press(mb.position)
				else:
					_press_token += 1
				if mb.pressed and _reset_tween != null and _reset_tween.is_valid():
					_reset_tween.kill()
				if mb.pressed and mb.double_click:
					_dragging = false
					reset_view()
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					context_requested.emit(mb.position)
			MOUSE_BUTTON_WHEEL_UP:
				_zoom = clampf(_zoom * 0.92, 0.3, 2.5)
				_apply_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom = clampf(_zoom * 1.08, 0.3, 2.5)
				_apply_camera()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.position.distance_to(_long_press_at) > 10.0:
			_press_token += 1      # moved too far: not a long press
		if _dragging and not _pinching:
			_yaw -= mm.relative.x * 0.006
			_pitch += mm.relative.y * 0.006      # no limit: the map can be flipped right over
			_apply_camera()
		elif Settings.get_bool("mouse_tracking"):
			var p := _pick(mm.position)
			hover_changed.emit(p.get("lat", 0.0), p.get("lon", 0.0), p["hit"])
	elif event is InputEventMagnifyGesture:
		_zoom = clampf(_zoom / (event as InputEventMagnifyGesture).factor, 0.3, 2.5)
		_apply_camera()

## Counts presses so a pending long press can tell it was cancelled (the finger moved, lifted or a second one joined).
var _press_token := 0
## Where the current press began, in pixels.
var _long_press_at := Vector2.ZERO

## Starts timing a long press (a finger held still for 0.6 seconds), which asks for the context menu. Only on a phone
## or tablet; a mouse uses the right button.
##
## [param pos]: where the press began, in pixels.
func _begin_long_press(pos: Vector2) -> void:
	_long_press_at = pos
	if not Layout.is_phone():
		return
	_press_token += 1
	var token := _press_token
	await get_tree().create_timer(0.6).timeout
	if token == _press_token and _dragging and not _pinching:
		_dragging = false
		_press_token += 1
		context_requested.emit(pos)

## The place under a position in this control (for the context menu's What's Here?).
##
## [param screen]: position in pixels, in this control.
## Returns: {"hit": false}, or {"hit": true, "lat", "lon"}.
func pick_screen(screen: Vector2) -> Dictionary:
	return _pick(screen)

## True while two fingers are down, so the one-finger drag that Godot emulates from the first finger does not also
## turn the map.
var _pinching := false

## main.gd tells the stage when a two-finger pinch starts or ends.
##
## [param on]: true while pinching.
func set_pinching(on: bool) -> void:
	_pinching = on

## Two-finger pinch on a touch screen (driven by main.gd): zooms the camera unless the world is locked. See
## [method GlobeView.pinch_zoom].
##
## [param factor]: greater than 1 when the fingers move apart (zoom in).
func pinch_zoom(factor: float) -> void:
	if Settings.get_bool("world_locked"):
		return
	_zoom = clampf(_zoom / factor, 0.3, 2.5)
	_apply_camera()

## When the mouse leaves the control, tells listeners it is no longer over the map.
##
## [param what]: the notification constant.
func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		hover_changed.emit(0.0, 0.0, false)

## Finds the place under a screen position by casting a ray through the plane, wherever the plane is tilted.
##
## [param screen]: position in pixels.
## Returns: {"hit": false}, or the result of [method FlatView.pick] ({"hit": true, "lat", "lon"}).
func _pick(screen: Vector2) -> Dictionary:
	if _camera == null or _showing_back:
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

## Draws the Sun's picture: a soft glow (50% opaque) round a small disc (75% opaque), in the style of the Sun in the
## globe's sky.
##
## Returns: the 256 by 256 ImageTexture.
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
##
## Returns: the factor.
func _unit() -> float:
	return PLANE_WIDTH / float(_picture_size.x)

## A lit material of one color with a slight glow, cached.
##
## [param c]: the color.
## Returns: the StandardMaterial3D.
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

## Frees all children of a node (queued).
##
## [param node]: the node to empty.
func _clear(node: Node3D) -> void:
	for child in node.get_children():
		child.queue_free()

## Makes a shape that rests on the map and casts a shadow.
##
## [param mesh]: the shape.
## [param height]: the height of its center above the map (half its height, so its base is on the map).
## [param mat]: its material.
## [param offset_y]: extra height (default 0).
## Returns: the MeshInstance3D.
func _marker(mesh: Mesh, height: float, mat: Material, offset_y: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position.y = height + offset_y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi

## Makes the extruded magnitude text ("M6.4") that lies on the map beside a quake's shape, as on the globe. Not used for
## Tethered Magnitude, whose disc already shows the magnitude.
##
## [param mag]: the magnitude.
## [param size]: the quake shape's size, which sets where the text sits and how big it is.
## [param mat]: the quake's color material.
## [param count]: how many quakes the shape stands for (more than 1 for a group); shown after the magnitude.
## Returns: the MeshInstance3D.
func _quake_magnitude_text(mag: float, size: float, mat: Material, count: int = 1) -> MeshInstance3D:
	var text := "%.2f" % mag
	if text.ends_with("0"):
		text = text.left(-1)
	if count > 1:
		text += " (%d)" % count
	var tm := TextMesh.new()
	tm.text = "M" + text
	tm.font = Geo.quake_font()
	tm.font_size = 64
	var height := 0.3 + 0.03 * mag
	tm.pixel_size = height / 64.0
	tm.depth = height * 0.3
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Lie flat, just in front of the shape (towards the bottom of the screen).
	mi.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0.0, tm.depth * 0.5 + 0.01, size * 0.5 + height))
	return mi

## Makes the Tethered Magnitude shape for a quake (as on the globe): a pole standing on the map, topped by a translucent
## disc in the quake's color that bears the magnitude, with a rim round the disc. A recent quake (when new quakes are
## highlighted) also gets a spinning ring of bright red spheres on the rim. Sizes grow with the magnitude and the
## `quake_scale` setting. Tweens stop when the node is freed.
##
## [param q]: the quake Dictionary.
## [param color]: its color.
## [param scale]: the size factor from the `quake_scale` setting ([method Shapes.scale_for]).
## Returns: the Node3D holding the shape, with its base on the map.
func _tethered_quake(q: Dictionary, color: Color, scale: float) -> Node3D:
	var local := float(q["magnitude"]) / 10.0
	var k := 0.35 * scale                          # world units per globe unit
	var holder := Node3D.new()
	var height := 2.5 * local * k
	var mat := _color_material(color)
	var pole := CylinderMesh.new()
	pole.top_radius = local * 0.1002 * k
	pole.bottom_radius = local * 0.1002 * k
	pole.height = height
	holder.add_child(_marker(pole, height * 0.5, mat))
	var disc_r := 2.01 * local * k
	var disc := CylinderMesh.new()
	disc.top_radius = disc_r
	disc.bottom_radius = disc_r
	disc.height = 0.1 * k
	var disc_mi := _marker(disc, height, Shapes.plain(Color(color, 0.6)))
	disc_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(disc_mi)
	var tm := TextMesh.new()
	tm.text = "M%.1f" % float(q["magnitude"])
	if int(q.get("group_count", 1)) > 1:
		tm.text += " (%d)" % int(q["group_count"])      # a group of quakes: how many it stands for
	tm.font = Geo.label_font(900)
	tm.font_size = 64
	tm.pixel_size = (0.6 + 0.3 * local) * k / 64.0
	tm.depth = 0.05 * k
	# The longer text must still fit on the disc: shrink it if it is wider than 85 percent of the disc's width.
	var text_width := tm.get_aabb().size.x
	if text_width > 1.7 * disc_r:
		tm.pixel_size *= 1.7 * disc_r / text_width
	var txt := MeshInstance3D.new()
	txt.mesh = tm
	txt.material_override = Shapes.plain(Color.BLACK)
	txt.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	txt.position = Vector3(0.0, height + 0.09 * k, 0.0)
	txt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(txt)
	var rim_r := disc_r + 0.101 * k
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = disc_r
	rim_mesh.outer_radius = rim_r + 0.101 * k
	var rim := _marker(rim_mesh, height, Shapes.plain(color))
	holder.add_child(rim)
	var recent := Time.get_unix_time_from_system() - float(q["time"]) <= Settings.get_float("quake_recent_hours") * 3600.0
	if Settings.get_bool("quake_highlight_new") and recent:
		var sphere := SphereMesh.new()
		sphere.radius = 0.215 * k
		sphere.height = 0.43 * k
		for a in range(0, 360, 45):
			var sp := MeshInstance3D.new()
			sp.mesh = sphere
			sp.material_override = Shapes.plain(Color("#ff0000"))
			sp.position = Vector3(rim_r * cos(deg_to_rad(a)), 0.0, rim_r * sin(deg_to_rad(a)))
			sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			rim.add_child(sp)
		var speed := maxf(0.09994492, 5.0 * (1.0 - local))
		var tw := rim.create_tween().set_loops()
		tw.tween_property(rim, "rotation:y", PI, speed).as_relative()
	return holder

## Makes the Pulsating Sphere for a quake: a translucent sphere centered on the map's surface (half of it sunk into the
## map), swelling to one and a half times its size and back, from its center; faster for bigger quakes. It casts no
## shadow (it is see-through). The tween stops when the node is freed.
##
## [param size]: the sphere's diameter at rest, in world units.
## [param color]: the quake's color.
## [param mag]: the quake's magnitude, which sets the speed.
## Returns: the MeshInstance3D.
func _pulsing_sphere(size: float, color: Color, mag: float) -> MeshInstance3D:
	var mi := _marker(_shape_mesh("sphere", size), 0.0, Shapes.plain(Color(color, 0.6)))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var d := 0.7 + (10.0 - mag) * 0.05
	var tw := mi.create_tween().set_loops()
	tw.tween_property(mi, "scale", Vector3.ONE * 1.5, d)
	tw.tween_property(mi, "scale", Vector3.ONE, d)
	return mi

## Makes the mesh for a shape name.
##
## [param kind]: "box", "cylinder", "cone", "pyramid", "capsule" or "stick"; anything else gives a sphere.
## [param size]: the shape's size.
## Returns: the Mesh. See [method _shape_half_height].
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

## Half the height of a shape made by [method _shape_mesh], so it can rest on the map.
##
## [param kind]: the shape name.
## [param size]: the size given to [method _shape_mesh].
## Returns: half the height.
func _shape_half_height(kind: String, size: float) -> float:
	match kind:
		"box": return size * 0.5
		"cylinder": return size * 0.7
		"cone": return size * 0.8
		"pyramid": return size * 0.7
		"capsule": return size * 0.75
		"stick": return size * 1.2
	return size * 0.5

## The city shape name from the `city_shape` setting.
##
## Returns: "box", "cylinder", "pyramid", "stick" or "sphere", or "" for "Names" (names only, no 3D marker).
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

## The earthquake shape name from the `quake_shape` setting.
##
## Returns: "arrow" (Static Arrow), "arrow_animated", "tethered" (Tethered Magnitude), "pyramid", "cone", "box",
##   "cylinder", "capsule", "pulsing" (Pulsating Sphere) or "sphere".
func _quake_kind() -> String:
	var shape := Settings.get_string("quake_shape")
	if shape.contains("Arrow"):
		return "arrow_animated" if shape.contains("Animated") else "arrow"
	if shape.contains("Tethered"):
		return "tethered"
	for k in ["Pyramid", "Cone", "Box", "Cylinder", "Capsule"]:
		if shape.contains(k):
			return k.to_lower()
	if shape.contains("Pulsat"):
		return "pulsing"
	return "sphere"

# --- hours: extruded 3D text lying on the map

## Keeps the hour labels, extruded 3D text lying on the map, current: asks [method FlatView.hour_label_specs] what to
## show, rebuilds the labels only if the text, color, kind or view changed, and places each one at its picture
## position.
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
		_set_casts_shadow(node, _is_lit_at_picture(spec["pos"]))

# --- cities

## Keeps the 3D city shapes current: when settings or the city list change (checked once a second, with
## [param recheck]) it rebuilds them; every frame it moves each to its map position.
##
## [param recheck]: true on the once-a-second pass that looks for changes.
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
		_set_casts_shadow(item["node"], _is_lit(item["lat"], item["lon"]))

# --- earthquakes

## Keeps the 3D earthquake shapes current, like [method _update_cities]: a shape (or an arrow) per visible quake,
## sized by magnitude and colored by [method QuakeService.magnitude_color].
##
## [param recheck]: true on the once-a-second pass that looks for changes.
func _update_quakes(recheck: bool) -> void:
	if recheck or _quake_key == "":
		var quakes: Array = QuakeService.map_quakes() if Settings.get_bool("enable_earthquakes") else []
		var key := "%s|%s|%d|%s|%s" % [_quake_kind(), Settings.get_string("quake_scale"), quakes.size(),
			Settings.get_bool("quake_highlight_new"), Settings.get_float("quake_recent_hours")]
		for q in quakes:
			key += "|%s#%d" % [q["id"], int(q.get("group_count", 1))]
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
				if kind == "arrow" or kind == "arrow_animated":
					# A cone pointing down at the spot, on a short shaft. The animated arrow bounces, its tip touching the map
					# at the bottom of each bounce, faster for bigger quakes.
					var arrow := Node3D.new()
					holder.add_child(arrow)
					var tip := CylinderMesh.new()
					tip.top_radius = size * 0.45
					tip.bottom_radius = 0.0
					tip.height = size * 1.1
					arrow.add_child(_marker(tip, size * 0.55, mat))
					var shaft := CylinderMesh.new()
					shaft.top_radius = size * 0.14
					shaft.bottom_radius = size * 0.14
					shaft.height = size * 1.3
					arrow.add_child(_marker(shaft, size * 1.1 + size * 0.65, mat))
					if kind == "arrow_animated":
						var d := maxf(0.2, (10.0 - mag) / 5.0)
						var top := size * 0.8
						arrow.position.y = top
						var tw := arrow.create_tween().set_loops()
						tw.tween_property(arrow, "position:y", 0.0, d).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
						tw.tween_property(arrow, "position:y", top, d).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				elif kind == "tethered":
					holder.add_child(_tethered_quake(q, color, scale))
				elif kind == "pulsing":
					holder.add_child(_pulsing_sphere(size, color, mag))
				else:
					holder.add_child(_marker(_shape_mesh(kind, size), _shape_half_height(kind, size), mat))
				if kind != "tethered":
					holder.add_child(_quake_magnitude_text(mag, size, mat, int(q.get("group_count", 1))))
				_quakes_root.add_child(holder)
				_quake_items.append({"node": holder, "lat": float(q["lat"]), "lon": float(q["lon"])})
	for item in _quake_items:
		(item["node"] as Node3D).position = _picture_to_world(_flat.project(item["lat"], item["lon"]))
		_set_casts_shadow(item["node"], _is_lit(item["lat"], item["lon"]))

# --- satellites: all at the same height over the map

## Keeps the satellite models current: each tracked satellite is a model floating at [constant SAT_HEIGHT] over its
## map position, turned along its track (with no heading across the map edge or a polar jump), with its label updated
## when the altitude changes. Hidden when satellites are off.
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
		_set_casts_shadow(item["holder"], _is_lit(float(s["lat"]), float(s["lon"])))
		var km := int(round(float(s["alt_km"])))
		if km != item["km"]:
			item["km"] = km
			(item["label"] as Label3D).text = "%s  %s" % [item["name"], SatelliteService.format_altitude(float(s["alt_km"]))]
	for id in _sat_items.keys():
		((_sat_items[id] as Dictionary)["holder"] as Node3D).visible = shown.has(id)
