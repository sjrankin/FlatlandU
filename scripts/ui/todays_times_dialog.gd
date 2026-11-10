extends Window
## Today's sunrise, solar noon and sunset for the home location or any city (Flatland's Today view).

var _city_opt: OptionButton
var _grid: GridContainer
var _cities: Array = []

func _ready() -> void:
	title = "Today's Times"
	size = Vector2i(520, 420)
	exclusive = false
	transient = true
	close_requested.connect(hide)
	var root := PanelContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	root.add_child(vb)
	_city_opt = OptionButton.new()
	_city_opt.add_item("Home: " + Settings.get_string("home_name"), 0)
	_cities = CityDB.cities.duplicate()
	_cities.sort_custom(func(a, b): return str(a["Name"]) < str(b["Name"]))
	for i in range(_cities.size()):
		_city_opt.add_item("%s, %s" % [_cities[i]["Name"], _cities[i].get("Country", "")], i + 1)
	_city_opt.item_selected.connect(func(_i: int) -> void: update_times())
	vb.add_child(_city_opt)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 24)
	_grid.add_theme_constant_override("v_separation", 8)
	vb.add_child(_grid)
	var close := Button.new()
	close.text = "Close"
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(hide)
	vb.add_child(close)
	about_to_popup.connect(update_times)
	update_times()

func _fmt(unix: float, tz_hours: float) -> String:
	var d := Time.get_time_dict_from_unix_time(int(unix + tz_hours * 3600.0))
	return "%02d:%02d" % [d["hour"], d["minute"]]

func update_times() -> void:
	for c in _grid.get_children():
		c.queue_free()
	var lat := Settings.get_float("home_latitude")
	var lon := Settings.get_float("home_longitude")
	var sel := _city_opt.get_selected_id()
	if sel > 0:
		lat = _cities[sel - 1]["Latitude"]
		lon = _cities[sel - 1]["Longitude"]
	var tz := roundf(lon / 15.0)
	var now := Solar.now()
	var r := Solar.sunrise_sunset(lat, lon, now)
	var rows: Array = [["Location", Geo.pretty_coordinates(lat, lon)], ["Time zone (nominal)", "UTC%+d" % int(tz)]]
	if r["status"] == "ok":
		rows.append(["Sunrise (UTC)", _fmt(r["sunrise"], 0.0)])
		rows.append(["Solar noon (UTC)", _fmt(r["noon"], 0.0)])
		rows.append(["Sunset (UTC)", _fmt(r["sunset"], 0.0)])
		rows.append(["Sunrise (local solar)", _fmt(r["sunrise"], tz)])
		rows.append(["Sunset (local solar)", _fmt(r["sunset"], tz)])
		var day_len: float = (r["sunset"] - r["sunrise"]) / 3600.0
		rows.append(["Length of day", "%d h %02d m" % [int(day_len), int((day_len - floor(day_len)) * 60.0)]])
	else:
		rows.append(["Sun", "Sun is up all day" if r["status"] == "polar_day" else "Sun does not rise today"])
	rows.append(["Sun now", "Above the horizon" if Solar.is_daylight(lat, lon, now) else "Below the horizon"])
	for row in rows:
		var a := Label.new()
		a.text = row[0]
		a.add_theme_color_override("font_color", Color("#8fb8ff"))
		var b := Label.new()
		b.text = row[1]
		_grid.add_child(a)
		_grid.add_child(b)
