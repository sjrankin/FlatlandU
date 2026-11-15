extends Window
## Today's sunrise, solar noon and sunset for the home location or any city (Flatland's Today view).

## Drop-down of places: Home first, then every city by name.
var _city_opt: OptionButton
## Two-column grid of heading and value labels.
var _grid: GridContainer
## The cities in the drop-down, sorted by name; item id n (n > 0) is `_cities[n - 1]`.
var _cities: Array = []

## Builds the window: the place chooser, the grid of times and a Close button. Refreshes each time it opens.
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
	_city_opt.clip_text = true
	_city_opt.fit_to_longest_item = false   # the longest city name must not set the dialog's minimum width
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

## Formats a time of day.
##
## [param unix]: a Unix time (UTC).
## [param tz_hours]: hours to add (a time zone offset, 0 for UTC).
## Returns: "HH:MM".
func _fmt(unix: float, tz_hours: float) -> String:
	var d := Time.get_time_dict_from_unix_time(int(unix + tz_hours * 3600.0))
	return "%02d:%02d" % [d["hour"], d["minute"]]

## The rows of the table for the chosen place: location, nominal time zone, sunrise, solar noon and sunset (UTC and
## local solar time), length of day or a note for polar day/night, and whether the Sun is up now. Shared by the Godot
## and native screens. Uses [method Solar.sunrise_sunset].
##
## Returns: an Array of [heading, value] text pairs.
func _rows() -> Array:
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
	return rows

## Rebuilds the grid from [method _rows] and tells NativeUI the data changed.
func update_times() -> void:
	NativeUI.refresh(self)
	for c in _grid.get_children():
		c.queue_free()
	var rows := _rows()
	for row in rows:
		var a := Label.new()
		a.text = row[0]
		a.add_theme_color_override("font_color", Color("#8fb8ff"))
		var b := Label.new()
		b.text = row[1]
		if Layout.is_phone():
			# Long values (URLs, status text) wrap in the space beside the heading.
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.custom_minimum_size.x = 120
		_grid.add_child(a)
		_grid.add_child(b)

# MARK: - Native (SwiftUI) version; see NativeUI

## Describes this dialog for the native UI: a City choice, then an info row per [method _rows] entry.
##
## Returns: {"screen": ..., "values": {"city": id}}.
func native_screen() -> Dictionary:
	var options: Array = []
	for i in range(_city_opt.item_count):
		options.append({"label": _city_opt.get_item_text(i), "value": _city_opt.get_item_id(i)})
	var items: Array = [{"type": "choice", "key": "city", "title": "City", "options": options},
		{"type": "section", "title": "Today"}]
	for row in _rows():
		items.append({"type": "info", "title": row[0], "detail": row[1]})
	return {"screen": {"title": "Today's Times", "pages": [{"title": "Times", "items": items}]},
		"values": {"city": _city_opt.get_selected_id()}}

## Handles native events: choosing a city selects it and updates the times.
##
## [param kind]: "value", "action" or "closed".
## [param key]: the control key ("city").
## [param value]: the chosen item id.
func native_event(kind: String, key: String, value: Variant) -> void:
	if kind == "value" and key == "city":
		_city_opt.select(_city_opt.get_item_index(int(value)))
		update_times()
