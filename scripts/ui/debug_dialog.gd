extends Window
## Debugger window (Flatland's debug panels): clock control, sun data, and runtime statistics.

## Grid of label/value pairs on the Sun tab (refreshed twice a second).
var _sun_grid: GridContainer
## Grid of label/value pairs on the Performance tab.
var _perf_grid: GridContainer
## Number box for the year of the clock to set.
var _year: SpinBox
## Number box for the month.
var _month: SpinBox
## Number box for the day.
var _day: SpinBox
## Number box for the UTC hour.
var _hour: SpinBox
## Number box for the minute.
var _minute: SpinBox
## Half-second timer that calls [method _refresh].
var _timer: Timer

## Builds the window: Clock, Sun and Performance tabs, a "Show debug text grid" check box, a Close button, and the
## refresh timer.
func _ready() -> void:
	title = "Flatland Debugger"
	size = Vector2i(780, 440)
	exclusive = false
	transient = true
	close_requested.connect(hide)
	var root := PanelContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var vb := VBoxContainer.new()
	root.add_child(vb)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(tabs)
	_clock_tab(tabs)
	_sun_tab(tabs)
	_perf_tab(tabs)
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_END
	bar.add_child(SettingControls.check("Show debug text grid", "show_debug_grid"))
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(hide)
	bar.add_child(close)
	vb.add_child(bar)
	_timer = Timer.new()
	_timer.wait_time = 0.5
	_timer.autostart = true
	_timer.timeout.connect(_refresh)
	add_child(_timer)

## Builds the Clock tab: date and time boxes with Set Time and Back to Live, a speed chooser ([constant SPEEDS]) and
## season presets ([constant PRESETS]). It changes [Solar]'s clock, which every view follows.
##
## [param tabs]: the TabContainer to add the page to.
func _clock_tab(tabs: TabContainer) -> void:
	var p := SettingControls.page(tabs, "Clock")
	var l := Label.new()
	l.text = "Show Flatland at any moment, or run time faster. All views follow this clock."
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(l)
	var row := PhoneSheet.button_bar()
	_year = _spin(row, "Year", 1900, 2200, 2026)
	_month = _spin(row, "Month", 1, 12, 1)
	_day = _spin(row, "Day", 1, 31, 1)
	_hour = _spin(row, "UTC hour", 0, 23, 12)
	_minute = _spin(row, "Minute", 0, 59, 0)
	p.add_child(row)
	var apply := PhoneSheet.button_bar()
	var set_btn := Button.new()
	set_btn.text = "Set Time"
	set_btn.pressed.connect(_apply_time)
	apply.add_child(set_btn)
	var now_btn := Button.new()
	now_btn.text = "Back to Live"
	now_btn.pressed.connect(func() -> void:
		Solar.reset_clock()
		_nudge())
	apply.add_child(now_btn)
	p.add_child(apply)
	var sp := PhoneSheet.button_bar()
	var sl := Label.new()
	sl.text = "Speed"
	sp.add_child(sl)
	var ob := OptionButton.new()
	for pair in SPEEDS:
		ob.add_item(pair[0])
		ob.set_item_metadata(ob.item_count - 1, pair[1])
	ob.item_selected.connect(func(i: int) -> void:
		Solar.set_clock(Solar.now(), float(ob.get_item_metadata(i)))
		_nudge())
	sp.add_child(ob)
	p.add_child(sp)
	var presets := PhoneSheet.button_bar()
	for pair in PRESETS:
		var b := Button.new()
		b.text = pair[0]
		b.pressed.connect(func() -> void:
			_month.value = pair[1]
			_day.value = pair[2]
			_apply_time())
		presets.add_child(b)
	p.add_child(presets)

## Adds a labeled whole-number box to a row.
##
## [param row]: the container to add to.
## [param text]: the label.
## [param lo]: smallest value.
## [param hi]: largest value.
## [param val]: starting value.
## Returns: the SpinBox.
func _spin(row: Container, text: String, lo: int, hi: int, val: int) -> SpinBox:
	var l := Label.new()
	l.text = text
	row.add_child(l)
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = val
	row.add_child(s)
	return s

## Sets the app's clock to the date and time in the boxes (keeping the current speed) and notifies the views with
## [method _nudge].
func _apply_time() -> void:
	var unix := Time.get_unix_time_from_datetime_dict({"year": int(_year.value), "month": int(_month.value),
		"day": int(_day.value), "hour": int(_hour.value), "minute": int(_minute.value), "second": 0})
	Solar.set_clock(float(unix), Solar.time_scale)
	_nudge()

## Tells the views the clock was changed: it writes the current tick count to the `debug_time_tick` setting, whose
## change signal makes GlobeView and others re-read the time.
func _nudge() -> void:
	Settings.set_value("debug_time_tick", int(Time.get_ticks_msec()))

## Builds the Sun tab: an empty grid that [method _refresh] fills.
##
## [param tabs]: the TabContainer to add the page to.
func _sun_tab(tabs: TabContainer) -> void:
	var p := SettingControls.page(tabs, "Sun")
	_sun_grid = GridContainer.new()
	_sun_grid.columns = 2
	_sun_grid.add_theme_constant_override("h_separation", 30)
	p.add_child(_sun_grid)

## Builds the Performance tab: an empty grid that [method _refresh] fills.
##
## [param tabs]: the TabContainer to add the page to.
func _perf_tab(tabs: TabContainer) -> void:
	var p := SettingControls.page(tabs, "Performance")
	_perf_grid = GridContainer.new()
	_perf_grid.columns = 2
	_perf_grid.add_theme_constant_override("h_separation", 30)
	p.add_child(_perf_grid)

## Replaces the contents of a grid with heading/value labels.
##
## [param grid]: the GridContainer.
## [param rows]: an Array of [heading, value] pairs.
func _fill(grid: GridContainer, rows: Array) -> void:
	for c in grid.get_children():
		c.queue_free()
	for row in rows:
		var a := Label.new()
		a.text = row[0]
		a.add_theme_color_override("font_color", Color("#8fb8ff"))
		var b := Label.new()
		b.text = str(row[1])
		grid.add_child(a)
		grid.add_child(b)

## The Sun tab's rows: simulated UTC, clock speed, declination, equation of time, sub-solar longitude and day
## fraction, from [Solar].
##
## Returns: an Array of [heading, value] pairs.
func _sun_rows() -> Array:
	var now := Solar.now()
	var d := Time.get_datetime_dict_from_unix_time(int(now))
	return [
		["Simulated UTC", "%04d-%02d-%02d %02d:%02d:%02d" % [d["year"], d["month"], d["day"], d["hour"], d["minute"], d["second"]]],
		["Clock speed", String.num(Solar.time_scale) + "x"],
		["Declination", "%.3f°" % Solar.declination(now)],
		["Equation of time", "%.2f min" % Solar.equation_of_time(now)],
		["Sub-solar longitude", "%.3f°" % Solar.subsolar_longitude(now)],
		["Day of year fraction", "%.4f" % Solar.day_fraction(now)],
	]

## The Performance tab's rows: frames per second, memory, object and node counts, draw calls, video memory, earthquake
## counts and satellite map status.
##
## Returns: an Array of [heading, value] pairs.
func _perf_rows() -> Array:
	return [
		["Frames per second", Engine.get_frames_per_second()],
		["Static memory", "%.1f MB" % (OS.get_static_memory_usage() / 1048576.0)],
		["Objects in scene", int(Performance.get_monitor(Performance.OBJECT_COUNT))],
		["Nodes", int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))],
		["Draw calls", int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))],
		["Video memory", "%.1f MB" % (Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0)],
		["Earthquakes (feed / shown)", "%d / %d" % [QuakeService.quakes.size(), QuakeService.visible_quakes().size()]],
		["Satellite map", MapCatalog.satellite_status],
	]

## Called twice a second: refreshes the native screen if it is showing, otherwise refills both grids if the window is
## visible.
func _refresh() -> void:
	if NativeUI.is_showing(self):
		NativeUI.refresh(self)
		return
	if not visible:
		return
	_fill(_sun_grid, _sun_rows())
	_fill(_perf_grid, _perf_rows())

# MARK: - Native (SwiftUI) version; see NativeUI

## The clock speeds to choose from: [label, speed factor]. 1.0 is real time, 86400.0 runs a day each second.
const SPEEDS := [["Real time", 1.0], ["60x (1 min/s)", 60.0], ["600x", 600.0], ["3600x (1 hour/s)", 3600.0], ["86400x (1 day/s)", 86400.0]]
## Buttons that jump to a season: [label, month, day] for the equinoxes and solstices.
const PRESETS := [["March equinox", 3, 20], ["June solstice", 6, 21], ["September equinox", 9, 22], ["December solstice", 12, 21]]

## The clock fields being edited in the native screen ("dbg_year", "dbg_month", "dbg_day", "dbg_hour", "dbg_minute").
## They are not Settings, so they are kept here until Set Time is pressed; emptied when the screen closes.
var _nv: Dictionary = {}

## Fills [member _nv] from the app's current clock, so the native screen starts with the time now showing.
func _seed_native() -> void:
	var d := Time.get_datetime_dict_from_unix_time(int(Solar.now()))
	_nv = {"dbg_year": d["year"], "dbg_month": d["month"], "dbg_day": d["day"], "dbg_hour": d["hour"], "dbg_minute": d["minute"]}

## Describes the dialog for the native UI: pages for Clock (with date/time fields, Set Time, Back to Live, speed,
## presets and the debug grid toggle), Sun and Performance.
##
## Returns: {"screen": ..., "values": {...}}.
func native_screen() -> Dictionary:
	if _nv.is_empty():
		_seed_native()
	var speeds: Array = []
	for s in SPEEDS:
		speeds.append({"label": s[0], "value": s[1]})
	var clock: Array = [
		{"type": "paragraph", "title": "Show Flatland at any moment, or run time faster. All views follow this clock."},
		{"type": "section", "title": "Date and Time (UTC)"},
		{"type": "number", "key": "dbg_year", "title": "Year", "min": 1900, "max": 2200, "step": 1},
		{"type": "number", "key": "dbg_month", "title": "Month", "min": 1, "max": 12, "step": 1},
		{"type": "number", "key": "dbg_day", "title": "Day", "min": 1, "max": 31, "step": 1},
		{"type": "number", "key": "dbg_hour", "title": "Hour", "min": 0, "max": 23, "step": 1},
		{"type": "number", "key": "dbg_minute", "title": "Minute", "min": 0, "max": 59, "step": 1},
		{"type": "action", "id": "set_time", "title": "Set Time", "style": "prominent"},
		{"type": "action", "id": "live", "title": "Back to Live"},
		{"type": "section", "title": "Speed"},
		{"type": "choice", "key": "dbg_speed", "title": "Speed", "options": speeds},
		{"type": "section", "title": "Presets"}]
	for i in PRESETS.size():
		clock.append({"type": "action", "id": "preset_%d" % i, "title": PRESETS[i][0]})
	clock.append({"type": "section", "title": "Display"})
	clock.append({"type": "toggle", "key": "show_debug_grid", "title": "Show debug text grid"})
	var sun: Array = []
	for row in _sun_rows():
		sun.append({"type": "info", "title": row[0], "detail": str(row[1])})
	var perf: Array = []
	for row in _perf_rows():
		perf.append({"type": "info", "title": row[0], "detail": str(row[1])})
	var values := _nv.duplicate()
	values["dbg_speed"] = Solar.time_scale
	values["show_debug_grid"] = Settings.get_bool("show_debug_grid")
	return {"screen": {"title": "Flatland Debugger", "pages": [
		{"title": "Clock", "items": clock}, {"title": "Sun", "items": sun}, {"title": "Performance", "items": perf}]}, "values": values}

## Handles native events: "dbg_speed" changes the clock speed, other "dbg_*" values update [member _nv], other values
## are stored as settings; actions run Set Time, Back to Live or a preset; "closed" clears [member _nv].
##
## [param kind]: "value", "action" or "closed".
## [param key]: the control or button id.
## [param value]: the new value for "value" events.
func native_event(kind: String, key: String, value: Variant) -> void:
	match kind:
		"value":
			if key == "dbg_speed":
				Solar.set_clock(Solar.now(), float(value))
				_nudge()
			elif key.begins_with("dbg_"):
				_nv[key] = int(value)
			else:
				NativeUI.store_setting(key, value)
		"action":
			if key == "set_time":
				_apply_native_time()
			elif key == "live":
				Solar.reset_clock()
				_nudge()
				_seed_native()
				NativeUI.refresh(self)
			elif key.begins_with("preset_"):
				var p: Array = PRESETS[int(key.substr(7))]
				_nv["dbg_month"] = p[1]
				_nv["dbg_day"] = p[2]
				_apply_native_time()
		"closed":
			_nv = {}

## Sets the app's clock from the native screen's fields ([member _nv]), keeping the speed, notifies the views and
## refreshes the screen.
func _apply_native_time() -> void:
	var unix := Time.get_unix_time_from_datetime_dict({"year": int(_nv["dbg_year"]), "month": int(_nv["dbg_month"]),
		"day": int(_nv["dbg_day"]), "hour": int(_nv["dbg_hour"]), "minute": int(_nv["dbg_minute"]), "second": 0})
	Solar.set_clock(float(unix), Solar.time_scale)
	_nudge()
	NativeUI.refresh(self)
