extends Node3D
## The 3D globe (counterpart of Flatland's GlobeView + extensions).
## The sun is fixed in the scene and the Earth turns beneath it according to UTC, exactly as
## Flatland does. The globe is lit by a sun light and, optionally, a cyan moon light.

## Emitted as the mouse moves over the globe (when `mouse_tracking` is on) and when it leaves.
##
## [param lat]: latitude under the mouse (0 when not over the globe).
## [param lon]: longitude under the mouse.
## [param over_globe]: true if the mouse is over the Earth.
signal hover_changed(lat: float, lon: float, over_globe: bool)
## Emitted when the user asks "what's here" at a point on the Earth (from the context menu); main.gd shows the popup.
##
## [param lat]: the latitude.
## [param lon]: the longitude.
signal location_clicked(lat: float, lon: float)
## The user asked for the context menu (right click, or a long press on a phone or tablet) at a point of the view.
## main.gd builds and shows the menu.
##
## [param position]: where in the view, in pixels.
signal context_requested(position: Vector2)

## The Earth's radius in scene units (10), from [constant Geo.GLOBE_RADIUS]. Almost every size in this file is
## relative to it.
const R := Geo.GLOBE_RADIUS
# Camera as in FlatlandView: a perspective camera 175 units away with a roughly 9 to 10 degree field of view
# (nearly orthographic). FlatlandView stops zooming at 60 (Defaults.ClosestZ); here the user can go in to 20.
## The camera's normal distance from the Earth's center: 175 units, as in FlatlandView, with a narrow field of view
## (nearly orthographic). Reset View returns here.
const DEFAULT_DISTANCE := 175.0
## Closest the user can zoom (FlatlandView stops at 60; here the user can go in to 20).
const MIN_DISTANCE := 20.0
## Farthest the user can zoom.
const MAX_DISTANCE := 500.0
# Hour labels are fully opaque at and beyond FADE_START_DISTANCE and fade smoothly to
# HOUR_MIN_ALPHA as the camera zooms in to FADE_END_DISTANCE, so they don't block the surface.
## Hour labels are fully opaque at and beyond this camera distance (see [method _hour_alpha_for_distance]).
const HOUR_FADE_START_DISTANCE := 110.0
## Hour labels reach their minimum opacity at this camera distance, so they do not block the surface when zoomed in.
const HOUR_FADE_END_DISTANCE := 45.0
## The lowest opacity the hour labels fade to when zoomed in.
const HOUR_MIN_ALPHA := 0.3
## The camera's vertical field of view in degrees in the normal (orbit) view: 9, nearly orthographic.
const CAMERA_FOV := 9.0

## Parent of the Earth and the sun-fixed objects; tilted by the Sun's declination (the seasons) so the Sun stays
## directly behind the viewer.
var _system: Node3D
## Rotates with the Earth: the map, grid, cities, quakes, satellites, hour labels that turn with the Earth.
var _earth: Node3D
## The Earth sphere carrying the map.
var _earth_mesh: MeshInstance3D
## The Earth's shader material (`shaders/earth.gdshader`): day/night shading and the map.
var _earth_mat: ShaderMaterial
## A sea-colored sphere just under the map, for maps with transparent seas (shown only when the map has a sea file).
var _sea_mesh: MeshInstance3D
## The sea sphere's shader material.
var _sea_mat: ShaderMaterial
## The shader materials of the cubic Earth's six faces (given the Sun direction like the Earth's).
var _cube_mats: Array[ShaderMaterial] = []
## File name of the current map's sea picture ("" if none).
var _sea_file := ""
## Stays with the Sun and does not turn with the Earth: the poles, noon meridians and the fixed hour labels.
var _fixed: Node3D
## The camera pivot: rotated by [member _pitch] and [member _yaw] so the camera, a child at distance
## [member _distance], orbits the Earth.
var _orbit: Node3D
## The camera. In orbit mode it sits on [member _orbit]; the special modes place it directly.
var _camera: Camera3D
## The Sun's directional light (casts the 3D shadows).
var _sun: DirectionalLight3D
## The faint cyan "moon light" that lights the night side slightly (the `show_moon_light` setting); not the Moon
## itself.
var _moon: DirectionalLight3D
## The Moon itself, at its true distance and size (not the cyan moon light).
var _moon_body: MeshInstance3D
## The Moon's current distance from the Earth's center in scene units (about 60 Earth radii); updated by
## [method _place_moon].
var _moon_distance := Lunar.MEAN_DISTANCE_KM / Geo.EARTH_KM * R
## Render layer of the Moon: only the Sun lights it, not the cyan moon light.
const MOON_LAYER := 1 << 2
## The Environment: black background (from the `color_background` setting), faint ambient light and a studio-like sky
## used only for reflections (so the gold balls look metallic).
var _env: Environment
## The sky sphere (with the Sun's picture) centered on the camera.
var _sky_mesh: MeshInstance3D
## The sky sphere's shader material.
var _sky_mat: ShaderMaterial
## The 2000 brightest stars, drawn as small camera-facing quads positioned at the camera ([method _build_stars]).
var _stars_node: MeshInstance3D
## The stars' shader material (`shaders/stars.gdshader`); its size follows [member _pixel_angle].
var _stars_mat: ShaderMaterial
## Parent of the city markers (in the Earth's frame).
var _cities_node: Node3D
## Parent of the earthquake shapes.
var _quakes_node: Node3D
## Parent of the hour labels that turn with the Earth (wall-clock and home labels).
var _hours_earth: Node3D
## Parent of the hour labels fixed to the Sun (noon-relative and solar labels).
var _hours_fixed: Node3D
## Parent of the latitude/longitude grid lines.
var _grid_node: Node3D
## The noon meridian: a half great circle facing the Sun (not shown in cubic mode).
var _noon_line: MeshInstance3D
## Parent of the World Heritage site markers.
var _sites_node: Node3D
## Parent of the outlines of the earthquake regions.
var _regions_node: Node3D
## The cubic Earth (six map faces), shown instead of the sphere when [member _cubic] is true.
var _cube: Node3D
## True when the cubic Earth is shown instead of the sphere ([method set_cubic]).
var _cubic := false
## The candy-striped north-south pole with gold balls at the ends.
var _poles: Node3D
## The two striped half-poles [north, south]; each spins slowly about its axis like a barber pole.
var _pole_shafts: Array = []
## Objects whose material follows day and night: {node, lat, lon, day, night, is_day}; updated once a minute by
## [method _refresh_day_night].
var _dn_items: Array = []
## Parent of the satellite models (in the Earth's frame).
var _sat_node: Node3D
## Satellite models by NORAD id: {holder, label, km, name} (see [method SatelliteModel.build]).
var _sat_items: Dictionary = {}
## Animated earthquake arrows, {node, dir}; each spins about its axis, one radian a second.
var _arrows: Array = []
## Materials already made, by color/kind, so each is built once.
var _mat_cache: Dictionary = {}
## Parent of the points-of-interest markers.
var _pois_node: Node3D
## File name of the map now on the Earth; used to tell when the texture needs changing ([method _apply_map]).
var _current_map_file := ""
## Camera angle round the Earth (radians), in orbit mode.
var _yaw := 0.0
## Screen-plane offset of the camera (Command/Option/Ctrl-drag), so the globe can be moved across the view.
var _pan := Vector2.ZERO
## Camera angle above or below the equator (radians), in orbit mode.
var _pitch := 0.0
## Camera distance from the Earth's center, in orbit mode ([constant MIN_DISTANCE] to [constant MAX_DISTANCE]).
var _distance := DEFAULT_DISTANCE
## How the camera is placed. ORBIT: circling the Earth, controlled by dragging (the normal mode). FROM_MOON and
## FROM_SUN: sitting at the Moon or Sun and facing the Earth, following the Moon. LOOK_AT_MOON: standing near the
## Earth and pointing at the Moon. FLIGHT: a slow wandering flight just above the surface. The special modes are
## chosen from the context menu, are never saved, and (except FLIGHT, which ends on a double click) end when the user
## moves the camera. See [method set_camera_mode].
enum CamMode { ORBIT, FROM_MOON, FROM_SUN, LOOK_AT_MOON, FLIGHT }
## Emitted when the camera mode changes, so main.gd can update the context menu's check marks.
##
## [param mode]: the new [enum CamMode].
signal camera_mode_changed(mode: int)
## The current [enum CamMode].
var _cam_mode := CamMode.ORBIT
## LOOK_AT_MOON: where the camera stands. Fixed when the mode starts; it does not follow the Moon.
var _look_from := Vector3.ZERO
## Progress, 0 to 1, of the one-second glide from the old camera position to the new mode's position.
var _blend := 1.0
## The camera's transform when the glide started.
var _blend_from := Transform3D.IDENTITY
## The camera's field of view when the glide started.
var _blend_fov := CAMERA_FOV
## The Tween driving [member _blend].
var _blend_tween: Tween
## LOOK_AT_MOON: the zoom, as the field of view in degrees (a smaller angle is closer). Changed by the wheel and pinch
## ([method zoom_look]).
var _look_fov := 4.0
## Narrowest field of view (closest zoom) when looking at the Moon, in degrees.
const LOOK_FOV_MIN := 0.2
## Widest field of view when looking at the Moon, in degrees.
const LOOK_FOV_MAX := 40.0

# Camera flight: a slow, wandering flight just above the surface, among the hour labels.
## The wandering-value class (wander.gd), used for the flight's slowly changing speed, course, altitude and view
## angles.
const Wander := preload("res://scripts/views/wander.gd")
## Where the hour labels sit, as a distance from the Earth's center (1.15 times the radius).
const HOUR_RADIUS := 11.5
## The hour labels' height above the surface; the flight altitude limits are fractions of this.
const HOUR_ALTITUDE := HOUR_RADIUS - R
## Lowest the flight goes, as a distance from the Earth's center: the surface plus 0.1 times the hours' altitude.
const FLIGHT_MIN_RADIUS := R + HOUR_ALTITUDE * 0.1
## Highest the flight goes: the surface plus 1.1 times the hours' altitude.
const FLIGHT_MAX_RADIUS := R + HOUR_ALTITUDE * 1.1
## The camera's field of view during the flight, in degrees (wide, to see the surface and the horizon).
const FLIGHT_FOV := 60.0
## How far, in degrees, the view may turn to either side of the course.
const FLIGHT_YAW_LIMIT := 20.0
## How far, in degrees, the view may tip up or down from the horizon.
const FLIGHT_PITCH_LIMIT := 15.0
## The flight keeps at least half of this distance from any satellite, quake marker or pole.
const FLIGHT_CLEARANCE := 1.2
## The flight starts steering round something when it is closer than this.
const FLIGHT_REACH := 4.0
## Flight: the unit vector from the Earth's center to the camera.
var _fl_dir := Vector3.BACK
## Flight: the course, a unit vector along the surface perpendicular to [member _fl_dir].
var _fl_tangent := Vector3.RIGHT
## Flight: where the camera looks (the course turned by the yaw and pitch offsets, and eased).
var _fl_forward := Vector3.RIGHT
## Flight: the camera's position.
var _fl_pos := Vector3.ZERO
## Flight: positions of things to keep clear of (satellites, quake markers, pole tips); refreshed four times a second
## by [method _refresh_flight_obstacles].
var _fl_obstacles: Array[Vector3] = []
## Flight: the eased-in turn away from obstacles, in radians a second.
var _fl_avoid := 0.0
## Flight: seconds since the obstacle list was refreshed.
var _fl_obstacle_age := 99.0
## Flight: the random number generator for the wandering values.
var _fl_rng := RandomNumberGenerator.new()
## Flight: wandering value for the distance from the Earth's center (between [constant FLIGHT_MIN_RADIUS] and
## [constant FLIGHT_MAX_RADIUS]).
var _fl_altitude: RefCounted
## Flight: wandering value for the speed along the surface, in units a second.
var _fl_speed: RefCounted
## Flight: wandering value for the rate the course turns, in radians a second.
var _fl_turn: RefCounted
## Flight: wandering value for how far the view is turned to the side, in degrees.
var _fl_yaw: RefCounted
## Flight: wandering value for how far the view is tipped up or down, in degrees.
var _fl_pitch: RefCounted
## The hour labels' current opacity; depends on the zoom (see [method _update_hour_alpha]) and is always 1 during the
## flight.
var _hour_alpha := 1.0
## True while the left mouse button (or one finger) is down and dragging the globe.
var _dragging := false
## The welcome text ([IntroText]) while it exists.
var _intro: IntroText
## Render layer of the invisible sphere that casts the Earth's shadow, so the "3D shadows" option can keep it while
## switching other shadows off.
const EARTH_SHADOW_LAYER := 1 << 19
## Render layer for objects on the night side: the Sun's light ignores it, so the Sun cannot light their sides near
## the edge of the lit half.
const NIGHT_LAYER := 1 << 1
## Where the last mouse press began, to tell a tap from a drag ([constant TAP_SLOP]).
var _tap_start := Vector2.ZERO
## How far in pixels a press may move and still count as a tap.
const TAP_SLOP := 6.0
## The minute (Unix time / 60) of the last once-a-minute update; when it changes the day/night materials and
## wall-clock hour labels are refreshed.
var _last_hour_stamp := -1
## The 24 hour labels, each {node, parent}.
var _hour_items: Array = []
## How many wall-clock hour labels still need renewing after the minute changed; see [method _renew_next_hour].
var _hours_stale := 0
## The ball on the Earth under the Sun (see SolarLunarMarker).
var _sun_point: MeshInstance3D
## The ball on the Earth under the Moon.
var _moon_point: MeshInstance3D
## The earthquake shapes by quake id: {group: Node3D holding all of that quake's nodes, indicator: Node3D or null}.
## Used by [method _sync_quakes] so only changed quakes are rebuilt.
var _quake_nodes: Dictionary = {}
## Where [method _add_quake_indicator] puts the indicator it builds (set by the caller for the quake being built).
var _indicator_parent: Node3D
## Seconds since the last once-a-second update ([method _update_time]).
var _tick := 0.0
## Attract mode: the Earth's current turn, in radians.
var _attract_angle := 0.0
## The turn that puts the sub-solar longitude facing the Sun now; the Earth eases toward it.
var _earth_angle := 0.0
## The last mouse position over the globe, in pixels.
var _mouse_pos := Vector2.ZERO
## Whether the mouse is inside the globe view (set by main.gd).
var _mouse_inside := false
## The view's last known size; the camera is re-fitted when it changes.
var _vp_size := Vector2(1280, 800)

## Builds the scene ([method _build_scene]), connects settings, map textures, quake updates and user-data changes,
## then applies the map, builds everything and sets the time.
func _ready() -> void:
	_build_scene()
	Settings.changed.connect(_on_setting_changed)
	MapCatalog.texture_ready.connect(_on_texture_ready)
	QuakeService.quakes_updated.connect(func(_q: Array) -> void: _sync_quakes())
	CityDB.user_data_changed.connect(func() -> void:
		_rebuild_pois()
		_rebuild_regions()
		_rebuild_quakes())
	_apply_map()
	_rebuild_all()
	_update_time(true)

# MARK: - Scene construction

## Builds the 3D world: the environment, the Earth system (tilted by the Sun's declination, with the Earth sphere,
## shadow caster, sea sphere and the parent nodes for cities, quakes, hours, grid, sites, POIs, satellites and
## regions), the noon line, poles, cubic Earth, the Sun and moon lights, the Moon, the camera and the sky. The welcome
## text is started later by [method start_intro].
func _build_scene() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Settings.get_color("color_background")
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.5, 0.55, 0.7)
	_env.ambient_light_energy = 0.05
	# A soft studio-like sky provides the reflections that make metal (the gold balls) look metallic.
	var refl_sky := ProceduralSkyMaterial.new()
	refl_sky.sky_top_color = Color("#9fb8d8")
	refl_sky.sky_horizon_color = Color("#fff1d0")
	refl_sky.ground_horizon_color = Color("#fff1d0")
	refl_sky.ground_bottom_color = Color("#d9c9a0")
	refl_sky.sky_energy_multiplier = 1.6
	refl_sky.ground_horizon_color = Color("#fff6dc")
	var refl := Sky.new()
	refl.sky_material = refl_sky
	_env.sky = refl
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)

	# The whole Earth system is tilted by the sun's declination, as in Flatland, so the sun stays
	# directly behind the viewer and the seasons show: the axis leans toward the sun in summer.
	_system = Node3D.new()
	_system.name = "System"
	add_child(_system)

	_fixed = Node3D.new()
	_fixed.name = "Fixed"
	_system.add_child(_fixed)

	_earth = Node3D.new()
	_earth.name = "Earth"
	_system.add_child(_earth)

	var shader: Shader = load("res://shaders/earth.gdshader")
	_earth_mat = ShaderMaterial.new()
	_earth_mat.shader = shader
	_earth_mat.set_shader_parameter("albedo_color", Color(0.12, 0.2, 0.35))
	_earth_mesh = MeshInstance3D.new()
	_earth_mesh.name = "Sphere"
	_earth_mesh.mesh = _make_sphere_mesh(R, 160, 80)
	_earth_mesh.material_override = _earth_mat
	_earth_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_earth.add_child(_earth_mesh)

	# Invisible, slightly smaller sphere that casts the Earth's shadow, so objects on the night side
	# are not lit by the sun from the side.
	var caster := MeshInstance3D.new()
	caster.mesh = _make_sphere_mesh(R - 0.3, 64, 32)
	caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	caster.layers = EARTH_SHADOW_LAYER   # lets the 3D-shadows option keep this one while turning the rest off
	_earth.add_child(caster)

	# Maps with transparent seas (Standard, etc.) sit on top of a sea sphere, as in Flatland.
	_sea_mat = ShaderMaterial.new()
	_sea_mat.shader = shader
	_sea_mat.set_shader_parameter("albedo_color", Color("#9cc3dd"))
	_sea_mesh = MeshInstance3D.new()
	_sea_mesh.name = "Sea"
	_sea_mesh.mesh = _make_sphere_mesh(R - 0.02, 128, 64)
	_sea_mesh.material_override = _sea_mat
	_sea_mesh.visible = false
	_sea_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_earth.add_child(_sea_mesh)

	_cities_node = _child(_earth, "Cities")
	_quakes_node = _child(_earth, "Earthquakes")
	_hours_earth = _child(_earth, "HoursEarth")
	_grid_node = _child(_earth, "Grid")
	_sites_node = _child(_earth, "HeritageSites")
	_pois_node = _child(_earth, "POIs")
	_sat_node = _child(_earth, "Satellites")
	_regions_node = _child(_earth, "Regions")
	_hours_fixed = _child(_fixed, "HoursFixed")

	_noon_line = MeshInstance3D.new()
	_fixed.add_child(_noon_line)

	_build_poles()
	_build_cube()
	# The welcome text is started by `start_intro` once the rest of the start-up work is done, so it does not stall.

	_sun = DirectionalLight3D.new()
	_sun.light_energy = 0.8
	_sun.light_color = Color.WHITE
	_sun.light_cull_mask = 0xFFFFF & ~NIGHT_LAYER
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 215.0
	_sun.shadow_bias = 0.03
	_sun.shadow_normal_bias = 0.5
	_sun.shadow_opacity = 0.75
	_apply_shadows()
	add_child(_sun)

	_moon = DirectionalLight3D.new()
	_moon.light_energy = 0.1
	_moon.light_color = Color.CYAN
	_moon.light_cull_mask = 0xFFFFF & ~MOON_LAYER
	add_child(_moon)
	_build_moon()

	_orbit = Node3D.new()
	_orbit.name = "Orbit"
	add_child(_orbit)
	_camera = Camera3D.new()
	_camera.fov = CAMERA_FOV
	_camera.near = 135.0
	_camera.far = 215.0
	_camera.position = Vector3(0, 0, _distance)
	_orbit.add_child(_camera)
	_camera.current = true
	_build_sky()

## Builds the Moon: a sphere of its true size (0.27 Earth diameters) textured with the lunar map. It sits at its true
## distance (about 60 Earth radii) by [method _place_moon]; the Sun lights it, so its phase is right without extra
## work.
func _build_moon() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://Assets/Moon/LROMoon.png")
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_moon_body = MeshInstance3D.new()
	_moon_body.name = "Moon"
	_moon_body.mesh = _make_sphere_mesh(Lunar.RADIUS_KM / Geo.EARTH_KM * R, 96, 48)
	_moon_body.material_override = mat
	_moon_body.layers = MOON_LAYER
	_moon_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_moon_body.visible = Settings.get_bool("show_moon")
	add_child(_moon_body)

## Puts the Moon where it is in the sky (the same frame the stars use) and turns its near side to the Earth with its
## north up. Then re-fits the camera, since the far plane depends on the Moon's distance.
##
## [param now]: Unix time in seconds (UTC).
func _place_moon(now: float) -> void:
	if _moon_body == null:
		return
	var pos := Lunar.position(now)
	_moon_distance = float(pos["distance_km"]) / Geo.EARTH_KM * R
	var dir := (_stars_basis * Lunar.equatorial_direction(pos)).normalized()
	var toward_earth := -dir
	var pole := _stars_basis * Lunar.pole_direction()
	var up := (pole - toward_earth * pole.dot(toward_earth)).normalized()
	_moon_body.transform = Transform3D(Basis(up.cross(toward_earth), up, toward_earth), dir * _moon_distance)
	_apply_camera()

## Makes an empty named child node.
##
## [param parent]: the node to add to.
## [param node_name]: the new node's name.
## Returns: the new Node3D.
func _child(parent: Node, node_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	parent.add_child(n)
	return n

## Builds a UV sphere with longitude 0 facing +Z and the texture's left edge at -180 degrees, so equirectangular maps
## fit.
##
## [param radius]: sphere radius.
## [param segments]: divisions around.
## [param rings]: divisions from pole to pole.
## Returns: the ArrayMesh.
func _make_sphere_mesh(radius: float, segments: int, rings: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for y in range(rings + 1):
		var lat := 90.0 - 180.0 * float(y) / float(rings)
		for x in range(segments + 1):
			var lon := -180.0 + 360.0 * float(x) / float(segments)
			var n := Geo.to_vec3(lat, lon, 1.0)
			verts.append(n * radius)
			norms.append(n)
			uvs.append(Vector2(float(x) / float(segments), float(y) / float(rings)))
	for y in range(rings):
		for x in range(segments):
			var a := y * (segments + 1) + x
			var b := a + segments + 1
			idx.append_array([a, a + 1, b, a + 1, b + 1, b])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Builds the candy-striped pole through the Earth with a gold ball at each end (Flatland's PolarShape). It is two
## half-poles (stored in [member _pole_shafts]) that spin slowly about their axis, so the diagonal stripes climb like
## a barber pole. Added under [member _fixed].
func _build_poles() -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in range(64):
		for x in range(64):
			var stripe := int(floor((x + y) / 16.0)) % 2 == 0
			img.set_pixel(x, y, Color("#d42a2a") if stripe else Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	var shaft_mat := StandardMaterial3D.new()
	shaft_mat.albedo_texture = tex
	shaft_mat.uv1_scale = Vector3(1, 8.7, 1)   # stripes at about 45 degrees
	shaft_mat.texture_repeat = true
	shaft_mat.roughness = 0.5
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color("#ffcf40")
	gold.metallic = 1.0
	gold.metallic_specular = 1.0
	gold.roughness = 0.45
	_poles = Node3D.new()
	_poles.name = "Poles"
	_fixed.add_child(_poles)
	for sign_v in [1.0, -1.0]:
		var shaft := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.22
		cyl.bottom_radius = 0.22
		cyl.height = 12.0
		shaft.mesh = cyl
		shaft.material_override = shaft_mat
		shaft.position = Vector3(0, 6.0 * sign_v, 0)
		_poles.add_child(shaft)
		_pole_shafts.append(shaft)
		var ball := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.55
		sph.height = 1.1
		ball.mesh = sph
		ball.material_override = gold
		ball.position = Vector3(0, 12.0 * sign_v, 0)
		_poles.add_child(ball)

# MARK: - Settings and map handling

## Reacts to a changed setting by updating only what it affects: the map, cities, grid, hour labels, Sun/Moon balls,
## the Moon, moonlight, stars, satellites, shadows, earthquakes, heritage sites, points of interest, regions, the
## cubic/sphere view, colors, the debugger clock, or the world lock (which resets the view).
##
## [param key]: the setting's key.
## [param _value]: its new value (read again from Settings by each handler).
func _on_setting_changed(key: String, _value: Variant) -> void:
	match key:
		"map_type":
			_apply_map()
		"show_cities", "city_filter", "city_rank", "show_city_names", "city_shape", "city_scale":
			_rebuild_cities()
		"show_grid", "show_equator", "show_polar_circles", "show_tropics", \
		"show_noon_meridians", "show_minor_grid":
			_rebuild_grid()
		"hour_type", "home_latitude", "home_longitude":
			_last_hour_stamp = -1
			_rebuild_hours()
		"show_sun_point", "show_moon_point":
			_place_solar_lunar_points(Solar.now())
		"show_moon":
			_moon_body.visible = Settings.get_bool("show_moon")
			_apply_camera()
		"show_moon_light":
			_moon.visible = Settings.get_bool("show_moon_light")
			_update_time(false)
		"show_stars", "show_sun":
			_apply_stars()
		"show_satellites":
			_sat_node.visible = Settings.get_bool("show_satellites")
			_apply_camera()
		"show_shadows_3d", "graphics_quality":
			_apply_shadows()
		"enable_earthquakes", "quake_min_magnitude", "quake_max_age_days", "quake_shape", "quake_scale", \
		"quake_indicator", "quake_highlight_new", "quake_recent_hours", "quake_group", "quake_group_km", "quake_outlines":
			_rebuild_quakes()
		"show_heritage_sites":
			_rebuild_sites()
		"show_user_pois":
			_rebuild_pois()
		"show_regions":
			_rebuild_regions()
		"view_type":
			set_cubic(Settings.get_string("view_type") == Settings.VIEW_CUBIC)
		"color_grid":
			_rebuild_grid()
			_rebuild_regions()
		"color_hours":
			_rebuild_hours()
		"label_font", "color_city_capital", "color_city_africa", "color_city_asia", "color_city_europe", \
		"color_city_north_america", "color_city_south_america":
			_rebuild_cities()
			_rebuild_hours()
		"color_background":
			_apply_stars()
		"debug_time_tick":
			_update_time(true)
		"world_locked":
			if Settings.get_bool("world_locked"):
				reset_view()

## Puts the map chosen by the `map_type` setting on the Earth: remembers its file names, shows or hides the sea
## sphere, and asks [MapCatalog] for the pictures (if they are not loaded yet, [method _on_texture_ready] applies them
## later).
func _apply_map() -> void:
	var m := MapCatalog.map_for(Settings.get_string("map_type"))
	if m.is_empty():
		return
	_current_map_file = str(m["globe"])
	_sea_file = str(m.get("sea", ""))
	_sea_mesh.visible = _sea_file != ""
	if _sea_file != "":
		var sea_tex := MapCatalog.request(_sea_file)
		if sea_tex != null:
			_set_tex(_sea_mat, sea_tex)
	var tex := MapCatalog.request(_current_map_file)
	if tex != null:
		_set_earth_texture(tex)

## A map picture finished loading: applies it if it is the current map or sea, and refreshes the stars when the Tycho
## sky map arrives (it is the star field's background).
##
## [param file_name]: the file that arrived.
## [param tex]: its texture.
func _on_texture_ready(file_name: String, tex: Texture2D) -> void:
	if file_name == _current_map_file:
		_set_earth_texture(tex)
	if file_name == _sea_file and _sea_file != "":
		_set_tex(_sea_mat, tex)
	elif file_name == "TychoSky.png":
		_apply_stars()

## Puts a texture on the Earth's material and resets its base color to white so the picture shows true.
##
## [param tex]: the map texture.
func _set_earth_texture(tex: Texture2D) -> void:
	_set_tex(_earth_mat, tex)
	_earth_mat.set_shader_parameter("albedo_color", Color.WHITE)

## Gives a shader material a map texture and switches its texturing on.
##
## [param mat]: the Earth or sea material.
## [param tex]: the texture.
func _set_tex(mat: ShaderMaterial, tex: Texture2D) -> void:
	mat.set_shader_parameter("albedo_tex", tex)
	mat.set_shader_parameter("use_tex", true)

## Turns the 3D shadows cast by labels, cities and the like on or off, from the `show_shadows_3d` setting and the
## graphics quality ([method PowerManager.shadows_allowed]). The invisible sphere that shades the night side is on its
## own layer and always keeps casting, so night-side objects stay dark.
func _apply_shadows() -> void:
	var on := Settings.get_bool("show_shadows_3d") and PowerManager.shadows_allowed()
	_sun.shadow_caster_mask = 0xFFFFF if on else EARTH_SHADOW_LAYER

## Builds the sky: a large sphere (with the Sun's picture) centered on, and moving with, the camera, sitting just
## beyond everything else, plus the stars ([method _build_stars]).
func _build_sky() -> void:
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load("res://shaders/sky.gdshader")
	_sky_mat.render_priority = -100
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 96
	sphere.rings = 48
	_sky_mesh = MeshInstance3D.new()
	_sky_mesh.name = "StarField"
	_sky_mesh.mesh = sphere
	_sky_mesh.material_override = _sky_mat
	_sky_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sky_mesh.extra_cull_margin = 16384.0
	_camera.add_child(_sky_mesh)
	_build_stars()

## The star under the mouse changed (macOS only; shown with a tooltip that main.gd draws beside the pointer). The
## stars are the 2000 brightest (HYG catalogue, data/bright_stars.json) plotted by right ascension and declination as
## points on a sphere centered on the camera; being at infinity, they are seen by direction only.
##
## [param text]: the star's description, or "" when none.
## [param position]: the mouse position in pixels.
signal star_tooltip_changed(text: String, position: Vector2)
## How close in pixels the mouse must be to a star to select it for the tooltip.
const STAR_HOVER_SLOP := 10.0
## Each star's direction as a unit vector in the star frame (before [member _stars_basis]).
var _star_dirs: Array[Vector3] = []
## Each star's catalogue row: [RA, Dec, magnitude, B-V color index, name, spectral type].
var _star_info: Array = []
## The tooltip text last sent, so it is only sent when it changes.
var _last_star_tip := ""
## Rotation from the star frame to the scene: turns the sky so the Sun's right ascension faces +Z, then tilts it by
## the declination. Set by [method _update_time]; also used for the Moon.
var _stars_basis := Basis.IDENTITY

## Finds the star under the mouse (within [constant STAR_HOVER_SLOP] pixels, in front of the camera, and not hidden by
## the globe, poles, Sun or welcome text) and describes it.
##
## [param mouse]: the mouse position in pixels.
## Returns: the star's name (if it has one), magnitude and type, as lines of text; "" if no star is there.
func star_tooltip_at(mouse: Vector2) -> String:
	if _stars_node == null or not _stars_node.visible or _star_dirs.is_empty():
		return ""
	var cam_pos := _camera.global_position
	var best := -1
	var best_dist := STAR_HOVER_SLOP
	for i in range(_star_dirs.size()):
		var dir := (_stars_basis * _star_dirs[i]).normalized()
		if _camera.is_position_behind(cam_pos + dir * 1000.0):
			continue
		var d := mouse.distance_to(_camera.unproject_position(cam_pos + dir * 1000.0))
		if d >= best_dist:
			continue
		if _star_obscured(cam_pos, dir):
			continue
		best = i
		best_dist = d
	if best < 0:
		return ""
	var info: Array = _star_info[best]
	var lines: PackedStringArray = []
	if str(info[4]) != "":
		lines.append(str(info[4]))
	lines.append("Brightness: magnitude %.2f" % float(info[2]))
	lines.append("Type: %s" % (str(info[5]) if str(info[5]) != "" else "unknown"))
	return "\n".join(lines)

## Whether something in front of the sky hides a star: the globe (with a small margin), the poles, the Sun's disk, or
## the welcome text.
##
## [param cam_pos]: the camera position.
## [param dir]: the unit direction to the star.
## Returns: true if hidden.
func _star_obscured(cam_pos: Vector3, dir: Vector3) -> bool:
	# The globe (with a little margin for the sea, grid and markers).
	if _ray_hits_sphere(cam_pos, dir, Vector3.ZERO, Geo.GLOBE_RADIUS + 0.3):
		return true
	# The polar poles: a thin shaft along the (tilted) axis with a ball at each end.
	var axis := _system.global_basis.y.normalized()
	for sign_y: float in [-1.0, 1.0]:
		if _ray_hits_sphere(cam_pos, dir, axis * 12.0 * sign_y, 0.6):
			return true
	if _ray_segment_distance(cam_pos, dir, axis * -12.0, axis * 12.0) < 0.3:
		return true
	# The sun's disk and glow (it lies in the +Z direction).
	if Settings.get_bool("show_sun") and dir.angle_to(Vector3(0, 0, 1)) < deg_to_rad(0.8):
		return true
	# The welcome text, while it is showing.
	if is_instance_valid(_intro) and _intro.occludes(cam_pos, dir):
		return true
	return false

## Whether a ray passes through a sphere, in front of its origin.
##
## [param origin]: ray start.
## [param dir]: ray direction (a unit vector).
## [param center]: sphere center.
## [param radius]: sphere radius.
## Returns: true if it hits.
static func _ray_hits_sphere(origin: Vector3, dir: Vector3, center: Vector3, radius: float) -> bool:
	var oc := origin - center
	var b := oc.dot(dir)
	var disc := b * b - (oc.length_squared() - radius * radius)
	return disc > 0.0 and -b + sqrt(disc) > 0.0

## The shortest distance between a ray (start plus a non-negative multiple of the direction) and a line segment.
##
## [param origin]: ray start.
## [param dir]: ray direction.
## [param a]: one end of the segment.
## [param b]: the other end.
## Returns: the distance; used to test whether a ray passes near the pole shaft.
static func _ray_segment_distance(origin: Vector3, dir: Vector3, a: Vector3, b: Vector3) -> float:
	var seg := b - a
	var w := origin - a
	var dd := dir.dot(dir)
	var ds := dir.dot(seg)
	var ss := seg.dot(seg)
	var denom := dd * ss - ds * ds
	var t := 0.0
	var u := clampf(w.dot(seg) / ss, 0.0, 1.0)
	if absf(denom) > 1e-9:
		t = maxf((ds * w.dot(seg) - ss * w.dot(dir)) / denom, 0.0)
		u = clampf((w.dot(seg) + t * ds) / ss, 0.0, 1.0)
	return (origin + dir * t).distance_to(a + seg * u)

## Updates the star tooltip as the mouse moves (macOS only): finds the star with [method star_tooltip_at] and emits
## [signal star_tooltip_changed] if it changed.
##
## [param mouse]: the mouse position in pixels.
func _update_star_tooltip(mouse: Vector2) -> void:
	if OS.get_name() != "macOS":
		return
	var tip := star_tooltip_at(mouse)
	if tip != _last_star_tip:
		_last_star_tip = tip
		star_tooltip_changed.emit(tip, mouse)

## Radius of the star sphere around the camera: just inside the camera's far plane. Set by [method _apply_camera].
var _sky_radius := 200.0
## The angle in radians one screen pixel covers at the current field of view; the stars' shader uses it to draw stars
## the same size in pixels at any zoom. Set by [method _apply_camera].
var _pixel_angle := 0.0002

## Centers the star sphere on the camera, orients it with [member _stars_basis] and gives the shader the current pixel
## size.
func _place_stars() -> void:
	if _stars_node == null:
		return
	_stars_node.global_transform = Transform3D(_stars_basis.scaled(Vector3.ONE * _sky_radius), _camera.global_position)
	_stars_mat.set_shader_parameter("pixel_angle", _pixel_angle)

## Builds the star field from data/bright_stars.json: a small camera-facing quad per star, colored by its color index
## ([method _star_color]). Brightness follows the star's magnitude (every magnitude is 2.5 times fainter than the one
## before, shown a little flatter, with the faintest kept visible), and brighter stars are drawn a little bigger.
func _build_stars() -> void:
	var rows: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/bright_stars.json"))
	if not (rows is Array):
		return
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var sizes := PackedVector2Array()
	var indices := PackedInt32Array()
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for row in rows:
		_star_dirs.append(Vector3(cos(deg_to_rad(float(row[1]))) * sin(deg_to_rad(float(row[0]))), sin(deg_to_rad(float(row[1]))), cos(deg_to_rad(float(row[1]))) * cos(deg_to_rad(float(row[0])))))
		_star_info.append(row)
		var ra := deg_to_rad(float(row[0]))
		var dec := deg_to_rad(float(row[1]))
		var mag := float(row[2])
		var d := Vector3(cos(dec) * sin(ra), sin(dec), cos(dec) * cos(ra))
		# Brightness follows the star's magnitude: every magnitude is 2.5 times fainter than the one before (shown a little
		# flatter than that, or the faint stars would vanish). Brighter stars are also drawn a little bigger.
		var bright := clampf(pow(10.0, -0.24 * (mag - 0.5)), 0.1, 1.0)
		var size_px := 2.5 + 7.5 * sqrt(bright)
		var c := _star_color(float(row[3])) * bright
		var base := verts.size()
		for k in range(4):
			verts.append(d)
			uvs.append(corners[k])
			colors.append(Color(c.r, c.g, c.b, 1.0))
			sizes.append(Vector2(size_px, 0.0))
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV2] = sizes
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_stars_mat = ShaderMaterial.new()
	_stars_mat.shader = load("res://shaders/stars.gdshader")
	_stars_mat.render_priority = -90
	_stars_node = MeshInstance3D.new()
	_stars_node.name = "Stars"
	_stars_node.mesh = mesh
	_stars_node.material_override = _stars_mat
	_stars_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stars_node.extra_cull_margin = 16384.0
	add_child(_stars_node)
	_apply_stars()

## Approximate color of a star from its B-V color index, from blue-white through white and yellow to orange-red.
##
## [param bv]: the B-V color index (about -0.3 hot to 2 cool).
## Returns: the Color.
func _star_color(bv: float) -> Color:
	var blue := Color(0.5, 0.65, 1.0)
	var white := Color(0.95, 0.95, 1.0)
	var yellow := Color(1.0, 0.88, 0.45)
	var orange := Color(1.0, 0.62, 0.28)
	var red := Color(1.0, 0.38, 0.22)
	if bv < 0.2:
		return blue.lerp(white, clampf((bv + 0.2) / 0.4, 0.0, 1.0))
	if bv < 0.6:
		return white.lerp(yellow, (bv - 0.2) / 0.4)
	if bv < 1.2:
		return yellow.lerp(orange, (bv - 0.6) / 0.6)
	return orange.lerp(red, clampf((bv - 1.2) / 0.6, 0.0, 1.0))

## Shows or hides the sky sphere (it carries the Sun's picture) and the star points, and tells the sky shader whether
## to draw the Sun, from the `show_sun` and `show_stars` settings.
func _apply_stars() -> void:
	if _sky_mat == null:
		return
	var sun_on := Settings.get_bool("show_sun")
	_sky_mesh.visible = sun_on
	_sky_mat.set_shader_parameter("use_sun", sun_on)
	if _stars_node != null:
		_stars_node.visible = Settings.get_bool("show_stars")

# MARK: - Content (cities, grid, hours, quakes)

## Builds all the content from scratch: view type (sphere or cube), grid, cities, hour labels, earthquakes, heritage
## sites, points of interest, regions, moonlight and the stars. Called once at start-up.
func _rebuild_all() -> void:
	set_cubic(Settings.get_string("view_type") == Settings.VIEW_CUBIC)
	_rebuild_grid()
	_rebuild_cities()
	_rebuild_hours()
	_rebuild_quakes()
	_rebuild_sites()
	_rebuild_pois()
	_rebuild_regions()
	_moon.visible = Settings.get_bool("show_moon_light")
	_apply_stars()

## Frees all the children of a node (queued).
##
## [param node]: the node to empty.
func _clear(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()

## A pair of materials for a color: one for day and one for night. At night the object glows in its own color, as in
## Flatland. Cached.
##
## [param color]: the object's color.
## [param glow]: the glow color used at night.
## Returns: [day material, night material].
func _mat_pair(color: Color, glow: Color) -> Array:
	var key := "%s|%s" % [color.to_html(), glow.to_html()]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var day := StandardMaterial3D.new()
	day.albedo_color = color
	day.roughness = 0.4
	day.metallic_specular = 0.6
	var night := day.duplicate() as StandardMaterial3D
	night.emission_enabled = true
	night.emission = glow
	night.emission_energy_multiplier = 0.4
	_mat_cache[key] = [day, night]
	return _mat_cache[key]

## Gives a marker the day or night material for its place and remembers it, so [method _refresh_day_night] can switch
## it as the terminator moves. Night objects also go to [constant NIGHT_LAYER].
##
## [param node]: the marker.
## [param lat]: its latitude.
## [param lon]: its longitude.
## [param color]: the day color.
## [param glow]: the night glow color.
func _register_dn(node: MeshInstance3D, lat: float, lon: float, color: Color, glow: Color) -> void:
	var pair := _mat_pair(color, glow)
	_dn_items.append({"node": node, "lat": lat, "lon": lon, "day": pair[0], "night": pair[1]})
	var day_now := Solar.is_daylight(lat, lon, Solar.now())
	node.material_override = pair[0] if day_now else pair[1]
	_set_night_layer(node, not day_now)

## Called once a minute: switches the material and render layer of each registered object ([member _dn_items]) that
## has crossed the terminator. Only changed objects are touched, because changing every object each minute made the
## whole scene re-prepare and caused a visible hitch.
func _refresh_day_night() -> void:
	var now := Solar.now()
	for it in _dn_items:
		if is_instance_valid(it["node"]):
			var day_now := Solar.is_daylight(it["lat"], it["lon"], now)
			# Only an object that has crossed the terminator is touched: changing the material or the render layer of
			# every object each minute made the whole scene re-prepare, a visible half-second hitch.
			if it.get("is_day") == day_now:
				continue
			it["is_day"] = day_now
			it["node"].material_override = it["day"] if day_now else it["night"]
			_set_night_layer(it["node"], not day_now)

## Puts an object on the night render layer, which the Sun's light ignores, so the Sun cannot light its sides near the
## edge of the lit half. (The moon light and the object's own glow still apply.)
##
## [param node]: the object.
## [param night]: true to move it to [constant NIGHT_LAYER], false for the normal layer.
func _set_night_layer(node: MeshInstance3D, night: bool) -> void:
	node.layers = NIGHT_LAYER if night else 1

## Builds extruded text lying on the surface, readable from outside, centered on its position and bent to follow the
## globe ([method Shapes.bend_text]).
##
## [param text]: the words.
## [param lat]: latitude of the anchor.
## [param lon]: longitude of the anchor.
## [param radius]: distance from the Earth's center.
## [param em]: text size in scene units.
## [param depth]: extrusion depth.
## [param top_anchor]: true to hang the text from its anchor (like Flatland's top-center pivot) instead of centering
##   it.
## [param font]: a font, or null for the label font.
## Returns: the MeshInstance3D.
func _flat_text(text: String, lat: float, lon: float, radius: float, em: float, depth: float, top_anchor: bool = false, font: Font = null) -> MeshInstance3D:
	var tm := TextMesh.new()
	tm.text = text
	tm.font = font if font != null else Geo.label_font()
	tm.font_size = 64
	tm.pixel_size = em / 64.0
	tm.depth = depth
	tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var mi := MeshInstance3D.new()
	mi.mesh = Shapes.bend_text(tm, radius)
	var basis := Geo.surface_basis(lat, lon)
	var pos := Geo.to_vec3(lat, lon, radius)
	if top_anchor:
		pos -= basis.y * (em * 0.5)    # text hangs from its anchor, like Flatland's top-center pivot
	mi.transform = Transform3D(basis, pos)
	return mi

## Makes a node standing on the surface with its local +Y pointing away from the globe, so shapes can be built
## upright.
##
## [param lat]: latitude.
## [param lon]: longitude.
## [param radius]: distance from the Earth's center.
## Returns: the Node3D (not yet added to a parent).
func _up_node(lat: float, lon: float, radius: float) -> Node3D:
	var b := Geo.surface_basis(lat, lon)
	var n := Node3D.new()
	n.transform = Transform3D(Basis(b.x, b.z, b.x.cross(b.z)), Geo.to_vec3(lat, lon, radius))
	return n

## A city's size for scaling its marker: the larger of its own and its metropolitan-area population.
##
## [param c]: a city Dictionary.
## Returns: the population.
func _city_population(c: Dictionary) -> int:
	return maxi(int(c.get("Population", 0)), int(c.get("MetropolitanPopulation", 0)))

## Rebuilds the city markers in the shape chosen in Preferences (Flatland's CityDisplayTypes): flush or relative
## spheres, floating spheres or boxes, boxes, cylinders, pyramids, sticks or names. Every shape glows in its own color
## at night; names lie flat on the map, dark blue by day and teal by night. Sizes follow the population relative to
## the largest city. Called when any city setting changes.
func _rebuild_cities() -> void:
	_clear(_cities_node)
	_dn_items = _dn_items.filter(func(i): return not (is_instance_valid(i["node"]) and i["node"].get_parent() == _cities_node))
	if not Settings.get_bool("show_cities"):
		return
	var shape := Settings.get_string("city_shape")
	var mult := Shapes.scale_for("city_scale")
	var names := Settings.get_bool("show_city_names")
	var list := CityDB.filtered_cities()
	var max_pop := 1
	var min_pop := 1 << 40
	for c in list:
		var p := _city_population(c)
		max_pop = maxi(max_pop, p)
		if p > 0:
			min_pop = mini(min_pop, p)
	for c in list:
		var lat: float = c["Latitude"]
		var lon: float = c["Longitude"]
		var col := Geo.city_color(c)
		var pop := _city_population(c)
		var rel := float(pop if pop > 0 else min_pop) / float(max_pop)
		if shape == "Names":
			var nt := _flat_text(" " + str(c["Name"]), lat, lon, R + 0.9, 0.7, 0.07)
			_cities_node.add_child(nt)
			_register_dn(nt, lat, lon, col, col)
			_city_stick(c, col, 0.8, mult)
			continue
		if names:
			var t := _flat_text(str(c["Name"]), lat, lon, R + 0.11, 0.7, 0.07)
			_cities_node.add_child(t)
			_register_dn(t, lat, lon, Color("#003153"), Color("#30b0c7"))
		match shape:
			"Uniform Flush Spheres":
				_city_flush_sphere(c, col, maxf(0.15, 0.15))
			"Relative Flush Spheres":
				_city_flush_sphere(c, col, maxf(0.15, rel * 0.35))
			"Floating Spheres":
				_city_floating(c, col, rel, true, mult)
			"Floating Boxes":
				_city_floating(c, col, rel, false, mult)
			"Boxes":
				_city_block(c, col, rel, true, mult)
			"Cylinders":
				_city_block(c, col, rel, false, mult)
			"Pyramids":
				_city_pyramid(c, col, rel, mult)
			"Sticks":
				_city_stick(c, col, 0.5, mult)
			_:
				_city_flush_sphere(c, col, 0.15)

## Adds a small sphere lying on the surface for a city.
##
## [param c]: the city Dictionary.
## [param col]: its color.
## [param size]: the sphere's radius.
func _city_flush_sphere(c: Dictionary, col: Color, size: float) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = size
	sphere.height = size * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.position = Geo.to_vec3(c["Latitude"], c["Longitude"], R - size * 0.5 + 0.05)
	_cities_node.add_child(mi)
	_register_dn(mi, c["Latitude"], c["Longitude"], col, col)

## Adds a sphere or box on a stem (colored with the complement of the city color) floating above the surface
## (Flatland's floating cities).
##
## [param c]: the city Dictionary.
## [param col]: its color.
## [param rel]: its population relative to the largest city (0 to 1), which sets the size.
## [param is_sphere]: true for a sphere, false for a box.
## [param mult]: the overall size factor from the `city_scale` setting.
func _city_floating(c: Dictionary, col: Color, rel: float, is_sphere: bool, mult: float) -> void:
	var lat: float = c["Latitude"]
	var lon: float = c["Longitude"]
	var size := maxf(0.5 * rel, 0.15)
	var stem_len := maxf(2.0 * rel, 0.1)
	var holder := _up_node(lat, lon, R + 0.1)
	holder.scale = Vector3.ONE * mult
	_cities_node.add_child(holder)
	var stem := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.04
	cyl.bottom_radius = 0.04
	cyl.height = stem_len
	stem.mesh = cyl
	stem.material_override = Shapes.plain(Shapes.complement(col))
	holder.add_child(stem)
	var body := MeshInstance3D.new()
	if is_sphere:
		var sph := SphereMesh.new()
		sph.radius = size
		sph.height = size * 2.0
		body.mesh = sph
		holder.add_child(body)
		_register_dn(body, lat, lon, col, col)
	else:
		body.mesh = Shapes.outlined_box(Vector3.ONE * size * 2.0)
		holder.add_child(body)
		_register_outline(body, lat, lon, col)
	body.position = Vector3(0, stem_len - size, 0)

## Adds a tall box or cylinder whose height follows the population (Flatland's "Boxes" and "Cylinders").
##
## [param c]: the city Dictionary.
## [param col]: its color.
## [param rel]: its population relative to the largest city.
## [param is_box]: true for a box (with the outlined texture), false for a cylinder.
## [param mult]: the overall size factor.
func _city_block(c: Dictionary, col: Color, rel: float, is_box: bool, mult: float) -> void:
	var lat: float = c["Latitude"]
	var lon: float = c["Longitude"]
	var size := maxf(rel * 2.0, 0.33)
	var hdim := maxf(size * 0.1, 0.25)
	var holder := _up_node(lat, lon, R + size * 0.5 * mult)
	holder.scale = Vector3.ONE * mult
	_cities_node.add_child(holder)
	var mi := MeshInstance3D.new()
	if is_box:
		mi.mesh = Shapes.outlined_box(Vector3(hdim, size, hdim))
		holder.add_child(mi)
		_register_outline(mi, lat, lon, col)
	else:
		var cyl := CylinderMesh.new()
		cyl.top_radius = hdim * 0.5
		cyl.bottom_radius = hdim * 0.5
		cyl.height = size
		mi.mesh = cyl
		holder.add_child(mi)
		_register_dn(mi, lat, lon, col, col)

## Adds a pyramid standing on the surface, its height following the population.
##
## [param c]: the city Dictionary.
## [param col]: its color.
## [param rel]: its population relative to the largest city.
## [param mult]: the overall size factor.
func _city_pyramid(c: Dictionary, col: Color, rel: float, mult: float) -> void:
	var lat: float = c["Latitude"]
	var lon: float = c["Longitude"]
	var size := maxf(rel * 2.0, 0.33)
	var hdim := maxf(size * 0.1, 0.25)
	var holder := _up_node(lat, lon, R)
	holder.scale = Vector3.ONE * mult
	_cities_node.add_child(holder)
	var mi := MeshInstance3D.new()
	mi.mesh = Shapes.pyramid_mesh(hdim, size, hdim)
	holder.add_child(mi)
	_register_dn(mi, lat, lon, col, col)

## Adds a thin stick standing on the surface (the "Sticks" shape, and the marker that goes with the "Names" shape).
##
## [param c]: the city Dictionary.
## [param col]: the city color (the stick uses its complement).
## [param height]: the stick's length.
## [param mult]: the overall size factor.
func _city_stick(c: Dictionary, col: Color, height: float, mult: float) -> void:
	var holder := _up_node(c["Latitude"], c["Longitude"], R + 0.1)
	holder.scale = Vector3.ONE * mult
	_cities_node.add_child(holder)
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.04
	cyl.bottom_radius = 0.04
	cyl.height = height
	mi.mesh = cyl
	mi.material_override = Shapes.plain(Shapes.complement(col))
	holder.add_child(mi)

## Like [method _register_dn] but for the textured outlined-block material ([method Shapes.outline_material]), which
## also glows at night.
##
## [param node]: the block.
## [param lat]: its latitude.
## [param lon]: its longitude.
## [param col]: its color.
func _register_outline(node: MeshInstance3D, lat: float, lon: float, col: Color) -> void:
	_dn_items.append({"node": node, "lat": lat, "lon": lon, "day": Shapes.outline_material(col, false), "night": Shapes.outline_material(col, true)})
	var is_night := not Solar.is_daylight(lat, lon, Solar.now())
	node.material_override = Shapes.outline_material(col, is_night)
	_set_night_layer(node, is_night)

## Rebuilds the World Heritage site markers as one MultiMesh of tiny spheres (cheap for many points). Nothing is drawn
## when `show_heritage_sites` is off.
func _rebuild_sites() -> void:
	_clear(_sites_node)
	if not Settings.get_bool("show_heritage_sites"):
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var s := SphereMesh.new()
	s.radius = 0.07
	s.height = 0.14
	s.radial_segments = 6
	s.rings = 3
	mm.mesh = s
	mm.instance_count = CityDB.heritage_sites.size()
	for i in range(CityDB.heritage_sites.size()):
		var h: Dictionary = CityDB.heritage_sites[i]
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Geo.to_vec3(h["Latitude"], h["Longitude"], R + 0.05)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#f6f6c8")
	mat.emission_enabled = true
	mat.emission = Color("#8a8a50")
	mmi.material_override = mat
	_sites_node.add_child(mmi)

## Rebuilds the points of interest, the built-in ones and the user's, as small cones pointing into the surface
## (Flatland's PlotLocationAsCone), glowing at night. Nothing is drawn when `show_user_pois` is off.
func _rebuild_pois() -> void:
	_clear(_pois_node)
	_dn_items = _dn_items.filter(func(i): return not (is_instance_valid(i["node"]) and i["node"].get_parent() == _pois_node))
	if not Settings.get_bool("show_user_pois"):
		return
	var cone := CylinderMesh.new()
	cone.top_radius = 0.15
	cone.bottom_radius = 0.0
	cone.height = 0.45
	for p in CityDB.all_pois():
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		var b := Geo.surface_basis(p["Latitude"], p["Longitude"])
		mi.transform = Transform3D(Basis(b.x, b.z, b.x.cross(b.z)), Geo.to_vec3(p["Latitude"], p["Longitude"], R + 0.05))
		_pois_node.add_child(mi)
		var col := Color(str(p.get("Color", "#ee44cc")))
		_register_dn(mi, p["Latitude"], p["Longitude"], col, col)

## Rebuilds the outlines of the enabled earthquake regions as lines on the globe (a rectangle from the two corners,
## crossing the antimeridian if needed), if `show_regions` is on.
func _rebuild_regions() -> void:
	_clear(_regions_node)
	if not Settings.get_bool("show_regions"):
		return
	for r in CityDB.regions:
		if not r.get("enabled", true):
			continue
		var lat1 := float(r["lat1"])
		var lat2 := float(r["lat2"])
		var lon1 := float(r["lon1"])
		var lon2 := float(r["lon2"])
		if lon2 < lon1:
			lon2 += 360.0
		var pts: Array = []
		var rr := R + 0.03
		for i in range(33):
			pts.append(Geo.to_vec3(lat1, lon1 + (lon2 - lon1) * i / 32.0, rr))
		for i in range(33):
			pts.append(Geo.to_vec3(lat1 + (lat2 - lat1) * i / 32.0, lon2, rr))
		for i in range(33):
			pts.append(Geo.to_vec3(lat2, lon2 - (lon2 - lon1) * i / 32.0, rr))
		for i in range(33):
			pts.append(Geo.to_vec3(lat2 + (lat1 - lat2) * i / 32.0, lon1, rr))
		_regions_node.add_child(_line_mesh([pts], Color(str(r.get("color", "#ffcc00")))))

## Builds the cubic world (Flatland's "silly cube"): six square faces, each textured with its own picture
## (`Assets/Cubic/*.png`) by the cube shader. The faces sit where the globe's longitudes put them: +Z is longitude 0
## (Africa), +X is 90 E (Asia), -Z is 180 (Pacific) and -X is 90 W (the Americas); the pole faces are turned to match.
## SceneKit's box material order (front, right, back, left, top, bottom) gives the names nz, nx, pz, px, py-90, ny90.
## Hidden until [method set_cubic] shows it.
func _build_cube() -> void:
	_cube = Node3D.new()
	_cube.name = "Cube"
	_cube.visible = false
	_earth.add_child(_cube)
	# Faces sit where the globe's longitudes put them: +Z is lon 0 (Africa), +X is 90E (Asia),
	# -Z is 180 (Pacific) and -X is 90W (the Americas). The pole faces are turned to match.
	var yaw := Basis(Vector3.UP, deg_to_rad(90.0))
	var faces := [
		["nz", Vector3(0, 0, 5), Basis()],
		["nx", Vector3(5, 0, 0), Basis(Vector3.UP, deg_to_rad(90.0))],
		["pz", Vector3(0, 0, -5), Basis(Vector3.UP, deg_to_rad(180.0))],
		["px", Vector3(-5, 0, 0), Basis(Vector3.UP, deg_to_rad(-90.0))],
		["py-90", Vector3(0, 5, 0), yaw * Basis.from_euler(Vector3(deg_to_rad(-90.0), 0, 0))],
		["ny90", Vector3(0, -5, 0), yaw * Basis.from_euler(Vector3(deg_to_rad(90.0), 0, 0))],
	]
	for f in faces:
		var quad := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(10, 10)
		quad.mesh = qm
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/cube.gdshader")
		mat.set_shader_parameter("albedo_tex", load("res://Assets/Cubic/%s.png" % f[0]))
		mat.set_shader_parameter("use_tex", true)
		_cube_mats.append(mat)
		quad.material_override = mat
		quad.position = f[1]
		quad.basis = f[2]
		_cube.add_child(quad)

## Puts the balls under the Sun and Moon in place, creating them on first use, and shows each according to its
## setting. On the sphere a ball floats just above the surface; on the cube it sits on the cube's surface, where the
## line from the center to the point meets it.
##
## [param now]: Unix time in seconds (UTC).
## Called from [method _update_time], [method set_cubic] and when a setting changes.
func _place_solar_lunar_points(now: float) -> void:
	if _sun_point == null:
		var r := Geo.GLOBE_RADIUS * SolarLunarMarker.GLOBE_FRACTION
		_sun_point = SolarLunarMarker.build(SolarLunarMarker.SUN_COLOR, r)
		_moon_point = SolarLunarMarker.build(SolarLunarMarker.MOON_COLOR, r)
		_earth.add_child(_sun_point)
		_earth.add_child(_moon_point)
	_sun_point.visible = SolarLunarMarker.sun_enabled()
	_moon_point.visible = SolarLunarMarker.moon_enabled()
	var pairs := [[_sun_point, SolarLunarMarker.sun_point(now)], [_moon_point, SolarLunarMarker.moon_point(now)]]
	for pair in pairs:
		var at: Vector2 = pair[1]
		var dir := Geo.to_vec3(at.x, at.y, 1.0)
		var node: MeshInstance3D = pair[0]
		if _cubic:
			var half := Geo.GLOBE_RADIUS * 0.5       # the cube is half the globe's diameter across
			var longest := maxf(absf(dir.x), maxf(absf(dir.y), absf(dir.z)))
			node.position = dir * (half / longest + Geo.GLOBE_RADIUS * SolarLunarMarker.GLOBE_FRACTION)
		else:
			node.position = dir * Geo.GLOBE_RADIUS * 1.05

## Switches between the sphere and the cubic world: shows the cube (or the sphere, sea, cities, quakes, grid, sites,
## points of interest and regions), hides the noon line on the cube, and re-places the Sun/Moon balls.
##
## [param on]: true for the cube, false for the sphere.
func set_cubic(on: bool) -> void:
	_cubic = on
	if _sun_point != null:
		_place_solar_lunar_points(Solar.now())
	_cube.visible = on
	_noon_line.visible = not on
	for n in [_earth_mesh, _sea_mesh, _cities_node, _quakes_node, _grid_node, _sites_node, _pois_node, _regions_node]:
		n.visible = not on
	if not on:
		_sea_mesh.visible = _sea_file != ""

## Builds grid lines as flat ribbons lying on the globe, so they have a real width (GPU lines are one pixel). They are
## unshaded, two-sided and cast no shadow.
##
## [param points_list]: an Array of polylines, each an Array of Vector3 points.
## [param color]: the line color.
## [param dashed]: true to draw every other group of three segments.
## [param width]: the ribbon width in scene units.
## Returns: the MeshInstance3D.
func _line_mesh(points_list: Array, color: Color, dashed: bool = false, width: float = 0.045) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for pts in points_list:
		for i in range(pts.size() - 1):
			if dashed and (i / 3) % 2 == 1:
				continue
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var side := a.normalized().cross(b - a).normalized() * (width * 0.5)
			var base := verts.size()
			verts.append_array([a - side, a + side, b - side, b + side])
			idx.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	if verts.size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # grid lines never cast shadows
	return mi

## Points of a circle of latitude, for the grid.
##
## [param lat]: latitude in degrees.
## [param radius]: distance from the Earth's center.
## [param steps]: number of segments (default 180).
## Returns: an Array of steps + 1 Vector3 points.
func _latitude_circle(lat: float, radius: float, steps: int = 180) -> Array:
	var pts: Array = []
	for i in range(steps + 1):
		pts.append(Geo.to_vec3(lat, -180.0 + 360.0 * i / steps, radius))
	return pts

## Points of a meridian from pole to pole, for the grid.
##
## [param lon]: longitude in degrees.
## [param radius]: distance from the Earth's center.
## [param steps]: number of segments (default 90).
## Returns: an Array of steps + 1 Vector3 points.
func _meridian(lon: float, radius: float, steps: int = 90) -> Array:
	var pts: Array = []
	for i in range(steps + 1):
		pts.append(Geo.to_vec3(-90.0 + 180.0 * i / steps, lon, radius))
	return pts

## Rebuilds the grid: the major latitude circles (equator, tropics, polar circles) and the 15 degree meridians, each
## as the settings allow, in the `color_grid` color, just above the surface (enough to avoid z-fighting). Nothing is
## drawn when `show_grid` is off.
func _rebuild_grid() -> void:
	_clear(_grid_node)
	_noon_line.mesh = null
	if not Settings.get_bool("show_grid"):
		return
	var lr := R + 0.03   # flush with the surface (just enough to avoid z-fighting)
	var major: Array = []
	if Settings.get_bool("show_equator"):
		major.append(_latitude_circle(0.0, lr))
	if Settings.get_bool("show_tropics"):
		major.append(_latitude_circle(23.4367, lr))
		major.append(_latitude_circle(-23.4367, lr))
	if Settings.get_bool("show_polar_circles"):
		major.append(_latitude_circle(66.5633, lr))
		major.append(_latitude_circle(-66.5633, lr))
	if major.size() > 0:
		_grid_node.add_child(_line_mesh(major, Settings.get_color("color_grid")))
	if Settings.get_bool("show_minor_grid"):
		var minor: Array = []
		for k in range(-11, 13):   # every 15°, including 0° and 180°
			minor.append(_meridian(15.0 * k, lr, 180))
		_grid_node.add_child(_line_mesh(minor, Settings.get_color("color_grid"), false, 0.045))

## Builds one hour label: extruded heavy-font text bent round the globe, in a glossy material (a polished body under a
## clear coat). The Sun, fixed behind the camera, must be what lights the label, so the material stays only slightly
## metallic. Its opacity follows [member _hour_alpha].
##
## [param text]: the label text.
## [param size]: size factor (1.0 normal).
## [param radius]: the sphere the text is bent round (default 11.5, [constant HOUR_RADIUS]).
## Returns: the MeshInstance3D.
func _hour_mesh(text: String, size: float, radius: float = 11.5) -> MeshInstance3D:
	var tm := TextMesh.new()
	tm.text = text
	tm.font = Geo.heavy_font()
	tm.font_size = 96
	tm.pixel_size = 0.0125 * size
	tm.depth = 0.35 * size
	tm.curve_step = 0.5
	var mi := MeshInstance3D.new()
	mi.mesh = Shapes.bend_text(tm, radius)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Settings.get_color("color_hours")
	# Glossy: a polished body under a clear coat. The sun (fixed behind the camera) must be what
	# lights and highlights the labels, so metallic stays low; a high value would make the fixed
	# studio sky in the environment dominate, which lit the labels from the side instead.
	mat.metallic = 0.2
	mat.metallic_specular = 0.8
	mat.roughness = 0.18
	mat.clearcoat_enabled = true
	mat.clearcoat = 1.0
	mat.clearcoat_roughness = 0.05
	mat.emission_enabled = true
	mat.emission = Settings.get_color("color_hours") * 0.08
	_apply_alpha_to_hour_material(mat, _hour_alpha)
	mi.material_override = mat
	return mi

## The opacity of the hour labels at a camera distance: fully opaque far away, fading to [constant HOUR_MIN_ALPHA] as
## the camera moves in, so they do not block the surface.
##
## [param distance]: camera distance from the Earth's center.
## Returns: 0 to 1.
func _hour_alpha_for_distance(distance: float) -> float:
	var t := smoothstep(HOUR_FADE_END_DISTANCE, HOUR_FADE_START_DISTANCE, distance)
	return lerpf(HOUR_MIN_ALPHA, 1.0, t)

## Sets a label material's opacity. Alpha blending is only switched on while the label is actually see-through, so
## fully opaque labels keep the cheaper opaque rendering and sorting.
##
## [param mat]: the label's material.
## [param alpha]: 0 to 1.
func _apply_alpha_to_hour_material(mat: StandardMaterial3D, alpha: float) -> void:
	var c := mat.albedo_color
	c.a = alpha
	mat.albedo_color = c
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if alpha < 0.999 else BaseMaterial3D.TRANSPARENCY_DISABLED

## Updates all the hour labels' opacity for the current camera: 1 (fully opaque) in flight, otherwise from the
## camera's distance ([method _hour_alpha_for_distance]). Does nothing if it has not changed.
func _update_hour_alpha() -> void:
	var a := 1.0 if _cam_mode == CamMode.FLIGHT else _hour_alpha_for_distance(_distance if _cam_mode == CamMode.ORBIT else _camera.global_position.length())
	if is_equal_approx(a, _hour_alpha) or _hours_earth == null or _hours_fixed == null:
		return
	_hour_alpha = a
	for parent in [_hours_earth, _hours_fixed]:
		for mi in parent.get_children():
			if mi is MeshInstance3D and mi.material_override is StandardMaterial3D:
				_apply_alpha_to_hour_material(mi.material_override, a)

## Rebuilds all 24 hour labels from the `hour_type` setting (none, relative to noon, solar, wall clock or relative to
## home). Used when the setting, the home location or the label color changes. The minute-by-minute change of
## wall-clock labels does not use this; see [method _renew_next_hour].
func _rebuild_hours() -> void:
	_clear(_hours_earth)
	_clear(_hours_fixed)
	_hour_items.clear()
	_hours_stale = 0
	if Settings.get_string("hour_type") == Settings.HOURS_NONE:
		return
	var utc := Solar.now()
	for k in range(-12, 12):
		var label := _make_hour_label(k, utc)
		(label["parent"] as Node3D).add_child(label["node"])
		_hour_items.append(label)

## Makes one hour label: its text for the current style, placed on the equator at its meridian, reading along the
## meridian from top to bottom as in Flatland, on the day or night layer. Fixed labels sit in the Sun's frame (the Sun
## is at longitude 0); wall-clock and home labels turn with the Earth.
##
## [param k]: which label, -12 to 11 (the 15 degree step from the Sun's, or the home, meridian).
## [param utc]: the time, Unix seconds.
## Returns: {"node": the label, "parent": the node to add it to}.
func _make_hour_label(k: int, utc: float) -> Dictionary:
	var kind := Settings.get_string("hour_type")
	var utc_hours := fposmod(utc, 86400.0) / 3600.0
	var text := ""
	var parent: Node3D = _hours_fixed
	var lon := 15.0 * k
	match kind:
		Settings.HOURS_NOON:
			text = "+0" if k == 0 else ("%+d" % k).replace("-", "−")
		Settings.HOURS_SOLAR:
			text = "%02d:00" % int(posmod(12 + k, 24))
		Settings.HOURS_WALL:
			# Meridians turn with the Earth; each shows the wall-clock time there.
			parent = _hours_earth
			var h := fposmod(utc_hours + lon / 15.0, 24.0)
			text = "%d:%02d" % [int(h), int((h - floor(h)) * 60.0)]
		Settings.HOURS_LOCATION:
			parent = _hours_earth
			var home_lon := Settings.get_float("home_longitude")
			lon = wrapf(home_lon + 15.0 * k, -180.0, 180.0)
			text = "Home" if k == 0 else ("%+d" % k).replace("-", "−")
	var mi := _hour_mesh(text, 1.0)
	var basis := Geo.surface_basis(0.0, lon)
	# Text reads along the meridian (top to bottom), as in Flatland.
	basis = basis * Basis(Vector3.BACK, deg_to_rad(-90.0))
	mi.transform = Transform3D(basis, Geo.to_vec3(0.0, lon, HOUR_RADIUS))
	# Fixed labels sit in the sun's frame (the sun is at longitude 0); wall-clock and home labels turn with the Earth.
	var label_night := not Solar.is_daylight(0.0, lon, utc) if parent == _hours_earth else absf(wrapf(lon, -180.0, 180.0)) > 90.0
	_set_night_layer(mi, label_night)
	return {"node": mi, "parent": parent}

## Renews the wall-clock labels after the minute changes, one per frame (called every frame; does nothing when none
## are stale). Making all 24 3D labels at once froze the view for about half a second. The old label is replaced by
## the new one in the same frame. See [member _hours_stale].
func _renew_next_hour() -> void:
	if _hours_stale <= 0:
		return
	var index := 24 - _hours_stale
	_hours_stale -= 1
	if index >= _hour_items.size():
		_hours_stale = 0
		return
	var old: Dictionary = _hour_items[index]
	var fresh := _make_hour_label(index - 12, Solar.now())
	if is_instance_valid(old["node"]):
		(old["node"] as Node).queue_free()
	(fresh["parent"] as Node3D).add_child(fresh["node"])
	_hour_items[index] = fresh

## Throws every quake away and builds them again. Only for a change that affects how all of them look (shape, size,
## filters, the enabled switch); a feed update goes through [method _sync_quakes], which touches only the quakes that
## came or went. The shapes are those of Flatland's EarthquakeShapes: animated or static arrow, sphere, pulsating
## sphere, pyramid, cone, box, cylinder, capsule or tethered magnitude; each has its magnitude written on the surface,
## and quakes inside the "recent" window get the chosen new-earthquake indicator (except with tethered magnitude, which has its
## own spinning bright red spheres).
func _rebuild_quakes() -> void:
	_clear(_quakes_node)
	_dn_items = _dn_items.filter(func(i): return not (is_instance_valid(i["node"]) and i["node"].get_parent() != null and _quakes_node.is_ancestor_of(i["node"])))
	_arrows.clear()
	_quake_nodes.clear()
	_sync_quakes()

## Brings the drawn quakes in line with the quake list: builds the ones that are new, removes the ones no longer
## shown, and adds or removes the "new quake" indicator as a quake becomes recent or stops being so. Nothing else is
## rebuilt, so a feed update does not cost a pause.
func _sync_quakes() -> void:
	var wanted: Dictionary = {}
	if Settings.get_bool("enable_earthquakes"):
		for q in QuakeService.map_quakes():
			wanted[_quake_key(q)] = q
	for id in _quake_nodes.keys():
		if not wanted.has(id):
			_remove_quake(id)
	var now := Time.get_unix_time_from_system()
	# The tethered magnitude shape marks new quakes with its own spinning bright red spheres, so it gets no "new quake" indicator
	# (the expanding ring and the others) as well.
	var highlight := Settings.get_bool("quake_highlight_new") and Settings.get_string("quake_shape") != "Tethered Magnitude"
	for id in wanted:
		var q: Dictionary = wanted[id]
		if not _quake_nodes.has(id):
			_quake_nodes[id] = {"group": _build_quake(q), "indicator": null}
		var entry: Dictionary = _quake_nodes[id]
		var recent := highlight and QuakeService.is_new(q, now)
		if recent and entry["indicator"] == null:
			var holder := Node3D.new()
			(entry["group"] as Node3D).add_child(holder)
			_indicator_parent = holder
			_add_quake_indicator(q)
			entry["indicator"] = holder
		elif not recent and entry["indicator"] != null:
			_discard_nodes(entry["indicator"])
			entry["indicator"] = null

## The key a drawn quake is filed under in [member _quake_nodes]: its id, plus the size of its group, so a quake is drawn
## again (with its count) when its group gains or loses a member.
##
## [param q]: the quake Dictionary (from [method QuakeService.map_quakes]).
## Returns: the key.
func _quake_key(q: Dictionary) -> String:
	return "%s#%d" % [q["id"], int(q.get("group_count", 1))]

## Builds everything for one earthquake: the shape ([method _make_quake_shape]) and its magnitude written on the
## surface ("M6.4", except for tethered magnitude), colored by magnitude. The nodes are grouped under one Node3D so the quake can be removed in one
## go ([method _remove_quake]).
##
## [param q]: the quake Dictionary.
## Returns: the group node (already added to the earthquake parent).
func _build_quake(q: Dictionary) -> Node3D:
	var group := Node3D.new()
	_quakes_node.add_child(group)
	var mag: float = q["magnitude"]
	var lat: float = q["lat"]
	var lon: float = q["lon"]
	var col := QuakeService.magnitude_color(mag)
	var holder := _make_quake_shape(q, col)
	if holder != null:
		group.add_child(holder)
	# Magnitude text lying on the surface (not for tethered magnitude, whose disc already shows the magnitude).
	if Settings.get_string("quake_shape") == "Tethered Magnitude":
		return group
	var s := "%.2f" % mag
	if s.ends_with("0"):
		s = s.left(-1)
	if int(q.get("group_count", 1)) > 1:
		s += " (%d)" % int(q["group_count"])      # a group of quakes: how many it stands for
	var em := 0.05 * (7.0 + mag)
	var radial := R + 0.3 + (mag / 10.0) * 0.7
	var t := _flat_text("M" + s, lat, lon, radial, em, 0.15, true, Geo.quake_font())
	Shapes.add_text_border(t, mag, em, "g|M%s|%.4f|%.4f" % [s, em, radial])
	group.add_child(t)
	_register_dn(t, lat, lon, col, col)
	return group

## Removes one quake's nodes and forgets it.
##
## [param id]: the quake's id (a key of [member _quake_nodes]).
func _remove_quake(id: String) -> void:
	_discard_nodes(_quake_nodes[id]["group"])
	_quake_nodes.erase(id)

## Frees a node and forgets the day/night and spinning-arrow entries that point into it.
##
## [param node]: the node to free.
func _discard_nodes(node: Node3D) -> void:
	_dn_items = _dn_items.filter(func(i): return is_instance_valid(i["node"]) and not node.is_ancestor_of(i["node"]))
	_arrows = _arrows.filter(func(i): return is_instance_valid(i["node"]) and not node.is_ancestor_of(i["node"]))
	node.queue_free()

## A rotation that stands a shape upright on the surface at a place (its local +Y points away from the globe).
##
## [param lat]: latitude.
## [param lon]: longitude.
## Returns: the Basis.
func _quake_basis(lat: float, lon: float) -> Basis:
	var b := Geo.surface_basis(lat, lon)
	return Basis(b.x, b.z, b.x.cross(b.z))

## Builds the 3D shape for a quake from the `quake_shape` setting: animated or static arrow, sphere, pulsating sphere,
## pyramid, cone, box, cylinder, capsule or tethered magnitude. Sizes depend on the magnitude and the `quake_scale`
## setting; animations (bounce, pulse) are looping tweens that stop when the node is freed. Animated shapes also
## register for day/night changes.
##
## [param q]: the quake Dictionary.
## [param col]: the color for its magnitude.
## Returns: the shape's holder node, or null for an unknown shape.
func _make_quake_shape(q: Dictionary, col: Color) -> Node3D:
	var mag: float = q["magnitude"]
	var lat: float = q["lat"]
	var lon: float = q["lon"]
	var mult := Shapes.scale_for("quake_scale")
	var shape := Settings.get_string("quake_shape")
	var plain := Shapes.plain(col)
	match shape:
		"Animated Arrow", "Static Arrow":
			var animated := shape == "Animated Arrow"
			var arrow_scale := (0.75 if animated else 0.74) * mult
			# Animated arrows bounce with the tip touching the surface at the bottom of the bounce
			# (never below it); static arrows hover as in Flatland.
			var holder := _up_node(lat, lon, R + (0.667 * arrow_scale if animated else 0.7))
			var arrow := Node3D.new()
			arrow.scale = Vector3.ONE * arrow_scale
			holder.add_child(arrow)
			var head := PrismMesh.new()
			head.size = Vector3(0.85, 0.667, 0.2)
			var head_mi := MeshInstance3D.new()
			head_mi.mesh = head
			head_mi.rotation_degrees = Vector3(0, 0, 180)     # apex toward the surface
			head_mi.position = Vector3(0, -0.333, 0)
			arrow.add_child(head_mi)
			var stem := BoxMesh.new()
			stem.size = Vector3(0.2125, 1.0, 0.2)
			var stem_mi := MeshInstance3D.new()
			stem_mi.mesh = stem
			stem_mi.position = Vector3(0, 0.5, 0)
			arrow.add_child(stem_mi)
			# The stem is as deep as the head, so the head's top edges run along the stem's base: no line there.
			Shapes.add_quake_border(head_mi, mag, false, AABB(Vector3(-0.1075, -0.35, -0.101), Vector3(0.215, 0.04, 0.202)))
			Shapes.add_quake_border(stem_mi, mag, true)
			if animated:
				_register_dn(head_mi, lat, lon, col, col)
				_register_dn(stem_mi, lat, lon, col, col)
				_arrows.append({"node": arrow, "dir": 1.0 if lat >= 0.0 else -1.0})
				# Bounce toward the surface and back; faster for bigger quakes.
				var d := maxf(0.2, (10.0 - mag) / 5.00000543)
				arrow.position.y = 0.5
				var tw := arrow.create_tween().set_loops()
				tw.tween_property(arrow, "position:y", 0.0, d).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				tw.tween_property(arrow, "position:y", 0.5, d).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			else:
				head_mi.material_override = plain
				stem_mi.material_override = plain
			return holder
		"Sphere", "Pulsating Sphere":
			var pulsing := shape == "Pulsating Sphere"
			# A plain sphere rests on the surface; a pulsating one is centered on it and swells from there.
			var holder := _up_node(lat, lon, R if pulsing else R + 0.5)
			var sph := SphereMesh.new()
			var r := mag * 0.5 * (0.12 if pulsing else 0.1)
			sph.radius = r
			sph.height = r * 2.0
			var mi := MeshInstance3D.new()
			mi.mesh = sph
			mi.material_override = Shapes.plain(Color(col, 0.6)) if pulsing else plain
			holder.add_child(mi)
			if not pulsing:      # the translucent pulsating sphere would show its border through itself
				Shapes.add_quake_border(mi, mag)
			holder.scale = Vector3.ONE * (0.749 if pulsing else 0.9993) * mult
			if pulsing:
				var d := 0.7 + (10.0 - mag) * 0.05
				var tw := mi.create_tween().set_loops()
				tw.tween_property(mi, "scale", Vector3.ONE * 1.5, d)
				tw.tween_property(mi, "scale", Vector3.ONE, d)
			return holder
		"Pyramid":
			var holder := _up_node(lat, lon, R)
			holder.scale = Vector3.ONE * 1.001 * mult
			var mi := MeshInstance3D.new()
			mi.mesh = Shapes.pyramid_mesh(0.5, 2.5, 0.5)
			mi.material_override = plain
			holder.add_child(mi)
			Shapes.add_quake_border(mi, mag)
			return holder
		"Cone", "Box", "Cylinder", "Capsule":
			var holder := _up_node(lat, lon, R + 0.5)
			var mi := MeshInstance3D.new()
			match shape:
				"Cone":
					var cm := CylinderMesh.new()
					cm.top_radius = 0.0
					cm.bottom_radius = 0.5
					cm.height = 3.5
					mi.mesh = cm
					holder.scale = Vector3.ONE * 1.002 * mult
				"Box":
					var bm := BoxMesh.new()
					bm.size = Vector3(0.5, 2.5, 0.5)
					mi.mesh = bm
					holder.scale = Vector3.ONE * 0.99999 * mult
				"Cylinder":
					var cm := CylinderMesh.new()
					cm.top_radius = 0.25
					cm.bottom_radius = 0.25
					cm.height = 2.5
					mi.mesh = cm
					holder.scale = Vector3.ONE * 0.9998 * mult
				_:
					var cp := CapsuleMesh.new()
					cp.radius = 0.25
					cp.height = 2.5
					mi.mesh = cp
					holder.scale = Vector3.ONE * 1.0003 * mult
			mi.material_override = plain
			holder.add_child(mi)
			Shapes.add_quake_border(mi, mag)
			return holder
		"Tethered Magnitude":
			return _tethered_quake(q, col, mult)
	return null

## Builds the "Tethered Magnitude" shape (Flatland's TetheredNumber): a pole topped with a translucent disc bearing
## the magnitude ("M5.8", or "M5.8 (3)" for a group of three quakes). Recent quakes also get a spinning rim of bright red spheres.
##
## [param q]: the quake Dictionary.
## [param col]: its color.
## [param mult]: the overall size factor from the `quake_scale` setting.
## Returns: the holder node.
func _tethered_quake(q: Dictionary, col: Color, mult: float) -> Node3D:
	var lat: float = q["lat"]
	var lon: float = q["lon"]
	var local := float(q["magnitude"]) / 10.0
	var holder := _up_node(lat, lon, R)
	holder.scale = Vector3.ONE * mult
	var height := 2.5 * local
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = local * 0.1002
	pm.bottom_radius = local * 0.1002
	pm.height = height
	pole.mesh = pm
	pole.position = Vector3(0, height * 0.5, 0)
	holder.add_child(pole)
	_register_dn(pole, lat, lon, col, col)
	var disc_r := 2.01 * local
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = disc_r
	dm.bottom_radius = disc_r
	dm.height = 0.1
	disc.mesh = dm
	disc.material_override = Shapes.plain(Color(col, 0.6))
	disc.position = Vector3(0, height, 0)
	holder.add_child(disc)
	var tm := TextMesh.new()
	tm.text = "M%.1f" % q["magnitude"]
	if int(q.get("group_count", 1)) > 1:
		tm.text += " (%d)" % int(q["group_count"])      # a group of quakes: how many it stands for
	tm.font = Geo.label_font(900)
	tm.font_size = 64
	tm.pixel_size = (0.6 + 0.3 * local) / 64.0
	tm.depth = 0.05
	# The longer text must still fit on the disc: shrink it if it is wider than 85 percent of the disc's width.
	var text_width := tm.get_aabb().size.x
	if text_width > 1.7 * disc_r:
		tm.pixel_size *= 1.7 * disc_r / text_width
	var txt := MeshInstance3D.new()
	txt.mesh = tm
	txt.material_override = Shapes.plain(Color.BLACK)
	txt.rotation_degrees = Vector3(-90, 0, 0)
	txt.position = Vector3(0, height + 0.09, 0)
	holder.add_child(txt)
	var rim_r := disc_r + 0.101
	var rim := MeshInstance3D.new()
	var tr := TorusMesh.new()
	tr.inner_radius = rim_r - 0.101
	tr.outer_radius = rim_r + 0.101
	rim.mesh = tr
	rim.material_override = plain_for_rim(col)
	rim.position = Vector3(0, height, 0)
	holder.add_child(rim)
	if QuakeService.is_new(q):
		var sphere := SphereMesh.new()
		sphere.radius = 0.215
		sphere.height = 0.43
		for a in range(0, 360, 45):
			var sp := MeshInstance3D.new()
			sp.mesh = sphere
			sp.material_override = Shapes.plain(Color("#ff0000"))
			sp.position = Vector3(rim_r * cos(deg_to_rad(a)), 0, rim_r * sin(deg_to_rad(a)))
			rim.add_child(sp)
		var speed := maxf(0.09994492, 5.0 * (1.0 - local))
		var tw := rim.create_tween().set_loops()
		tw.tween_property(rim, "rotation:y", PI, speed).as_relative()
	return holder

## The material for the rim of a tethered quake's disc.
##
## [param col]: the quake's color.
## Returns: a plain material of that color ([method Shapes.plain]).
func plain_for_rim(col: Color) -> StandardMaterial3D:
	return Shapes.plain(col)

## Adds the "new earthquake" indicator chosen in the `quake_indicator` setting (Flatland's EarthquakeIndicators) to
## [member _indicator_parent]: a static or animated ring, arrow and ring, radiating rings, glowing sphere, or a ring
## of triangles moving inward or outward. Animation speed depends on the magnitude (bigger quakes animate faster).
## Does nothing for "None".
##
## [param q]: the quake Dictionary.
func _add_quake_indicator(q: Dictionary) -> void:
	var kind := Settings.get_string("quake_indicator")
	if kind == "None":
		return
	var mag: float = q["magnitude"]
	var lat: float = q["lat"]
	var lon: float = q["lon"]
	var fade := 1.0 - mag / 10.0
	var ring := TorusMesh.new()
	ring.inner_radius = 0.8
	ring.outer_radius = 1.0
	match kind:
		"Static Ring", "Animated Ring":
			var holder := _up_node(lat, lon, R + 0.3)
			_indicator_parent.add_child(holder)
			var mi := MeshInstance3D.new()
			mi.mesh = ring
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(mi)
			if kind == "Static Ring":
				mi.material_override = Shapes.plain(Color("#ff2400"))
			else:
				mi.material_override = Shapes.plain(Color("#ffa080"))
				var dur := 1.0 + fade
				var tw := mi.create_tween().set_loops()
				tw.tween_property(mi, "scale", Vector3.ONE * (1.2 + 0.3 * fade), dur)
				tw.tween_property(mi, "scale", Vector3.ONE, dur)
		"Arrow and Ring":
			_add_arrow_and_ring(lat, lon, mag)
		"Radiating Rings":
			var rr := TorusMesh.new()
			rr.inner_radius = 0.75
			rr.outer_radius = 1.05
			var holder := _up_node(lat, lon, R + 0.02)
			_indicator_parent.add_child(holder)
			var mi := MeshInstance3D.new()
			mi.mesh = rr
			var rmat := StandardMaterial3D.new()
			rmat.albedo_color = Color(1.0, 0.627, 0.5, 0.8)
			rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			rmat.emission_enabled = true
			rmat.emission = Color("#ffa080") * 0.6
			mi.material_override = rmat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(mi)
			var dur := 1.0 + fade
			var to_scale := 1.0 + 0.3 * fade
			var rt := mi.create_tween().set_loops()
			rt.tween_callback(func() -> void:
				mi.scale = Vector3.ONE * 0.1
				rmat.albedo_color.a = 0.8)
			rt.tween_property(mi, "scale", Vector3.ONE * to_scale, dur)
			rt.parallel().tween_property(rmat, "albedo_color:a", 0.0, 0.1).set_delay(dur - 0.1)
		"Glowing Sphere":
			var holder := _up_node(lat, lon, R)
			_indicator_parent.add_child(holder)
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.75
			sm.height = 1.5
			mi.mesh = sm
			mi.material_override = Shapes.plain(Color(1.0, 0.14, 0.0, 0.45))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(mi)
		"Triangle Ring Inward", "Triangle Ring Outward":
			var holder := _up_node(lat, lon, R + 0.3)
			holder.scale = Vector3.ONE * 0.41
			_indicator_parent.add_child(holder)
			var spin := Node3D.new()
			holder.add_child(spin)
			var tri := PrismMesh.new()
			tri.size = Vector3(0.6, 0.8, 0.15)
			var out := kind == "Triangle Ring Outward"
			for i in range(13):
				var a := TAU * i / 13.0
				var mi := MeshInstance3D.new()
				mi.mesh = tri
				mi.material_override = Shapes.plain(Color("#ff2400"))
				# Prism apex points +Y; lay it flat (tangent plane) pointing out or in along the ring.
				mi.position = Vector3(1.2 * cos(a), 0, 1.2 * sin(a))
				mi.basis = Basis(Vector3.UP, -a) * Basis(Vector3.BACK, deg_to_rad(-90.0 if out else 90.0)) * Basis(Vector3.RIGHT, deg_to_rad(90))
				spin.add_child(mi)
			var tw := spin.create_tween().set_loops()
			tw.tween_property(spin, "rotation:y", TAU, 10.0 - mag + 2.0).as_relative()

## Adds the "Arrow and Ring" indicator, which does not animate: an arrow points down at the spot and a ring lies on
## the surface around it. The arrow's size and height above the surface, and the ring's radius, all grow in proportion
## to the magnitude.
##
## [param lat]: latitude.
## [param lon]: longitude.
## [param mag]: the magnitude.
func _add_arrow_and_ring(lat: float, lon: float, mag: float) -> void:
	var holder := _up_node(lat, lon, R + 0.02)
	_indicator_parent.add_child(holder)
	var plain := Shapes.plain(Color("#ff2400"))
	var ring_mesh := TorusMesh.new()
	ring_mesh.outer_radius = 0.2 * mag
	ring_mesh.inner_radius = 0.2 * mag * 0.8
	var ring := MeshInstance3D.new()
	ring.mesh = ring_mesh
	ring.material_override = plain
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(ring)
	var k := 0.15 * mag                        # arrow size
	var arrow := Node3D.new()
	arrow.scale = Vector3.ONE * k
	arrow.position.y = 0.1 * mag + 0.667 * k   # the tip hovers this high above the surface
	holder.add_child(arrow)
	var head := PrismMesh.new()
	head.size = Vector3(0.85, 0.667, 0.2)
	var head_mi := MeshInstance3D.new()
	head_mi.mesh = head
	head_mi.rotation_degrees = Vector3(0, 0, 180)     # apex toward the surface
	head_mi.position = Vector3(0, -0.333, 0)
	head_mi.material_override = plain
	head_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arrow.add_child(head_mi)
	var stem := BoxMesh.new()
	stem.size = Vector3(0.2125, 1.0, 0.2)
	var stem_mi := MeshInstance3D.new()
	stem_mi.mesh = stem
	stem_mi.position = Vector3(0, 0.5, 0)
	stem_mi.material_override = plain
	stem_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arrow.add_child(stem_mi)

# MARK: - Time

## Every frame while drawing: re-fits the camera if the view was resized, moves the stars with the camera, updates the
## satellites, steps the camera flight, spins the earthquake arrows and pole shafts, renews one wall-clock hour label
## if any are stale, turns the Earth (attract mode, or easing to the clock's angle), counts the once-a-second
## [method _update_time], and updates the hover. Does nothing while a native dialog covers the window or the app is in
## the background on a phone.
##
## [param delta]: seconds since the last frame.
func _process(delta: float) -> void:
	if not PowerManager.drawing():
		return   # a sheet covers the screen or the app is in the background: nobody sees the globe
	var vs := get_viewport().get_visible_rect().size
	if vs != _vp_size:
		_vp_size = vs
		_apply_camera()
	_place_stars()
	_update_satellites()
	if _cam_mode == CamMode.FLIGHT:
		_step_flight(delta)
		_apply_camera()
	for a in _arrows:
		if is_instance_valid(a["node"]):
			(a["node"] as Node3D).rotation.y += a["dir"] * delta     # about 1 radian per second
	if _pole_shafts.size() == 2:
		(_pole_shafts[0] as Node3D).rotation.y += delta * deg_to_rad(225.0 / 4.59)
		(_pole_shafts[1] as Node3D).rotation.y -= delta * deg_to_rad(225.0 / 4.59)
	_renew_next_hour()
	_tick += delta
	if Settings.get_bool("attract_mode"):
		_attract_angle += delta * TAU / 40.0
		_earth.rotation.y = _attract_angle
	else:
		# Smoothly follow the clock (Flatland animates the rotation over about a second).
		_earth.rotation.y = lerp_angle(_earth.rotation.y, _earth_angle, clampf(delta * 6.0, 0.0, 1.0))
	if _tick >= 1.0:
		_tick = 0.0
		_update_time(false)
	_update_hover()

## Brings the scene to the current time (called once a second, when the debugger's clock changes, and at start-up).
## Turns the Earth so the sub-solar longitude faces the Sun, tilts the Earth system by the Sun's declination (the
## seasons), turns the star frame to the date, places the Moon and the Sun/Moon balls, gives the Earth and cube
## shaders the Sun direction (the Sun is fixed at +Z) and night level, places the two directional lights, and once a
## minute refreshes the day/night materials and flags the wall-clock hour labels to be renewed.
##
## [param snap]: true to jump the Earth to its angle at once; false to let it ease there.
func _update_time(snap: bool) -> void:
	var now := Solar.now()
	var sub_lon := Solar.subsolar_longitude(now)
	_earth_angle = -deg_to_rad(sub_lon)
	if snap:
		_earth.rotation.y = _earth_angle
	var decl := deg_to_rad(Solar.declination(now))
	if _stars_node != null:
		# Star frame -> scene: spin so the sun's right ascension faces +Z, then apply the seasonal tilt.
		_stars_basis = Basis(Vector3.RIGHT, decl) * Basis(Vector3.UP, -deg_to_rad(Solar.right_ascension(now)))
		_place_stars()
		_place_moon(now)
	_place_solar_lunar_points(now)
	_system.rotation.x = decl          # tilt the Earth; the sun stays fixed behind the camera
	var sun_dir := Vector3(0, 0, 1)
	var lit_mats: Array[ShaderMaterial] = [_earth_mat, _sea_mat]
	lit_mats.append_array(_cube_mats)
	for mat in lit_mats:
		mat.set_shader_parameter("sun_dir", sun_dir)
		mat.set_shader_parameter("night_level", 0.14 if Settings.get_bool("show_moon_light") else 0.04)
	_sun.position = sun_dir * 100.0
	_sun.look_at(Vector3.ZERO, Vector3.UP)
	_moon.position = -sun_dir * 100.0
	_moon.look_at(Vector3.ZERO, Vector3.UP)
	# The noon meridian is the half great circle facing the sun.
	_noon_line.rotation.y = 0.0
	var stamp := int(now / 60.0)
	if stamp != _last_hour_stamp:
		_last_hour_stamp = stamp
		_refresh_day_night()
		if Settings.get_string("hour_type") == Settings.HOURS_WALL:
			_hours_stale = 24      # the minutes have moved on: renew the labels one at a time (see _renew_next_hour)

# MARK: - Camera and interaction

## The Tween animating [method reset_view].
var _reset_tween: Tween

## Returns the camera to its default orientation (the double click and the Reset button): leaves any special camera
##   mode, then turns, zooms and un-pans to the start view, taking the short way round in yaw.
##
## [param animate]: true (default) to animate over one second, false to jump.
func reset_view(animate: bool = true) -> void:
	_leave_special_mode()
	if _reset_tween != null and _reset_tween.is_valid():
		_reset_tween.kill()
	if not animate:
		_yaw = 0.0
		_pitch = 0.0
		_distance = DEFAULT_DISTANCE
		_pan = Vector2.ZERO
		_apply_camera()
		return
	# Take the short way round to yaw 0.
	_yaw = wrapf(_yaw, -PI, PI)
	var y0 := _yaw
	var p0 := _pitch
	var d0 := _distance
	var pan0 := _pan
	_reset_tween = create_tween()
	_reset_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_reset_tween.tween_method(func(t: float) -> void:
		_yaw = lerpf(y0, 0.0, t)
		_pitch = lerpf(p0, 0.0, t)
		_distance = lerpf(d0, DEFAULT_DISTANCE, t)
		_pan = pan0.lerp(Vector2.ZERO, t)
		_apply_camera(), 0.0, 1.0, 1.0)

## Places the camera for the current mode and updates everything that depends on it. In orbit mode it sets the pivot
## rotation, keeps the whole globe in view whatever the window shape, and sets a depth range tight around the globe
## (so shadows stay sharp), reaching out to the Moon and the satellites when they are shown. In the special modes
## [method _apply_special_camera] does it. Then it sets the Sun's shadow distance, the hour label opacity and the star
## sphere size.
func _apply_camera() -> void:
	var cam_z: float
	if _cam_mode == CamMode.ORBIT:
		_orbit.rotation = Vector3(_pitch, _yaw, 0.0)
		_camera.fov = CAMERA_FOV
		_camera.basis = Basis.IDENTITY     # the special modes aim the camera itself; the orbit does the aiming here
		# Keep the whole globe in view whatever the window shape: fit the narrower dimension.
		var vs0 := get_viewport().get_visible_rect().size
		var fit := 1.0
		if vs0.y > 0.0:
			fit = maxf(1.0, 0.95 / (vs0.x / vs0.y))
		cam_z = _distance * fit
		_camera.position = Vector3(_pan.x, _pan.y, cam_z)
		# Keep the depth range tight around the globe so shadows stay sharp at this distance.
		# With satellites on, leave room for the geostationary ring, which is well in front of and behind the globe.
		var extra := 60.0 if Settings.get_bool("show_satellites") else 0.0
		_camera.near = maxf(0.1, cam_z - 40.0 - extra)
		_camera.far = cam_z + 40.0 + extra
		if _moon_body != null and _moon_body.visible:
			# The Moon is far out (about 600 units): reach it, and leave the star field just beyond it.
			_camera.far = maxf(_camera.far, cam_z + _moon_distance + 20.0)
	else:
		cam_z = _apply_special_camera()
	var vs := get_viewport().get_visible_rect().size
	_sun.directional_shadow_max_distance = cam_z + 40.0
	_update_hour_alpha()
	if _sky_mesh != null:
		# Just inside the far plane, beyond everything in the scene.
		var r := _camera.far - 2.0
		_sky_mesh.scale = Vector3(r, r, r)
		_sky_radius = r * 0.99
		_pixel_angle = deg_to_rad(_camera.fov) / maxf(1.0, vs.y)
		_place_stars()

## The current camera mode.
##
## Returns: the [enum CamMode] as an int.
func camera_mode() -> int:
	return _cam_mode

## Moves the camera to a special vantage point, gliding there over a second (or back to orbiting with ORBIT).
## FROM_MOON and FROM_SUN follow the Moon (the Sun is fixed in this scene) so the Earth stays in view; LOOK_AT_MOON
## stands still and points at the Moon as it is now; FLIGHT starts the wandering flight ([method _start_flight]).
## Emits [signal camera_mode_changed].
##
## [param mode]: the wanted [enum CamMode].
func set_camera_mode(mode: int) -> void:
	if mode == CamMode.ORBIT:
		_leave_special_mode()
		return
	if _moon_body == null:
		return
	if _reset_tween != null and _reset_tween.is_valid():
		_reset_tween.kill()
	_blend_from = _camera.global_transform.orthonormalized()
	_blend_fov = _camera.fov
	if mode == CamMode.LOOK_AT_MOON:
		_look_from = _vantage_to_see_moon()
		_look_fov = 4.0
	if mode == CamMode.FLIGHT:
		_start_flight()
	_cam_mode = mode as CamMode
	_start_blend()
	camera_mode_changed.emit(mode)
	_apply_camera()

## Starts the one-second ease of [member _blend] from 0 to 1 that glides the camera to a new mode's position.
func _start_blend() -> void:
	if _blend_tween != null and _blend_tween.is_valid():
		_blend_tween.kill()
	_blend = 0.0
	_blend_tween = create_tween()
	_blend_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_blend_tween.tween_method(func(t: float) -> void:
		_blend = t
		_apply_camera(), 0.0, 1.0, 1.0)

## Where to stand to look at the Moon: where the camera is now if the Moon can be seen from there, otherwise the same
## distance from the Earth's center but on the Moon's side of the Earth.
##
## Returns: the camera position for LOOK_AT_MOON.
func _vantage_to_see_moon() -> Vector3:
	var here := _camera.global_position
	var moon := _moon_body.position
	if here.length() < R * 1.2:
		here = here.normalized() * R * 1.2 if here.length() > 0.001 else Vector3(0, 0, R * 1.2)
	# Closest approach of the line from here to the moon to the Earth's centre.
	var seg := moon - here
	var t := clampf(-here.dot(seg) / maxf(seg.length_squared(), 0.001), 0.0, 1.0)
	if (here + seg * t).length() >= R * 1.02:
		return here
	return moon.normalized() * here.length()

## Goes back to orbiting the Earth, starting from wherever the camera is now (its direction and distance become the
## orbit's yaw, pitch and distance). Does nothing in orbit mode. Emits [signal camera_mode_changed].
func _leave_special_mode() -> void:
	if _cam_mode == CamMode.ORBIT:
		return
	var p := _camera.global_position
	if p.length() < 0.001:
		p = Vector3(0, 0, DEFAULT_DISTANCE)
	var dir := p.normalized()
	_yaw = atan2(dir.x, dir.z)
	_pitch = clampf(-asin(clampf(dir.y, -1.0, 1.0)), -1.45, 1.45)
	_distance = clampf(p.length(), MIN_DISTANCE, MAX_DISTANCE)
	_pan = Vector2.ZERO
	_cam_mode = CamMode.ORBIT
	if _blend_tween != null and _blend_tween.is_valid():
		_blend_tween.kill()
	_blend = 1.0
	_apply_camera()
	camera_mode_changed.emit(CamMode.ORBIT)

## Starts the camera flight from where the camera is, heading along the surface at a random wandering altitude, speed,
## turn rate and view offsets (all [Wander] values).
func _start_flight() -> void:
	_fl_rng.randomize()
	var p := _camera.global_position
	_fl_dir = p.normalized() if p.length() > 0.001 else Vector3.BACK
	var fwd := -_camera.global_transform.basis.z
	fwd = fwd - _fl_dir * fwd.dot(_fl_dir)          # along the surface
	if fwd.length() < 0.05:
		fwd = _fl_dir.cross(Vector3.UP)
		if fwd.length() < 0.05:
			fwd = _fl_dir.cross(Vector3.RIGHT)
	_fl_tangent = fwd.normalized()
	var mid := (FLIGHT_MIN_RADIUS + FLIGHT_MAX_RADIUS) * 0.5
	_fl_altitude = Wander.new(_fl_rng, FLIGHT_MIN_RADIUS, FLIGHT_MAX_RADIUS, 25.0, 40.0, mid)
	_fl_speed = Wander.new(_fl_rng, 1.6, 3.6, 30.0, 45.0, 2.4)
	_fl_turn = Wander.new(_fl_rng, deg_to_rad(-3.5), deg_to_rad(3.5), 30.0, 45.0, 0.0)           # radians a second
	_fl_yaw = Wander.new(_fl_rng, -FLIGHT_YAW_LIMIT, FLIGHT_YAW_LIMIT, 25.0, 40.0, 0.0)
	_fl_pitch = Wander.new(_fl_rng, -FLIGHT_PITCH_LIMIT, FLIGHT_PITCH_LIMIT, 25.0, 40.0, 0.0)
	_fl_pos = _fl_dir * mid
	_fl_forward = _fl_tangent
	_fl_obstacle_age = 99.0
	_fl_avoid = 0.0

## Rebuilds the list of things the flight must not fly through: visible satellites, quake markers and the pole tips.
## Called four times a second.
func _refresh_flight_obstacles() -> void:
	_fl_obstacles.clear()
	for item in _sat_items.values():
		var holder: Node3D = (item as Dictionary)["holder"]
		if is_instance_valid(holder) and holder.visible:
			_fl_obstacles.append(holder.global_position)
	for entry in _quake_nodes.values():
		var group: Node3D = (entry as Dictionary)["group"]
		if is_instance_valid(group) and group.visible:
			_fl_obstacles.append(group.global_position * 1.04)   # the markers stand a little way off the surface
	for pole in [-1.0, 1.0]:
		for h in [1.1, 1.25]:
			_fl_obstacles.append(_system.global_transform * Vector3(0, pole * R * h, 0))

## One step of the flight. The speed, course turn, altitude and the yaw and pitch of the view all follow slowly
## wandering values, so nothing jerks; anything near the path turns the course away from its side (the reaction eased
## in and out); the altitude stays inside the band around the hour labels; and the pitch is measured from the horizon
## so the Earth stays in the lower part of the view. The camera moves along a great circle and the view eases toward
## where it should look.
##
## [param delta]: seconds since the last frame (limited to 0.1).
func _step_flight(delta: float) -> void:
	delta = minf(delta, 0.1)
	_fl_obstacle_age += delta
	if _fl_obstacle_age > 0.25:
		_fl_obstacle_age = 0.0
		_refresh_flight_obstacles()
	var radius := clampf(_fl_altitude.step(delta), FLIGHT_MIN_RADIUS, FLIGHT_MAX_RADIUS)
	var speed: float = _fl_speed.step(delta)
	var turn: float = _fl_turn.step(delta)
	# Steer round anything ahead: it turns the course away from the side the thing is on.
	var right := _fl_tangent.cross(_fl_dir)
	var avoid := 0.0
	for o in _fl_obstacles:
		var rel := o - _fl_pos
		var d := rel.length()
		if d < FLIGHT_REACH and rel.dot(_fl_tangent) > -1.0:
			var side := 1.0 if rel.dot(right) >= 0.0 else -1.0
			avoid += side * 0.45 * (1.0 - d / FLIGHT_REACH)
	# The reaction is eased in and out, so the course never swings suddenly when something comes into range.
	_fl_avoid = lerpf(_fl_avoid, clampf(avoid, -0.35, 0.35), 1.0 - exp(-delta * 1.2))
	turn += _fl_avoid
	# Move along the surface (a great circle) and turn the course.
	var axis := _fl_dir.cross(_fl_tangent).normalized()
	var angle := speed * delta / radius
	_fl_dir = _fl_dir.rotated(axis, angle).normalized()
	_fl_tangent = _fl_tangent.rotated(axis, angle)
	_fl_tangent = (_fl_tangent - _fl_dir * _fl_tangent.dot(_fl_dir)).normalized()
	_fl_tangent = _fl_tangent.rotated(_fl_dir, turn * delta)
	_fl_pos = _fl_dir * radius
	for o in _fl_obstacles:
		var off := _fl_pos - o
		if off.length() < FLIGHT_CLEARANCE * 0.5 and off.length() > 0.001:
			_fl_pos = o + off.normalized() * FLIGHT_CLEARANCE * 0.5
	# The view looks along the course, turned a little to the side and tipped up or down. The pitch is measured from the
	# horizon (which dips further below level the higher the camera is), so the Earth stays in the lower part of the
	# view whatever the pitch offset.
	var yaw := deg_to_rad(_fl_yaw.step(delta))
	var pitch := deg_to_rad(_fl_pitch.step(delta)) - acos(R / radius) * 0.9
	var look := _fl_tangent.rotated(_fl_dir, yaw)
	look = look.rotated(look.cross(_fl_dir).normalized(), pitch)
	# Ease the view toward where it should look, so any small step in the target never shows as a jerk.
	_fl_forward = _fl_forward.slerp(look, 1.0 - exp(-delta * 3.0)).normalized()

## Positions the camera for the current special mode: at the Moon looking at the Earth, at the Sun's side looking at
## the Earth, at the look-from point looking at the Moon, or at the flight position looking along its view. Sets the
## field of view (the Earth fills about half the view from the Moon or Sun), depth range and, during the glide, blends
## from the starting transform.
##
## Returns: the camera's distance from the origin (used for the shadow distance).
func _apply_special_camera() -> float:
	var moon_pos := _moon_body.position
	var pos := Vector3.ZERO
	var target := Vector3.ZERO
	match _cam_mode:
		CamMode.FROM_MOON:
			pos = moon_pos
		CamMode.FROM_SUN:
			# The sun is a very long way off; it is drawn as far out as the moon, which gives the same view.
			pos = Vector3(0, 0, _moon_distance)
		CamMode.LOOK_AT_MOON:
			pos = _look_from
			target = moon_pos
		CamMode.FLIGHT:
			pos = _fl_pos
			target = _fl_pos + _fl_forward
	var dist := pos.distance_to(target)
	var fov := _look_fov
	if _cam_mode == CamMode.FLIGHT:
		fov = FLIGHT_FOV
	elif _cam_mode != CamMode.LOOK_AT_MOON:
		# Frame the Earth so it fills about half the height of the view.
		fov = clampf(rad_to_deg(2.0 * asin(minf(1.0, R / maxf(dist, R)))) / 0.5, 0.5, CAMERA_FOV)
	var forward := (target - pos).normalized()
	var up := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	if _cam_mode == CamMode.FLIGHT:
		up = pos.normalized()          # the horizon stays level: up is away from the Earth
	var xf := Transform3D(Basis.looking_at(forward, up), pos)
	_orbit.rotation = Vector3.ZERO
	var extra := 60.0 if Settings.get_bool("show_satellites") else 0.0
	var near_plane := 1.0
	var far_plane := dist + 60.0 + extra
	if _cam_mode == CamMode.FLIGHT:
		near_plane = 0.1
		far_plane = (_moon_distance + 100.0) if _moon_body.visible else 400.0
	elif _cam_mode != CamMode.LOOK_AT_MOON:
		near_plane = maxf(0.1, dist - 40.0 - extra)
		far_plane = dist + 40.0 + extra
	if _blend < 1.0:
		xf = _blend_from.interpolate_with(xf, _blend)
		fov = lerpf(_blend_fov, fov, _blend)
		near_plane = 0.5
		far_plane = maxf(far_plane, _moon_distance + 100.0)
	_camera.global_transform = xf
	_camera.fov = fov
	_camera.near = near_plane
	_camera.far = far_plane
	return pos.length()

## Rotates the camera so a place faces the viewer (used when the user picks an earthquake). Leaves any special camera
## mode first.
##
## [param lat]: latitude in degrees.
## [param lon]: longitude in degrees.
func look_at_location(lat: float, lon: float) -> void:
	_leave_special_mode()
	# World direction of the place: local position -> Earth rotation -> seasonal tilt.
	var v := _system.basis * (Basis(Vector3.UP, _earth_angle) * Geo.to_vec3(lat, lon, 1.0))
	_yaw = atan2(v.x, v.z)
	_pitch = -asin(clampf(v.y, -1.0, 1.0))
	_apply_camera()

## Development helper (the `--cam=` flag): sets yaw, pitch and distance directly.
##
## [param yaw_deg]: yaw in degrees.
## [param pitch_deg]: pitch in degrees.
## [param distance]: camera distance (limited to the zoom range).
func set_camera(yaw_deg: float, pitch_deg: float, distance: float) -> void:
	_yaw = deg_to_rad(yaw_deg)
	_pitch = deg_to_rad(pitch_deg)
	_distance = clampf(distance, MIN_DISTANCE, MAX_DISTANCE)
	_apply_camera()

## Tells the globe the size of its view so the camera is re-fitted when it changes.
##
## [param size]: the size in pixels.
func set_viewport_size(size: Vector2) -> void:
	_vp_size = size

## main.gd tells the globe when the mouse enters or leaves its view, so hover reports stop when outside.
##
## [param inside]: true if the mouse is inside.
func set_mouse_inside(inside: bool) -> void:
	_mouse_inside = inside

## Emitted when the welcome text appears or goes away, so the Welcome button can update.
##
## [param showing]: true when it appeared, false when it finished.
signal intro_changed(showing: bool)

# MARK: - Satellites

## Satellites farther out than this (in scene units) are drawn at this distance: the true distance of a geostationary
## satellite is 6.6 Earth radii.
const SAT_MAX_RADIUS := 70.0

## Makes a satellite model (see [method SatelliteModel.build]) and adds it under the Earth's satellite node.
##
## [param short_name]: the name for its label.
## Returns: {"holder", "label", "km", "name"}.
func _make_satellite(short_name: String) -> Dictionary:
	var item := SatelliteModel.build(short_name)
	_sat_node.add_child(item["holder"])
	return item

## Puts every tracked satellite where it is now, pointing along its track, and updates its label when the altitude
## changes; hides the ones no longer tracked. Far satellites are drawn closer than their true distance
## ([constant SAT_MAX_RADIUS]). Hidden when satellites are off.
func _update_satellites() -> void:
	var on := Settings.get_bool("show_satellites")
	_sat_node.visible = on
	if not on:
		return
	var now := Solar.now()
	var shown := {}
	for s in SatelliteService.positions(now):
		var id: int = s["id"]
		shown[id] = true
		if not _sat_items.has(id):
			_sat_items[id] = _make_satellite(str(s["label"]))
		var item: Dictionary = _sat_items[id]
		# Far satellites are drawn closer than their true distance (the geostationary ring is 6.6 globe radii out).
		var radius := minf(Geo.GLOBE_RADIUS * (1.0 + float(s["alt_km"]) / SatelliteService.EARTH_RADIUS_KM), SAT_MAX_RADIUS)
		var here := Geo.to_vec3(float(s["lat"]), float(s["lon"]), radius)
		var ahead := Geo.to_vec3(float(s["next_lat"]), float(s["next_lon"]), radius)
		var up := here.normalized()
		var fwd := (ahead - here)
		fwd = (fwd - up * fwd.dot(up)).normalized()
		var side := fwd.cross(up).normalized()
		(item["holder"] as Node3D).transform = Transform3D(Basis(fwd, up, side), here)
		var km := int(round(float(s["alt_km"])))
		if km != item["km"]:
			item["km"] = km
			(item["label"] as Label3D).text = "%s  %s" % [item["name"], SatelliteService.format_altitude(float(s["alt_km"]))]
	for id in _sat_items.keys():
		((_sat_items[id] as Dictionary)["holder"] as Node3D).visible = shown.has(id)   # untracked: not shown

## Shows the welcome text at start-up, if the `show_intro` setting says to. main.gd calls it once everything is built.
func start_intro() -> void:
	if Settings.get_bool("show_intro"):
		show_intro()

## Whether the welcome text is on screen.
##
## Returns: true while it exists.
func is_intro_showing() -> bool:
	return is_instance_valid(_intro)

## Shows the welcome text (it starts its orbit from the beginning). Does nothing if it is already showing. Emits
## [signal intro_changed].
##
## [param auto_fade]: true to let it fade away after its turns; false to keep it until dismissed.
func show_intro(auto_fade: bool = true) -> void:
	if is_instance_valid(_intro):
		return
	_intro = IntroText.new()
	_intro.auto_fade = auto_fade
	_fixed.add_child(_intro)
	_intro.finished.connect(func() -> void: intro_changed.emit(false))
	intro_changed.emit(true)

## Fades the welcome text out (one second) and removes it.
func hide_intro() -> void:
	if is_instance_valid(_intro):
		_intro.dismiss()

## The Welcome button: hides the text if it is showing, otherwise shows it and keeps it until the user taps the view
## or the button.
func toggle_intro() -> void:
	if is_instance_valid(_intro):
		hide_intro()
	else:
		show_intro(false)   # shown on request: stays until the user taps the view or the button

## Dismisses the welcome text when the user taps (presses and releases without moving more than [constant TAP_SLOP]);
## a drag or the wheel does not count.
##
## [param event]: the input event.
func _check_intro_tap(event: InputEvent) -> void:
	if not is_instance_valid(_intro) or not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT and mb.button_index != MOUSE_BUTTON_RIGHT and mb.button_index != MOUSE_BUTTON_MIDDLE:
		return   # wheel zoom is not a tap
	if mb.pressed:
		_tap_start = mb.position
	elif mb.position.distance_to(_tap_start) <= TAP_SLOP:
		_intro.dismiss()

## Handles mouse input from the globe's container (main.gd connects it): in the special camera modes, the flight and
## look-at-Moon rules apply ([method _flight_input], [method _zoom_look]); otherwise left drag turns the globe
## (Command/Option/Ctrl-drag pans it), the wheel and trackpad gestures zoom, double click resets the view, a long
## press (phones) or right click asks for the context menu ([signal context_requested]), and movement reports hover
## and star tooltips. All of it is ignored while the world is locked (apart from dismissing the welcome text).
##
## [param event]: the input event.
func handle_gui_input(event: InputEvent) -> void:
	_check_intro_tap(event)
	if Settings.get_bool("world_locked"):
		return
	if _cam_mode == CamMode.FLIGHT:
		_flight_input(event)
		return
	if _cam_mode == CamMode.LOOK_AT_MOON and _zoom_look(event):
		return
	if _cam_mode != CamMode.ORBIT and _moves_camera(event):
		_leave_special_mode()
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				_dragging = mb.pressed
				if mb.pressed and _last_star_tip != "":
					_last_star_tip = ""
					star_tooltip_changed.emit("", mb.position)
				if mb.pressed and _reset_tween != null and _reset_tween.is_valid():
					_reset_tween.kill()
				if mb.pressed and mb.double_click:
					_dragging = false
					_press_token += 1
					reset_view()   # double-click resets the view
				elif mb.pressed:
					_begin_long_press(mb.position)
				else:
					_press_token += 1
			MOUSE_BUTTON_WHEEL_UP:
				_distance = clampf(_distance * 0.92, MIN_DISTANCE, MAX_DISTANCE)
				_apply_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				_distance = clampf(_distance * 1.08, MIN_DISTANCE, MAX_DISTANCE)
				_apply_camera()
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					context_requested.emit(mb.position)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_mouse_pos = mm.position
		if mm.position.distance_to(_long_press_at) > TAP_SLOP * 2.0:
			_press_token += 1   # moved too far: not a long press
		if not _dragging:
			_update_star_tooltip(mm.position)
		if _dragging and not _pinching:
			if mm.meta_pressed or mm.alt_pressed or mm.ctrl_pressed:
				# Command/Option/Ctrl-drag moves the globe across the view (SceneKit's camera pan).
				var k := 2.0 * _distance * tan(deg_to_rad(_camera.fov) * 0.5) / maxf(1.0, get_viewport().get_visible_rect().size.y)
				_pan.x = clampf(_pan.x - mm.relative.x * k, -40.0, 40.0)
				_pan.y = clampf(_pan.y + mm.relative.y * k, -40.0, 40.0)
			else:
				var speed := 0.004 * (_distance / DEFAULT_DISTANCE)
				_turn(-mm.relative.x * speed, -mm.relative.y * speed)
			_apply_camera()
	elif event is InputEventMagnifyGesture:
		_distance = clampf(_distance / (event as InputEventMagnifyGesture).factor, MIN_DISTANCE, MAX_DISTANCE)
		_apply_camera()
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		_turn(pg.delta.x * 0.01, pg.delta.y * 0.01)
		_apply_camera()

## Turns the globe with a drag, without limits: the pitch may go over the poles and all the way round. Once the view is
## upside down (past the pole) the yaw change is reversed, so a drag to the right still turns the globe the same way
## on screen.
##
## [param d_yaw]: the yaw change in radians for a drag along the screen's X axis.
## [param d_pitch]: the pitch change in radians for a drag along the screen's Y axis.
func _turn(d_yaw: float, d_pitch: float) -> void:
	_yaw = wrapf(_yaw + d_yaw * (1.0 if cos(_pitch) >= 0.0 else -1.0), -PI, PI)
	_pitch = wrapf(_pitch + d_pitch, -PI, PI)

## Counts presses so a pending long-press timer can tell it was cancelled (the finger moved, lifted, or another press
## started).
var _press_token := 0
## Where the current press began, in pixels.
var _long_press_at := Vector2.ZERO

## On a phone or tablet, holds a finger still for about 0.6 seconds to ask for the context menu
## ([signal context_requested]); cancelled if the finger moves, lifts, or a second finger joins. Does nothing on a
## desktop.
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

## Input during the camera flight: dragging and zooming are ignored; a double click ends the flight (Reset View); a
## right click or long press still asks for the context menu.
##
## [param event]: the input event.
func _flight_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed and not mb.double_click
			if mb.pressed and mb.double_click:
				_press_token += 1
				reset_view()
			elif mb.pressed:
				_begin_long_press(mb.position)
			else:
				_press_token += 1
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			context_requested.emit(mb.position)
	elif event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).position.distance_to(_long_press_at) > TAP_SLOP * 2.0:
			_press_token += 1

## Looking at the Moon: the wheel and the trackpad pinch zoom by narrowing or widening the field of view.
##
## [param event]: the input event.
## Returns: true if the event was used.
func _zoom_look(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_look(1.0 / 0.92)
			return true
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_look(1.0 / 1.08)
			return true
	elif event is InputEventMagnifyGesture:
		zoom_look((event as InputEventMagnifyGesture).factor)
		return true
	return false

## Zooms the view of the Moon (the field of view, within [constant LOOK_FOV_MIN] to [constant LOOK_FOV_MAX]).
##
## [param factor]: greater than 1 zooms in.
func zoom_look(factor: float) -> void:
	_look_fov = clampf(_look_fov / factor, LOOK_FOV_MIN, LOOK_FOV_MAX)
	_apply_camera()

## Whether an input event would turn, pan or zoom the camera (such an event ends a special camera mode).
##
## [param event]: the input event.
## Returns: true if it would.
func _moves_camera(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN
	if event is InputEventMouseMotion:
		return _dragging and not _pinching
	return event is InputEventMagnifyGesture or event is InputEventPanGesture

## True while two fingers are down, so the one-finger drag that Godot emulates from the first finger does not also
## spin the globe.
var _pinching := false

## main.gd tells the globe when a two-finger pinch starts or ends.
##
## [param on]: true while pinching.
func set_pinching(on: bool) -> void:
	_pinching = on

## Two-finger pinch on a touch screen (driven by main.gd): zooms the camera (or the view of the Moon), unless the
## world is locked or the flight is running. Moving the camera ends other special modes.
##
## [param factor]: greater than 1 when the fingers move apart (zoom in), like the trackpad magnify gesture.
func pinch_zoom(factor: float) -> void:
	if Settings.get_bool("world_locked"):
		return
	if _cam_mode == CamMode.FLIGHT:
		return
	if _cam_mode == CamMode.LOOK_AT_MOON:
		zoom_look(factor)
		return
	_leave_special_mode()
	_distance = clampf(_distance / factor, MIN_DISTANCE, MAX_DISTANCE)
	_apply_camera()

## Finds the place on the Earth under a screen position by casting a ray from the camera and intersecting the sphere.
##
## [param screen_pos]: position in pixels.
## Returns: {"hit": false} if the ray misses the Earth, otherwise {"hit": true, "lat": ..., "lon": ...}.
func pick(screen_pos: Vector2) -> Dictionary:
	var origin := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	var b := origin.dot(dir)
	var c := origin.dot(origin) - R * R
	var disc := b * b - c
	if disc < 0.0:
		return {"hit": false}
	var t := -b - sqrt(disc)
	if t < 0.0:
		return {"hit": false}
	var world_pt := origin + dir * t
	var local_pt := _earth.to_local(world_pt)
	var ll := Geo.vec3_to_latlon(local_pt)
	return {"hit": true, "lat": ll.x, "lon": ll.y}

## Reports the place under the mouse with [signal hover_changed], if the mouse is inside the view and `mouse_tracking`
## is on.
func _update_hover() -> void:
	if not _mouse_inside or not Settings.get_bool("mouse_tracking"):
		return
	var p := pick(_mouse_pos)
	if p["hit"]:
		hover_changed.emit(p["lat"], p["lon"], true)
	else:
		hover_changed.emit(0.0, 0.0, false)

## Emits [signal location_clicked] for the place at a screen position, if it is on the Earth.
##
## [param pos]: position in pixels.
func _emit_click(pos: Vector2) -> void:
	var p := pick(pos)
	if p["hit"]:
		location_clicked.emit(p["lat"], p["lon"])

## Takes a picture of the globe's viewport.
##
## Returns: the Image.
func capture() -> Image:
	return get_viewport().get_texture().get_image()
