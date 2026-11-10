extends Window
## Debugger window (Flatland's debug panels): clock control, sun data, and runtime statistics.

var _sun_grid: GridContainer
var _perf_grid: GridContainer
var _year: SpinBox
var _month: SpinBox
var _day: SpinBox
var _hour: SpinBox
var _minute: SpinBox
var _timer: Timer

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

func _clock_tab(tabs: TabContainer) -> void:
	var p := SettingControls.page(tabs, "Clock")
	var l := Label.new()
	l.text = "Show Flatland at any moment, or run time faster. All views follow this clock."
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(l)
	var row := HBoxContainer.new()
	_year = _spin(row, "Year", 1900, 2200, 2026)
	_month = _spin(row, "Month", 1, 12, 1)
	_day = _spin(row, "Day", 1, 31, 1)
	_hour = _spin(row, "UTC hour", 0, 23, 12)
	_minute = _spin(row, "Minute", 0, 59, 0)
	p.add_child(row)
	var apply := HBoxContainer.new()
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
	var sp := HBoxContainer.new()
	var sl := Label.new()
	sl.text = "Speed"
	sp.add_child(sl)
	var ob := OptionButton.new()
	for pair in [["Real time", 1.0], ["60x (1 min/s)", 60.0], ["600x", 600.0], ["3600x (1 hour/s)", 3600.0], ["86400x (1 day/s)", 86400.0]]:
		ob.add_item(pair[0])
		ob.set_item_metadata(ob.item_count - 1, pair[1])
	ob.item_selected.connect(func(i: int) -> void:
		Solar.set_clock(Solar.now(), float(ob.get_item_metadata(i)))
		_nudge())
	sp.add_child(ob)
	p.add_child(sp)
	var presets := HBoxContainer.new()
	for pair in [["March equinox", 3, 20], ["June solstice", 6, 21], ["September equinox", 9, 22], ["December solstice", 12, 21]]:
		var b := Button.new()
		b.text = pair[0]
		b.pressed.connect(func() -> void:
			_month.value = pair[1]
			_day.value = pair[2]
			_apply_time())
		presets.add_child(b)
	p.add_child(presets)

func _spin(row: HBoxContainer, text: String, lo: int, hi: int, val: int) -> SpinBox:
	var l := Label.new()
	l.text = text
	row.add_child(l)
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = val
	row.add_child(s)
	return s

func _apply_time() -> void:
	var unix := Time.get_unix_time_from_datetime_dict({"year": int(_year.value), "month": int(_month.value),
		"day": int(_day.value), "hour": int(_hour.value), "minute": int(_minute.value), "second": 0})
	Solar.set_clock(float(unix), Solar.time_scale)
	_nudge()

func _nudge() -> void:
	Settings.set_value("debug_time_tick", int(Time.get_ticks_msec()))

func _sun_tab(tabs: TabContainer) -> void:
	var p := SettingControls.page(tabs, "Sun")
	_sun_grid = GridContainer.new()
	_sun_grid.columns = 2
	_sun_grid.add_theme_constant_override("h_separation", 30)
	p.add_child(_sun_grid)

func _perf_tab(tabs: TabContainer) -> void:
	var p := SettingControls.page(tabs, "Performance")
	_perf_grid = GridContainer.new()
	_perf_grid.columns = 2
	_perf_grid.add_theme_constant_override("h_separation", 30)
	p.add_child(_perf_grid)

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

func _refresh() -> void:
	if not visible:
		return
	var now := Solar.now()
	var d := Time.get_datetime_dict_from_unix_time(int(now))
	_fill(_sun_grid, [
		["Simulated UTC", "%04d-%02d-%02d %02d:%02d:%02d" % [d["year"], d["month"], d["day"], d["hour"], d["minute"], d["second"]]],
		["Clock speed", "%gx" % Solar.time_scale],
		["Declination", "%.3f°" % Solar.declination(now)],
		["Equation of time", "%.2f min" % Solar.equation_of_time(now)],
		["Sub-solar longitude", "%.3f°" % Solar.subsolar_longitude(now)],
		["Day of year fraction", "%.4f" % Solar.day_fraction(now)],
	])
	_fill(_perf_grid, [
		["Frames per second", Engine.get_frames_per_second()],
		["Static memory", "%.1f MB" % (OS.get_static_memory_usage() / 1048576.0)],
		["Objects in scene", int(Performance.get_monitor(Performance.OBJECT_COUNT))],
		["Nodes", int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))],
		["Draw calls", int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))],
		["Video memory", "%.1f MB" % (Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0)],
		["Earthquakes (feed / shown)", "%d / %d" % [QuakeService.quakes.size(), QuakeService.visible_quakes().size()]],
		["Satellite map", MapCatalog.satellite_status],
	])
