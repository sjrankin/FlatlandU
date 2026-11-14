class_name FlatView
extends Control
## Flatland's flat modes: the north-centered and south-centered polar maps, and the
## equirectangular ("Rectangular") map. The map turns with the Earth beneath a fixed day/night
## mask, exactly as in the original; hour labels ring the map; the sun sits at the rim.

signal hover_changed(lat: float, lon: float, over_map: bool)
signal location_clicked(lat: float, lon: float)


var view_type := Settings.VIEW_FLAT_NORTH
## When shown on a plane in 3D (FlatStage) the stage draws the sun and handles the mouse.
var stage_mode := false

var _map_tex: Texture2D
var _map_file := ""
var _night: ColorRect
var _night_mat: ShaderMaterial
var _light := 1.0
var _sea_tex: Texture2D
var _sea_file := ""
var _sun_tex_up: Texture2D = load("res://Assets/Suns/Sun2Up.png")
var _sun_tex_down: Texture2D = load("res://Assets/Suns/Sun2Down.png")
var _tick := 0.0
var _now := 0.0
var _sub_lon := 0.0
var _decl := 0.0
var _font: Font

func _ready() -> void:
	_font = Geo.label_font()
	_night_mat = ShaderMaterial.new()
	_night_mat.shader = load("res://shaders/night.gdshader")
	_night = ColorRect.new()
	_night.material = _night_mat
	_night.color = Color.WHITE
	_night.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_night)
	CityDB.user_data_changed.connect(queue_redraw)
	mouse_filter = Control.MOUSE_FILTER_IGNORE if stage_mode else Control.MOUSE_FILTER_STOP
	Settings.changed.connect(_on_setting_changed)
	MapCatalog.texture_ready.connect(_on_texture_ready)
	QuakeService.quakes_updated.connect(func(_q: Array) -> void: queue_redraw())
	resized.connect(func() -> void:
		_update_night()
		queue_redraw())
	refresh()

func set_view(type: String) -> void:
	view_type = type
	_map_tex = null
	refresh()

func refresh() -> void:
	_now = Solar.now()
	_sub_lon = Solar.subsolar_longitude(_now)
	_decl = Solar.declination(_now)
	_request_map()
	_update_night()
	queue_redraw()

func _on_setting_changed(key: String, _v: Variant) -> void:
	if key == "label_font":
		_font = Geo.label_font()
	if key == "debug_time_tick":
		refresh()
	_request_map()
	queue_redraw()

func _request_map() -> void:
	var m := MapCatalog.map_for(Settings.get_string("map_type"))
	if m.is_empty():
		return
	match view_type:
		Settings.VIEW_FLAT_NORTH: _map_file = m["north"]
		Settings.VIEW_FLAT_SOUTH: _map_file = m["south"]
		_: _map_file = m["globe"]
	_light = 1.0   # maps are shown at full brightness (the per-map multiplier made them too dark)
	_sea_file = str(m.get("sea", "")) if view_type == Settings.VIEW_RECT else ""
	if _sea_file != "":
		var st := MapCatalog.request(_sea_file)
		if st != null:
			_sea_tex = st
	var t := MapCatalog.request(_map_file)
	if t != null:
		_map_tex = t

## Position the shader overlay over the map and feed it the sun's position.
func _update_night() -> void:
	if _night == null:
		return
	_night.visible = Settings.get_bool("show_night")
	if _is_polar():
		var rad := _map_radius()
		_night.position = _center() - Vector2(rad, rad)
		_night.size = Vector2(rad, rad) * 2.0
		_night_mat.set_shader_parameter("mode", 0 if view_type == Settings.VIEW_FLAT_NORTH else 1)
	else:
		var r := _rect_map()
		_night.position = r.position
		_night.size = r.size
		_night_mat.set_shader_parameter("mode", 2)
	_night_mat.set_shader_parameter("sun_declination", deg_to_rad(_decl))
	_night_mat.set_shader_parameter("sun_longitude", _sub_lon)
	_night_mat.set_shader_parameter("night_alpha", _night_alpha())

func _on_texture_ready(file_name: String, tex: Texture2D) -> void:
	if file_name == _map_file:
		_map_tex = tex
	if file_name == _sea_file and _sea_file != "":
		_sea_tex = tex
	queue_redraw()

func _process(delta: float) -> void:
	if not PowerManager.drawing():
		return   # a sheet covers the screen (or the app is in the background): skip the redraw work too
	if visible and (PowerManager.quakes_animate() or Settings.get_bool("show_satellites")):
		queue_redraw()   # animate the radiating rings and the moving satellites
	_tick += delta
	if _tick >= 1.0:
		_tick = 0.0
		refresh()

# MARK: - Geometry

## UI scale factor so labels and markers grow with the window.
func _k() -> float:
	return clampf(minf(size.x, size.y) / 900.0, 0.6, 3.0)

func _grid_col() -> Color:
	return Settings.get_color("color_grid")

func _is_polar() -> bool:
	return view_type == Settings.VIEW_FLAT_NORTH or view_type == Settings.VIEW_FLAT_SOUTH

func _center() -> Vector2:
	return size * 0.5

## The polar map is kept well inside the picture so the hour ring and the clock have room around it.
func _map_radius() -> float:
	return minf(size.x, size.y) * 0.39

## Offset of an object's shadow on the map: away from the sun, longer for taller objects. The shadows are in
## relation to the sun's position, not to a scene light.
func _shadow_offset(p: Vector2, height: float) -> Vector2:
	var away := p - sun_picture_position()
	if away.length() < 1.0:
		away = Vector2(1.0, 1.0)
	return away.normalized() * height * _k()

## Where the sun is, in picture pixels (used by the 3D stage to float the sun above the map).
func sun_picture_position() -> Vector2:
	return project(_decl, _sub_lon)      # over the sub-solar point on every flat map

func _rect_map() -> Rect2:
	var w := minf(size.x * 0.97, (size.y - 130.0 * _k()) * 2.0)
	var h := w * 0.5
	return Rect2((size.x - w) * 0.5, (size.y - h) * 0.5 + 8.0, w, h)

## Counter-clockwise rotation (degrees) of the polar map for the current time.
func _map_rotation_ccw() -> float:
	if view_type == Settings.VIEW_FLAT_NORTH:
		return 180.0 - _sub_lon
	return _sub_lon

## Screen position of a location. For polar maps, `radius_scale` pushes the point outward.
func project(lat: float, lon: float, radius_scale: float = 1.0) -> Vector2:
	if view_type == Settings.VIEW_RECT:
		var r := _rect_map()
		return Vector2(r.position.x + (lon + 180.0) / 360.0 * r.size.x, r.position.y + (90.0 - lat) / 180.0 * r.size.y)
	var rad := _map_radius()
	var ang: float
	var rr: float
	if view_type == Settings.VIEW_FLAT_NORTH:
		ang = deg_to_rad(90.0 + lon + _map_rotation_ccw())
		rr = rad * (90.0 - lat) / 180.0
	else:
		ang = deg_to_rad(90.0 - lon + _map_rotation_ccw())
		rr = rad * (90.0 + lat) / 180.0
	rr *= radius_scale
	return _center() + Vector2(cos(ang), -sin(ang)) * rr

## Inverse of `project` for the current frame; returns {"hit", "lat", "lon"}.
func pick(p: Vector2) -> Dictionary:
	if view_type == Settings.VIEW_RECT:
		var r := _rect_map()
		if not r.has_point(p):
			return {"hit": false}
		return {"hit": true, "lat": 90.0 - (p.y - r.position.y) / r.size.y * 180.0,
			"lon": (p.x - r.position.x) / r.size.x * 360.0 - 180.0}
	var d := p - _center()
	var rad := _map_radius()
	var rr := d.length()
	if rr > rad:
		return {"hit": false}
	var ang := rad_to_deg(atan2(-d.y, d.x))
	if view_type == Settings.VIEW_FLAT_NORTH:
		return {"hit": true, "lat": 90.0 - rr / rad * 180.0, "lon": wrapf(ang - 90.0 - _map_rotation_ccw(), -180.0, 180.0)}
	return {"hit": true, "lat": rr / rad * 180.0 - 90.0, "lon": wrapf(90.0 - ang + _map_rotation_ccw(), -180.0, 180.0)}

# MARK: - Drawing

func _draw() -> void:
	if _is_polar():
		_draw_polar()
	else:
		_draw_rectangular()
	_draw_regions()
	_draw_cities()
	_draw_pois()
	_draw_quakes()
	_draw_satellites()

func _night_alpha() -> float:
	return float(Settings.NIGHT_ALPHA.get(Settings.get_string("night_darkness"), 0.4)) * 0.7   # lighter than before

func _draw_polar() -> void:
	var c := _center()
	var rad := _map_radius()
	var rect := Rect2(-rad, -rad, rad * 2.0, rad * 2.0)
	# Map (rotates with the Earth).
	draw_set_transform(c, -deg_to_rad(_map_rotation_ccw()), Vector2.ONE)
	if _map_tex != null:
		draw_texture_rect(_map_tex, rect, false, Color(_light, _light, _light, 1.0))
	else:
		draw_circle(Vector2.ZERO, rad, Color("#16264a"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_polar_grid()
	_draw_polar_hours()
	_draw_sun()

func _draw_polar_grid() -> void:
	if not Settings.get_bool("show_grid"):
		return
	var c := _center()
	var rad := _map_radius()
	var lat_lines: Array = []
	if Settings.get_bool("show_equator"):
		lat_lines.append(0.0)
	if Settings.get_bool("show_tropics"):
		lat_lines.append_array([23.4367, -23.4367])
	if Settings.get_bool("show_polar_circles"):
		lat_lines.append_array([66.5633, -66.5633])
	for lat in lat_lines:
		var r: float = rad * ((90.0 - lat) / 180.0 if view_type == Settings.VIEW_FLAT_NORTH else (90.0 + lat) / 180.0)
		draw_arc(c, r, 0.0, TAU, 128, _grid_col(), 1.5, true)
	if Settings.get_bool("show_minor_grid"):
		for k in range(24):
			var lon := 15.0 * k
			var a := project(-90.0 if view_type == Settings.VIEW_FLAT_NORTH else 90.0, lon)
			var b := project(90.0 if view_type == Settings.VIEW_FLAT_NORTH else -90.0, lon)
			if view_type == Settings.VIEW_FLAT_NORTH:
				a = project(-90.0, lon)
				b = c
			else:
				a = project(90.0, lon)
				b = c
			draw_line(b, a, _grid_col(), 1.5, true)
	if Settings.get_bool("show_noon_meridians"):
		var dir := Vector2(0, 1) if view_type == Settings.VIEW_FLAT_NORTH else Vector2(0, -1)
		draw_line(c, c + dir * rad, Settings.get_color("color_grid"), 2.5, true)

func _sun_direction() -> Vector2:
	return Vector2(0, 1) if view_type == Settings.VIEW_FLAT_NORTH else Vector2(0, -1)

func _draw_polar_hours() -> void:
	if stage_mode:
		return      # on the 3D stage the hours are extruded 3D text (see hour_label_specs)
	var kind := Settings.get_string("hour_type")
	if kind == Settings.HOURS_NONE:
		return
	var c := _center()
	var rad := _map_radius() * 1.16
	var utc_hours := fposmod(_now, 86400.0) / 3600.0
	for k in range(24):
		var ang_ccw: float
		var text := ""
		match kind:
			Settings.HOURS_NOON:
				ang_ccw = _noon_angle(k)
				text = "+0" if k == 0 else ("%+d" % (k if k <= 12 else k - 24)).replace("-", "−")
			Settings.HOURS_SOLAR:
				ang_ccw = _noon_angle(k)
				text = "%02d:00" % ((12 + k) % 24)
			Settings.HOURS_LOCATION:
				var home_lon := Settings.get_float("home_longitude")
				ang_ccw = _angle_of_lon(home_lon + 15.0 * k)
				text = "Home" if k == 0 else ("%+d" % (k if k <= 12 else k - 24)).replace("-", "−")
			_:
				var lon := 15.0 * k
				ang_ccw = _angle_of_lon(lon)
				var h := fposmod(utc_hours + lon / 15.0, 24.0)
				text = "%d:%02d" % [int(h), int((h - floor(h)) * 60.0)]
		var a := deg_to_rad(ang_ccw)
		var pos := c + Vector2(cos(a), -sin(a)) * rad
		# Text base line follows the ring; flip on the lower half so it stays readable.
		var rot := -(a - PI / 2.0)
		if sin(a) < 0.0:
			rot += PI   # keep the lower labels upright
		draw_set_transform(pos, rot, Vector2.ONE)
		var fsize := int(26 * _k())
		var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		draw_string_outline(_font, Vector2(-w * 0.5, fsize * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 4, Color(0, 0, 0, 0.8))
		draw_string(_font, Vector2(-w * 0.5, fsize * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Settings.get_color("color_hours_2d"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## The hour labels as data, for the 3D stage to build extruded text from: an Array of
## {"text", "pos" (picture pixels, the centre of the text), "rot" (radians, canvas rotation), "size" (pixels)}.
func hour_label_specs() -> Array:
	var out: Array = []
	var kind := Settings.get_string("hour_type")
	if kind == Settings.HOURS_NONE:
		return out
	var utc_hours := fposmod(_now, 86400.0) / 3600.0
	if _is_polar():
		var c := _center()
		var rad := _map_radius() * 1.16
		for k in range(24):
			var ang_ccw: float
			var text := ""
			match kind:
				Settings.HOURS_NOON:
					ang_ccw = _noon_angle(k)
					text = "+0" if k == 0 else ("%+d" % (k if k <= 12 else k - 24)).replace("-", "−")
				Settings.HOURS_SOLAR:
					ang_ccw = _noon_angle(k)
					text = "%02d:00" % ((12 + k) % 24)
				Settings.HOURS_LOCATION:
					var home_lon := Settings.get_float("home_longitude")
					ang_ccw = _angle_of_lon(home_lon + 15.0 * k)
					text = "Home" if k == 0 else ("%+d" % (k if k <= 12 else k - 24)).replace("-", "−")
				_:
					var lon := 15.0 * k
					ang_ccw = _angle_of_lon(lon)
					var h := fposmod(utc_hours + lon / 15.0, 24.0)
					text = "%d:%02d" % [int(h), int((h - floor(h)) * 60.0)]
			var a := deg_to_rad(ang_ccw)
			var rot := -(a - PI / 2.0)
			if sin(a) < 0.0:
				rot += PI
			out.append({"text": text, "pos": c + Vector2(cos(a), -sin(a)) * rad, "rot": rot, "size": 26.0 * _k()})
	else:
		var r := _rect_map()
		for k in range(24):
			var lon := wrapf(-180.0 + 7.5 + 15.0 * k, -180.0, 180.0)
			var text := ""
			match kind:
				Settings.HOURS_WALL:
					var h := fposmod(utc_hours + lon / 15.0, 24.0)
					text = "%d:%02d" % [int(h), int((h - floor(h)) * 60.0)]
				Settings.HOURS_SOLAR:
					var h := fposmod(12.0 + (lon - _sub_lon) / 15.0, 24.0)
					text = "%02d:00" % int(h)
				_:
					var off := int(round(wrapf((lon - _sub_lon) / 15.0, -12.0, 12.0)))
					text = "+0" if off == 0 else ("%+d" % off).replace("-", "−")
			out.append({"text": text, "pos": Vector2(project(0.0, lon).x, r.end.y + 26.0 * _k() - 6.0 * _k()), "rot": 0.0, "size": 20.0 * _k()})
	return out

## Screen angle (CCW degrees) of the meridian at `lon` for the current map rotation.
func _angle_of_lon(lon: float) -> float:
	if view_type == Settings.VIEW_FLAT_NORTH:
		return 90.0 + lon + _map_rotation_ccw()
	return 90.0 - lon + _map_rotation_ccw()

## Fixed-to-sun hour positions: `k` hours east of solar noon.
func _noon_angle(k: int) -> float:
	if view_type == Settings.VIEW_FLAT_NORTH:
		return 270.0 + 15.0 * k
	return 90.0 - 15.0 * k

func _draw_sun() -> void:
	if stage_mode or not Settings.get_bool("show_sun"):
		return
	var c := _center()
	var rad := _map_radius() * 1.27
	var s := _sun_direction()
	var tex := _sun_tex_down if view_type == Settings.VIEW_FLAT_NORTH else _sun_tex_up
	var pos := c + s * rad
	var d := minf(size.x, size.y) * 0.075
	if tex != null:
		draw_texture_rect(tex, Rect2(pos - Vector2(d, d) * 0.5, Vector2(d, d)), false)
	else:
		draw_circle(pos, d * 0.5, Color("#f08a1c"))

func _draw_rectangular() -> void:
	var r := _rect_map()
	draw_rect(r, Color("#16264a"))
	if _sea_tex != null and _sea_file != "":
		draw_texture_rect(_sea_tex, r, false)
	if _map_tex != null:
		draw_texture_rect(_map_tex, r, false, Color(_light, _light, _light, 1.0))
	if Settings.get_bool("show_grid"):
		var lat_lines: Array = []
		if Settings.get_bool("show_equator"): lat_lines.append(0.0)
		if Settings.get_bool("show_tropics"): lat_lines.append_array([23.4367, -23.4367])
		if Settings.get_bool("show_polar_circles"): lat_lines.append_array([66.5633, -66.5633])
		for lat in lat_lines:
			var y := project(lat, 0.0).y
			draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), _grid_col(), 1.5)
		if Settings.get_bool("show_minor_grid"):
			for k in range(-11, 12):
				var x := project(0.0, 15.0 * k).x
				draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), _grid_col(), 1.5)
	# Sun at the sub-solar point, noon meridian marker.
	var sun_pt := project(_decl, _sub_lon)
	if Settings.get_bool("show_noon_meridians"):
		draw_line(Vector2(sun_pt.x, r.position.y), Vector2(sun_pt.x, r.end.y), Settings.get_color("color_grid"), 1.25)
	if Settings.get_bool("show_sun") and not stage_mode:
		var d := r.size.y * 0.1
		if _sun_tex_up != null:
			draw_texture_rect(_sun_tex_up, Rect2(sun_pt - Vector2(d, d) * 0.5, Vector2(d, d)), false)
	# Hour labels along the bottom edge.
	var kind := Settings.get_string("hour_type")
	if kind != Settings.HOURS_NONE and not stage_mode:
		var utc_hours := fposmod(_now, 86400.0) / 3600.0
		for k in range(24):
			var lon := wrapf(-180.0 + 7.5 + 15.0 * k, -180.0, 180.0)
			var text := ""
			match kind:
				Settings.HOURS_WALL:
					var h := fposmod(utc_hours + lon / 15.0, 24.0)
					text = "%d:%02d" % [int(h), int((h - floor(h)) * 60.0)]
				Settings.HOURS_SOLAR:
					var h := fposmod(12.0 + (lon - _sub_lon) / 15.0, 24.0)
					text = "%02d:00" % int(h)
				_:
					var off := int(round(wrapf((lon - _sub_lon) / 15.0, -12.0, 12.0)))
					text = "+0" if off == 0 else ("%+d" % off).replace("-", "−")
			var x := project(0.0, lon).x
			var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(20 * _k())).x
			draw_string_outline(_font, Vector2(x - w * 0.5, r.end.y + 26 * _k()), text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(20 * _k()), 4, Color(0, 0, 0, 0.8))
			draw_string(_font, Vector2(x - w * 0.5, r.end.y + 26 * _k()), text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(20 * _k()), Settings.get_color("color_hours_2d"))

func _draw_cities() -> void:
	if not Settings.get_bool("show_cities"):
		return
	var names := Settings.get_bool("show_city_names")
	for city in CityDB.filtered_cities():
		var p := project(city["Latitude"], city["Longitude"])
		if not stage_mode:     # on the 3D stage the city is a 3D shape, not a dot
			if Settings.get_bool("show_shadows"):
				draw_circle(p + _shadow_offset(p, 3.5), 4.5 * _k(), Color(0, 0, 0, 0.5))
			draw_circle(p, 4.5 * _k(), Settings.get_color("color_city_2d"))
		var pop := maxi(int(city.get("Population", 0)), int(city.get("MetropolitanPopulation", 0)))
		if names:
			var day := Solar.is_daylight(city["Latitude"], city["Longitude"], _now)
			var col := Color("#0a1f6b") if day else Color("#63b8ff")
			draw_string(_font, p + Vector2(7, 4) * _k(), str(city["Name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * _k()), col)

func _draw_pois() -> void:
	if not Settings.get_bool("show_user_pois"):
		return
	for poi in CityDB.all_pois():
		var p := project(poi["Latitude"], poi["Longitude"])
		var col := Color(str(poi.get("Color", "#ee44cc")))
		var d := 6.0 * _k()
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0)]), col)
		draw_string(_font, p + Vector2(d + 3, 4) * 1.0, str(poi["Name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * _k()), col)

func _draw_regions() -> void:
	if not Settings.get_bool("show_regions"):
		return
	for r in CityDB.regions:
		if not r.get("enabled", true):
			continue
		var col := Color(str(r.get("color", "#ffcc00")))
		var pts := PackedVector2Array()
		var lat1 := float(r["lat1"])
		var lat2 := float(r["lat2"])
		var lon1 := float(r["lon1"])
		var lon2 := float(r["lon2"])
		if lon2 < lon1:
			lon2 += 360.0
		var steps := 24
		for i in range(steps):
			pts.append(project(lat1, wrapf(lon1 + (lon2 - lon1) * i / steps, -180.0, 180.0)))
		for i in range(steps):
			pts.append(project(lat1 + (lat2 - lat1) * i / steps, wrapf(lon2, -180.0, 180.0)))
		for i in range(steps):
			pts.append(project(lat2, wrapf(lon2 - (lon2 - lon1) * i / steps, -180.0, 180.0)))
		for i in range(steps):
			pts.append(project(lat2 + (lat1 - lat2) * i / steps, wrapf(lon1, -180.0, 180.0)))
		pts.append(pts[0])
		if view_type == Settings.VIEW_RECT:
			continue_polyline(pts, col)
		else:
			draw_polyline(pts, col, 2.0 * _k(), true)

func continue_polyline(pts: PackedVector2Array, col: Color) -> void:
	# Rectangular map: skip the segment that wraps across the antimeridian.
	var run := PackedVector2Array()
	for p in pts:
		if run.size() > 0 and absf(p.x - run[run.size() - 1].x) > size.x * 0.5:
			if run.size() > 1:
				draw_polyline(run, col, 2.0, true)
			run = PackedVector2Array()
		run.append(p)
	if run.size() > 1:
		draw_polyline(run, col, 2.0, true)

func _draw_quakes() -> void:
	if not Settings.get_bool("enable_earthquakes"):
		return
	for q in QuakeService.visible_quakes():
		var p := project(q["lat"], q["lon"])
		var col := QuakeService.magnitude_color(q["magnitude"])
		var indicator := Settings.get_string("quake_indicator")
		if Time.get_unix_time_from_system() - float(q["time"]) <= 86400.0 and indicator == "Arrow and Ring":
			_draw_arrow_and_ring(p, q["magnitude"])
		elif Time.get_unix_time_from_system() - float(q["time"]) <= 86400.0 and indicator != "None":
			# Radiating ring for quakes in the last 24 hours, as in Flatland.
			var dur: float = 1.0 + (1.0 - q["magnitude"] / 10.0)
			var ph: float = fposmod(Time.get_ticks_msec() / 1000.0, dur) / dur
			draw_arc(p, (4.0 + 22.0 * ph) * _k(), 0.0, TAU, 32, Color(1.0, 0.627, 0.5, 0.8 * (1.0 - ph)), 3.0 * _k(), true)
		if not stage_mode:     # on the 3D stage the earthquake is a 3D shape; its ring and number stay
			draw_circle(p + _shadow_offset(p, 3.0 + q["magnitude"] * 0.6), (3.0 + q["magnitude"] * 0.7) * _k(), Color(0, 0, 0, 0.4))
			draw_circle(p, (3.0 + q["magnitude"] * 0.7) * _k(), Color(col, 0.55))
			draw_arc(p, (3.0 + q["magnitude"] * 0.7) * _k(), 0.0, TAU, 20, col, 1.0, true)
		draw_string(_font, p + Vector2(8, -8), "%.1f" % q["magnitude"], HORIZONTAL_ALIGNMENT_LEFT, -1, int(26 * _k()), col)

## The still "Arrow and Ring" indicator: a ring around the spot and a down-pointing arrow above it. The ring's
## radius, the arrow's size and its height above the spot all grow in proportion to the magnitude.
func _draw_arrow_and_ring(p: Vector2, mag: float) -> void:
	var k := _k()
	var red := Color(1.0, 0.14, 0.0, 0.9)
	draw_arc(p, 3.5 * mag * k, 0.0, TAU, 40, red, 3.0 * k, true)
	var s := 3.2 * mag * k                       # arrow size
	var tip := p + Vector2(0.0, -1.2 * mag * k)  # the tip hovers this high above the spot
	var hw := 0.425 * s
	var sw := 0.106 * s
	var neck := tip + Vector2(0.0, -0.667 * s)
	draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(hw, -0.667 * s), tip + Vector2(-hw, -0.667 * s)]), red)
	draw_rect(Rect2(neck + Vector2(-sw, -1.0 * s), Vector2(2.0 * sw, 1.0 * s + 0.5 * k)), red)

## Satellites: a pill-shaped body with two solar panels, turned along the satellite's track, and a small
## label (name and altitude) beside it.
func _draw_satellites() -> void:
	if stage_mode or not Settings.get_bool("show_satellites"):
		return      # on the 3D stage satellites are 3D models floating over the map
	var k := _k()
	for s in SatelliteService.positions(Solar.now()):
		var p := project(float(s["lat"]), float(s["lon"]))
		var q := project(float(s["next_lat"]), float(s["next_lon"]))
		var heading := 0.0
		if p.distance_to(q) < 100.0 * k:      # not across the map edge or a polar jump
			heading = (q - p).angle()
		# The shadow falls away from the sun, farther the higher the satellite is.
		var shadow_height := minf(float(s["alt_km"]) / 40.0, 45.0) + 8.0
		_draw_satellite_shape(p + _shadow_offset(p, shadow_height), heading, true)
		_draw_satellite_shape(p, heading, false)
		var text := "%s  %s" % [s["label"], SatelliteService.format_altitude(float(s["alt_km"]))]
		draw_string_outline(_font, p + Vector2(20.0, -12.0) * k, text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * k), 5, Color.BLACK)
		draw_string(_font, p + Vector2(20.0, -12.0) * k, text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * k), Color("#fff2b0"))

## A pill-shaped body with two solar panels, drawn at `p` along `heading`; as a dark silhouette for a shadow.
func _draw_satellite_shape(p: Vector2, heading: float, shadow: bool) -> void:
	var k := _k()
	var body := StyleBoxFlat.new()
	body.bg_color = Color(0, 0, 0, 0.4) if shadow else Color("#e4e4ea")
	body.border_color = Color(0, 0, 0, 0.0) if shadow else Color("#50505a")
	body.set_border_width_all(0 if shadow else 1)
	body.set_corner_radius_all(int(6 * k))
	var panel_fill := Color(0, 0, 0, 0.4) if shadow else Color("#1d4fb5")
	var panel_edge := Color("#0b2766")
	draw_set_transform(p, heading, Vector2.ONE)
	for side in [-1.0, 1.0]:
		var panel := Rect2(Vector2(-6.0 * k, (4.0 if side > 0.0 else -22.0) * k), Vector2(12.0 * k, 18.0 * k))
		draw_rect(panel, panel_fill)
		if not shadow:
			draw_rect(panel, panel_edge, false, 1.0)
			draw_line(panel.position + Vector2(panel.size.x * 0.5, 0.0), panel.position + Vector2(panel.size.x * 0.5, panel.size.y), panel_edge, 1.0)
	draw_style_box(body, Rect2(Vector2(-14.0 * k, -5.0 * k), Vector2(28.0 * k, 10.0 * k)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# MARK: - Input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Settings.get_bool("mouse_tracking"):
		var p := pick((event as InputEventMouseMotion).position)
		hover_changed.emit(p.get("lat", 0.0), p.get("lon", 0.0), p["hit"])
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_RIGHT or (mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click)):
			var p := pick(mb.position)
			if p["hit"]:
				location_clicked.emit(p["lat"], p["lon"])

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		hover_changed.emit(0.0, 0.0, false)
