class_name FlatView
extends Control
## Flatland's flat modes: the north-centered and south-centered polar maps, and the
## equirectangular ("Rectangular") map. The map turns with the Earth beneath a fixed day/night
## mask, exactly as in the original; hour labels ring the map; the sun sits at the rim.

## Emitted as the mouse moves over the map (when the `mouse_tracking` setting is on) and when it leaves.
##
## [param lat]: latitude under the mouse (0 when not over the map).
## [param lon]: longitude under the mouse.
## [param over_map]: true if the mouse is over the map itself.
signal hover_changed(lat: float, lon: float, over_map: bool)
## Emitted when the user right-clicks, or double-clicks with the left button, on the map, so main.gd can show the
## What's Here popup.
##
## [param lat]: the clicked latitude.
## [param lon]: the clicked longitude.
signal location_clicked(lat: float, lon: float)


## Which flat map this draws: [constant Settings.VIEW_FLAT_NORTH], [constant Settings.VIEW_FLAT_SOUTH] or
## [constant Settings.VIEW_RECT]. Change it with [method set_view].
var view_type := Settings.VIEW_FLAT_NORTH
## True when this control is drawn onto a plane in 3D by [FlatStage]: the stage then draws the Sun, hour labels,
## cities and satellites as 3D objects and handles the mouse, and this draws only the map, grid and rings.
var stage_mode := false

## The map picture currently drawn; null until it has loaded.
var _map_tex: Texture2D
## File name of the map being drawn (a polar one for the polar views, the globe one for the rectangular view).
var _map_file := ""
## The ColorRect that carries the night-shading shader over the map.
var _night: ColorRect
## The ShaderMaterial of the night shading (see `shaders/night.gdshader`); fed the Sun's position by
## [method _update_night].
var _night_mat: ShaderMaterial
## Brightness factor for the map (always 1.0: the per-map multiplier made maps too dark).
var _light := 1.0
## Optional picture of the sea, drawn under the rectangular map; null if the map has none.
var _sea_tex: Texture2D
## File name of that sea picture ("" if none).
var _sea_file := ""
## The Sun picture for the south-centered and rectangular maps.
var _sun_tex_up: Texture2D = load("res://Assets/Suns/Sun2Up.png")
## The Sun picture for the north-centered map.
var _sun_tex_down: Texture2D = load("res://Assets/Suns/Sun2Down.png")
## Seconds since the last once-a-second [method refresh].
var _tick := 0.0
## The time (Unix, UTC) of the last [method refresh]; all drawing uses it so one frame is consistent.
var _now := 0.0
## Sub-solar longitude at [member _now].
var _sub_lon := 0.0
## Solar declination at [member _now].
var _decl := 0.0
## The font for labels (see [method Geo.label_font]).
var _font: Font

## Sets up the label font, the night-shading overlay and the connections that keep the map current: user data
## (locations, regions), settings, map textures, quakes and resizing.
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

## Switches to another flat map.
##
## [param type]: [constant Settings.VIEW_FLAT_NORTH], [constant Settings.VIEW_FLAT_SOUTH] or
##   [constant Settings.VIEW_RECT].
func set_view(type: String) -> void:
	view_type = type
	_map_tex = null
	refresh()

## Re-reads the time and Sun position, asks for the map picture, updates the night shading and redraws. Called each
## second and when the clock is changed in the debugger.
func refresh() -> void:
	_now = Solar.now()
	_sub_lon = Solar.subsolar_longitude(_now)
	_decl = Solar.declination(_now)
	_request_map()
	_update_night()
	queue_redraw()

## A setting changed: refreshes the label font and the map choice and redraws; a debugger clock change refreshes the
## time too.
##
## [param key]: the setting's key.
## [param _v]: its new value (unused).
func _on_setting_changed(key: String, _v: Variant) -> void:
	if key == "label_font":
		_font = Geo.label_font()
	if key == "debug_time_tick":
		refresh()
	_request_map()
	queue_redraw()

## Chooses the map file for the current view from the `map_type` setting (north, south or globe file) and asks
## [MapCatalog] for it, and for the sea picture on the rectangular map. The pictures are stored when they arrive.
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

## Positions the night-shading overlay over the map (a circle for the polar maps, a rectangle otherwise) and gives its
## shader the Sun's declination and longitude and the darkness. Hidden when `show_night` is off.
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

## A map picture finished loading: stores it if it is the one needed and redraws.
##
## [param file_name]: the file that arrived.
## [param tex]: its texture.
func _on_texture_ready(file_name: String, tex: Texture2D) -> void:
	if file_name == _map_file:
		_map_tex = tex
	if file_name == _sea_file and _sea_file != "":
		_sea_tex = tex
	queue_redraw()

## Every frame: redraws if something animates (quake rings, satellites) and calls [method refresh] once a second. Does
## nothing while drawing is paused (see [method PowerManager.drawing]).
##
## [param delta]: seconds since the last frame.
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

## The factor that makes labels and markers grow with the window.
##
## Returns: the smaller side of the window over 900, kept between 0.6 and 3.
func _k() -> float:
	return clampf(minf(size.x, size.y) / 900.0, 0.6, 3.0)

## The grid line color setting.
##
## Returns: the Color.
func _grid_col() -> Color:
	return Settings.get_color("color_grid")

## Whether the current view is one of the two polar maps.
##
## Returns: true for north- or south-centered.
func _is_polar() -> bool:
	return view_type == Settings.VIEW_FLAT_NORTH or view_type == Settings.VIEW_FLAT_SOUTH

## The center of the control, in pixels.
##
## Returns: a Vector2.
func _center() -> Vector2:
	return size * 0.5

## The radius of the polar map: 39 percent of the smaller side, so the hour ring and the clock have room around it.
##
## Returns: pixels.
func _map_radius() -> float:
	return minf(size.x, size.y) * 0.39

## Where an object's shadow falls on the map: away from the Sun, longer for taller things. Shadows relate to the Sun's
## position, not to a scene light.
##
## [param p]: the object's position in pixels.
## [param height]: its height (in pixels at k = 1).
## Returns: the offset to add to [param p].
func _shadow_offset(p: Vector2, height: float) -> Vector2:
	var away := p - sun_picture_position()
	if away.length() < 1.0:
		away = Vector2(1.0, 1.0)
	return away.normalized() * height * _k()

## Where the Sun is, in picture pixels: above the sub-solar point on every flat map. FlatStage uses this to float the
## Sun above the map.
##
## Returns: a Vector2.
func sun_picture_position() -> Vector2:
	return project(_decl, _sub_lon)      # over the sub-solar point on every flat map

## The rectangle the rectangular map fills: as wide as fits (twice as wide as tall), centered, leaving room for
## labels.
##
## Returns: a Rect2 in pixels.
func _rect_map() -> Rect2:
	var w := minf(size.x * 0.97, (size.y - 130.0 * _k()) * 2.0)
	var h := w * 0.5
	return Rect2((size.x - w) * 0.5, (size.y - h) * 0.5 + 8.0, w, h)

## How far the polar map is turned for the current time: the map turns with the Earth beneath a fixed day/night mask.
##
## Returns: degrees, counter-clockwise.
func _map_rotation_ccw() -> float:
	if view_type == Settings.VIEW_FLAT_NORTH:
		return 180.0 - _sub_lon
	return _sub_lon

## Converts a place on the Earth to a position on the map.
##
## [param lat]: latitude in degrees.
## [param lon]: longitude in degrees.
## [param radius_scale]: for polar maps, multiplies the distance from the center, to push a point outward (default 1).
## Returns: pixel position. The reverse is [method pick].
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

## Converts a pixel position back to a place on the Earth (the inverse of [method project] for the current frame).
##
## [param p]: pixel position.
## Returns: {"hit": false} if outside the map, otherwise {"hit": true, "lat": ..., "lon": ...}.
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

## Draws the whole map: the picture and grid (polar or rectangular), earthquake regions, cities, points of interest,
## quakes, satellites and the Sun/Moon balls. In [member stage_mode] the 3D stage supplies some of these instead.
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
	_draw_solar_lunar_points()

## Draws the balls under the Sun (yellow) and Moon (blue) as discs with a glow, an outline and a highlight, sized from
## [constant SolarLunarMarker.MAP_FRACTION]. Each one follows its own setting. Skipped in [member stage_mode]
## (FlatStage draws them as 3D balls).
func _draw_solar_lunar_points() -> void:
	if stage_mode:
		return
	var width := _map_radius() * 2.0 if _is_polar() else _rect_map().size.x
	var r := width * SolarLunarMarker.MAP_FRACTION
	var now := Solar.now()
	var entries := []
	if SolarLunarMarker.sun_enabled():
		entries.append([SolarLunarMarker.sun_point(now), SolarLunarMarker.SUN_COLOR])
	if SolarLunarMarker.moon_enabled():
		entries.append([SolarLunarMarker.moon_point(now), SolarLunarMarker.MOON_COLOR])
	for entry in entries:
		var at: Vector2 = entry[0]
		var color: Color = entry[1]
		var p := project(at.x, at.y)
		draw_circle(p, r * 1.25, Color(color, 0.35))                       # a glow
		draw_circle(p, r, color)
		draw_arc(p, r, 0.0, TAU, 24, color.darkened(0.45), 1.5, true)
		draw_circle(p + Vector2(-0.3, -0.35) * r, r * 0.35, Color(1, 1, 1, 0.75))   # the highlight

## The opacity of the night shading, from the `night_darkness` setting (a little lighter than the table value).
##
## Returns: 0 to 1.
func _night_alpha() -> float:
	return float(Settings.NIGHT_ALPHA.get(Settings.get_string("night_darkness"), 0.4)) * 0.7   # lighter than before

## Draws a polar map: the picture turned with the Earth (or a dark circle until it loads), then the grid, hour labels
## and the Sun.
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

## Draws the polar map's grid: circles of latitude (equator, tropics, polar circles), the 24 hour meridians and the
## noon line, as the settings allow.
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

## The direction from the center toward the Sun's symbol: down on the north map, up on the south map.
##
## Returns: a unit Vector2.
func _sun_direction() -> Vector2:
	return Vector2(0, 1) if view_type == Settings.VIEW_FLAT_NORTH else Vector2(0, -1)

## Draws the 24 hour labels on a ring round the polar map (text outlined in black), flipped on the lower half so it
## stays readable. Skipped in [member stage_mode] (see [method hour_label_specs]). The label text depends on the
## `hour_type` setting.
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

## The hour labels as data, for FlatStage to build extruded 3D text from.
##
## Returns: an Array of {"text", "pos" (pixels, the center of the text), "rot" (radians, canvas rotation), "size"
##   (pixels)}; empty when hours are off. See [method _draw_polar_hours].
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

## The screen angle of a meridian for the current map rotation.
##
## [param lon]: longitude in degrees.
## Returns: counter-clockwise degrees.
func _angle_of_lon(lon: float) -> float:
	if view_type == Settings.VIEW_FLAT_NORTH:
		return 90.0 + lon + _map_rotation_ccw()
	return 90.0 - lon + _map_rotation_ccw()

## The screen angle of an hour label that is fixed to the Sun.
##
## [param k]: hours east of solar noon (0 to 23).
## Returns: counter-clockwise degrees.
func _noon_angle(k: int) -> float:
	if view_type == Settings.VIEW_FLAT_NORTH:
		return 270.0 + 15.0 * k
	return 90.0 - 15.0 * k

## Draws the Sun picture at the rim of the polar map, if the Sun is shown. Skipped in [member stage_mode].
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

## Draws the rectangular map: background, sea, picture, grid, the Sun at the sub-solar point with the noon meridian,
## and the hour labels along the bottom edge.
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

## Draws the cities chosen by [method CityDB.filtered_cities] (a shadowed dot, and the name in a day or night color).
## Only the names in [member stage_mode], where cities are 3D shapes.
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

## Draws the user's and built-in points of interest as colored diamonds with their names, if the `show_user_pois`
## setting is on.
func _draw_pois() -> void:
	if not Settings.get_bool("show_user_pois"):
		return
	for poi in CityDB.all_pois():
		var p := project(poi["Latitude"], poi["Longitude"])
		var col := Color(str(poi.get("Color", "#ee44cc")))
		var d := 6.0 * _k()
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0)]), col)
		draw_string(_font, p + Vector2(d + 3, 4) * 1.0, str(poi["Name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * _k()), col)

## Draws the enabled earthquake regions as colored rectangles (following the map's curvature on the polar maps).
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

## Draws a polyline on the rectangular map, skipping any segment that jumps across the antimeridian (the edge of the
## map), so no line is drawn across the whole picture.
##
## [param pts]: the points in pixels.
## [param col]: the color.
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

## Draws the earthquakes: for recent ones (within 24 hours) the "Arrow and Ring" or a radiating ring depending on the
## `quake_indicator` setting, a shadowed colored disc sized by magnitude (not in [member stage_mode]), and the
## magnitude number.
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

## Draws the still "Arrow and Ring" marker: a ring round the spot and a down-pointing arrow above it, both growing
## with the magnitude.
##
## [param p]: the quake's position in pixels.
## [param mag]: its magnitude.
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

## Draws every tracked satellite ([method SatelliteService.positions]): a shadow, the satellite turned along its track
## and a label with its name and altitude. Skipped in [member stage_mode] (satellites are 3D models there).
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

## Draws one satellite (or its shadow): a pill-shaped body with two solar panels, turned to a heading.
##
## [param p]: position in pixels.
## [param heading]: rotation in radians along the track.
## [param shadow]: true to draw a dark translucent silhouette instead.
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

## Mouse handling: movement reports the place under the mouse ([signal hover_changed]); a right click or double click
## on the map emits [signal location_clicked].
##
## [param event]: the input event.
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

## When the mouse leaves the control, tells listeners it is no longer over the map.
##
## [param what]: the notification constant.
func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		hover_changed.emit(0.0, 0.0, false)
