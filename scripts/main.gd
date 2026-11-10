extends Control
## Main window: the counterpart of Flatland's MainController. Hosts the 3D globe and the flat
## view, the time label, toolbar, menu bar, status bar and all dialogs. All UI is Godot UI.

const ICON_DIR := "res://Assets/Icons/"
const APP_VERSION := "1.0 (Godot)"
const TOOLBAR_HEIGHT := 60

## Height taken by an in-window menu bar (zero on macOS, which uses the native menu bar).
func _menu_height() -> int:
	return 0 if DisplayServer.has_feature(DisplayServer.FEATURE_GLOBAL_MENU) else 28

var _content: Control
var _toolbar_bar: PanelContainer
var _globe_container: SubViewportContainer
var _globe_viewport: SubViewport
var _globe: Node3D
var _flat: Control
var _time_label: Label
var _status: PanelContainer
var _toolbar: HBoxContainer
var _menu_bar: MenuBar
var _debug_grid: GridContainer
var _debug_values: Dictionary = {}
var _view_buttons: Dictionary = {}
var _lock_button: Button
var _prefs: Window
var _about: Window
var _times: Window
var _quake_list: Window
var _live_status: Window
var _locations: Window
var _regions: Window
var _debugger: Window
var _bg: ColorRect
var _snapshot_dialog: FileDialog
var _whats_here: PopupPanel
var _whats_here_label: RichTextLabel
var _hours_menu: PopupMenu
var _view_menu: PopupMenu
var _start_msec := Time.get_ticks_msec()
var _sounds: Dictionary = {}
var _player: AudioStreamPlayer
var _open_on_start := ""
var _resize_to := ""
var _cam_args := PackedFloat64Array()
var _shot_path := ""
var _shot_frames := 0

func _ready() -> void:
	_parse_command_line()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg = ColorRect.new()
	_bg.color = Settings.get_color("color_background")
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	_content = Control.new()
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.offset_top = TOOLBAR_HEIGHT + _menu_height()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	_build_views()
	_build_overlays()
	_build_menu_bar()
	_build_toolbar()
	_build_dialogs()
	_player = AudioStreamPlayer.new()
	add_child(_player)
	Settings.changed.connect(_on_setting_changed)
	QuakeService.new_quake.connect(_on_new_quake)
	QuakeService.fetch_started.connect(func() -> void:
		if QuakeService.fetch_count == 0:
			_status.post("Refreshing earthquake data.", 4.0))
	QuakeService.fetch_failed.connect(func(reason: String) -> void: _status.post("Earthquake data: " + reason, 5.0))
	_apply_view_type()
	_update_debug_grid()
	if _cam_args.size() == 3:
		_globe.set_camera(_cam_args[0], _cam_args[1], _cam_args[2])
	if _open_on_start != "":
		call_deferred("_open_for_test", _open_on_start)
	var t := Timer.new()
	t.wait_time = 1.0
	t.autostart = true
	t.timeout.connect(_update_debug_grid)
	add_child(t)

## Development hooks: `-- --time=<unix>` shows another moment, `-- --view=<type>` starts in a view.
func _parse_command_line() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--time="):
			Solar.time_offset = float(arg.substr(7)) - Time.get_unix_time_from_system()
		elif arg.begins_with("--view="):
			Settings.override("view_type", arg.substr(7))
		elif arg.begins_with("--map="):
			Settings.override("map_type", arg.substr(6))
		elif arg.begins_with("--shot="):
			_shot_path = arg.substr(7)
			_shot_frames = 150
		elif arg.begins_with("--set="):
			var kv := arg.substr(6).split("=", true, 1)
			if kv.size() == 2:
				var cur: Variant = Settings.get_value(kv[0])
				Settings.override(kv[0], int(kv[1]) if cur is int else (float(kv[1]) if cur is float else (kv[1] == "true" if cur is bool else kv[1])))
		elif arg.begins_with("--cam="):
			_cam_args = arg.substr(6).split_floats(",")
		elif arg.begins_with("--resize="):
			_resize_to = arg.substr(9)
		elif arg.begins_with("--open="):
			_open_on_start = arg.substr(7)
		elif arg.begins_with("--hours="):
			Settings.override("hour_type", arg.substr(8))

# MARK: - Construction

func _build_views() -> void:
	_globe_container = SubViewportContainer.new()
	_globe_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_globe_container.stretch = true
	_globe_container.mouse_filter = Control.MOUSE_FILTER_PASS
	_content.add_child(_globe_container)
	_globe_viewport = SubViewport.new()
	_globe_viewport.msaa_3d = Viewport.MSAA_4X
	_globe_viewport.handle_input_locally = true
	_globe_viewport.gui_disable_input = false
	_globe_container.add_child(_globe_viewport)
	_globe = load("res://scripts/views/globe_view.gd").new()
	_globe_viewport.add_child(_globe)
	_globe.hover_changed.connect(_on_hover)
	_globe.location_clicked.connect(_on_location_clicked)
	_globe_container.gui_input.connect(_globe.handle_gui_input)
	_globe_container.mouse_entered.connect(_globe.set_mouse_inside.bind(true))
	_globe_container.mouse_exited.connect(func() -> void:
		_globe.set_mouse_inside(false)
		_on_hover(0.0, 0.0, false))
	_flat = load("res://scripts/views/flat_view.gd").new()
	_flat.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flat.hover_changed.connect(_on_hover)
	_flat.location_clicked.connect(_on_location_clicked)
	_content.add_child(_flat)

func _build_overlays() -> void:
	_time_label = load("res://scripts/ui/time_label.gd").new()
	_time_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_time_label.offset_top = 8
	_time_label.offset_bottom = 72
	_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_time_label)

	_status = load("res://scripts/ui/status_bar.gd").new()
	_status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status.anchor_left = 0.04
	_status.anchor_right = 0.96
	_status.offset_top = -56
	_status.offset_bottom = -12
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_status)

	# Debug text grid (Version / Build / Uptime / Memory), shown in the lower left.
	_debug_grid = GridContainer.new()
	_debug_grid.columns = 2
	_debug_grid.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_debug_grid.offset_left = 16
	_debug_grid.offset_top = -190
	_debug_grid.offset_bottom = -64
	_debug_grid.offset_right = 260
	_debug_grid.add_theme_constant_override("h_separation", 40)
	_debug_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for row in ["Version", "Build", "Build date", "Uptime", "Memory Used"]:
		var a := Label.new()
		a.text = row
		a.add_theme_font_size_override("font_size", 15)
		var b := Label.new()
		b.add_theme_font_size_override("font_size", 15)
		_debug_grid.add_child(a)
		_debug_grid.add_child(b)
		_debug_values[row] = b
	_content.add_child(_debug_grid)
	_debug_grid.visible = Settings.get_bool("show_debug_grid")

	_whats_here = PopupPanel.new()
	_whats_here_label = RichTextLabel.new()
	_whats_here_label.bbcode_enabled = true
	_whats_here_label.fit_content = true
	_whats_here_label.custom_minimum_size = Vector2(320, 0)
	_whats_here_label.scroll_active = false
	_whats_here.add_child(_whats_here_label)
	_content.add_child(_whats_here)

func _build_menu_bar() -> void:
	_menu_bar = MenuBar.new()
	_menu_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_menu_bar.offset_bottom = 28
	_menu_bar.prefer_global_menu = true
	add_child(_menu_bar)

	var file := PopupMenu.new()
	file.name = "File"
	file.add_item("Take Snapshot…", 1)
	file.add_separator()
	file.add_item("Preferences…", 2)
	file.add_separator()
	file.add_item("Quit", 3)
	file.id_pressed.connect(_on_file_menu)
	_menu_bar.add_child(file)

	_view_menu = PopupMenu.new()
	_view_menu.name = "View"
	_view_menu.add_radio_check_item("3D Globe", 0)
	_view_menu.add_radio_check_item("Flat – North Centered", 1)
	_view_menu.add_radio_check_item("Flat – South Centered", 2)
	_view_menu.add_radio_check_item("Rectangular", 3)
	_view_menu.add_radio_check_item("Cubic World", 4)
	_view_menu.add_separator()
	_view_menu.add_item("Select Map…", 10)
	_view_menu.add_item("Reset View", 11)
	_view_menu.add_check_item("Lock World", 12)
	_view_menu.add_separator()
	_view_menu.add_check_item("Show Night", 13)
	_view_menu.add_check_item("Show Cities", 14)
	_view_menu.add_check_item("Show Status Bar", 15)
	_view_menu.id_pressed.connect(_on_view_menu)
	_menu_bar.add_child(_view_menu)

	_hours_menu = PopupMenu.new()
	_hours_menu.name = "Hours"
	var hour_items := [["No Hours", Settings.HOURS_NONE], ["Solar Time", Settings.HOURS_SOLAR],
		["Relative to Noon", Settings.HOURS_NOON], ["Relative to Home Location", Settings.HOURS_LOCATION],
		["Wall Clock", Settings.HOURS_WALL]]
	for i in range(hour_items.size()):
		_hours_menu.add_radio_check_item(hour_items[i][0], i)
	_hours_menu.id_pressed.connect(func(id: int) -> void: Settings.set_value("hour_type", hour_items[id][1]))
	_menu_bar.add_child(_hours_menu)

	var quakes := PopupMenu.new()
	quakes.name = "Earthquakes"
	quakes.add_item("Earthquake List…", 1)
	quakes.add_item("Refresh Earthquakes", 2)
	quakes.add_check_item("Show Earthquakes", 3)
	quakes.add_separator()
	quakes.add_item("Live Data Status…", 4)
	quakes.id_pressed.connect(_on_quake_menu)
	quakes.about_to_popup.connect(func() -> void: quakes.set_item_checked(2, Settings.get_bool("enable_earthquakes")))
	_menu_bar.add_child(quakes)

	var tools := PopupMenu.new()
	tools.name = "Tools"
	tools.add_item("Today's Times…", 1)
	tools.add_item("My Locations…", 6)
	tools.add_item("Earthquake Regions…", 7)
	tools.add_item("Debugger…", 8)
	tools.add_check_item("Show Mouse Coordinates", 2)
	tools.add_check_item("Attract Mode", 3)
	tools.add_separator()
	tools.add_check_item("Show Debug Information", 4)
	tools.add_item("Reset Settings", 5)
	tools.id_pressed.connect(_on_tools_menu)
	tools.about_to_popup.connect(func() -> void:
		tools.set_item_checked(tools.get_item_index(2), Settings.get_bool("mouse_tracking"))
		tools.set_item_checked(tools.get_item_index(3), Settings.get_bool("attract_mode"))
		tools.set_item_checked(tools.get_item_index(4), Settings.get_bool("show_debug_grid")))
	_menu_bar.add_child(tools)

	var help := PopupMenu.new()
	help.name = "Help"
	help.add_item("About Flatland…", 1)
	help.id_pressed.connect(func(_id: int) -> void: _action_about())
	_menu_bar.add_child(help)

	_view_menu.about_to_popup.connect(_refresh_menu_checks)
	_hours_menu.about_to_popup.connect(_refresh_menu_checks)

func _toggle(key: String) -> void:
	Settings.set_value(key, not Settings.get_bool(key))

func _on_file_menu(id: int) -> void:
	match id:
		1: _action_snapshot()
		2: _action_preferences()
		3: get_tree().quit()

func _on_view_menu(id: int) -> void:
	var types := [Settings.VIEW_GLOBE, Settings.VIEW_FLAT_NORTH, Settings.VIEW_FLAT_SOUTH, Settings.VIEW_RECT, Settings.VIEW_CUBIC]
	if id < 5:
		Settings.set_value("view_type", types[id])
		return
	match id:
		10: _action_select_map()
		11: _action_reset_view()
		12: _toggle("world_locked")
		13: _toggle("show_night")
		14: _toggle("show_cities")
		15: _toggle("show_status_bar")

func _on_quake_menu(id: int) -> void:
	match id:
		1: _action_quake_list()
		2:
			QuakeService.refresh()
			_status.post("Refreshing earthquake data.", 4.0)
		3: _toggle("enable_earthquakes")
		4: _action_live_status()

func _on_tools_menu(id: int) -> void:
	match id:
		1: _action_times()
		2: _toggle("mouse_tracking")
		3: _toggle("attract_mode")
		4: _toggle("show_debug_grid")
		5: Settings.reset_all()
		6: _popup(_locations)
		7: _popup(_regions)
		8: _popup(_debugger)

func _refresh_menu_checks() -> void:
	var types := [Settings.VIEW_GLOBE, Settings.VIEW_FLAT_NORTH, Settings.VIEW_FLAT_SOUTH, Settings.VIEW_RECT, Settings.VIEW_CUBIC]
	for i in range(5):
		_view_menu.set_item_checked(i, types[i] == Settings.get_string("view_type"))
	_view_menu.set_item_checked(_view_menu.get_item_index(12), Settings.get_bool("world_locked"))
	_view_menu.set_item_checked(_view_menu.get_item_index(13), Settings.get_bool("show_night"))
	_view_menu.set_item_checked(_view_menu.get_item_index(14), Settings.get_bool("show_cities"))
	_view_menu.set_item_checked(_view_menu.get_item_index(15), Settings.get_bool("show_status_bar"))
	var hour_keys := [Settings.HOURS_NONE, Settings.HOURS_SOLAR, Settings.HOURS_NOON, Settings.HOURS_LOCATION, Settings.HOURS_WALL]
	for i in range(hour_keys.size()):
		_hours_menu.set_item_checked(i, hour_keys[i] == Settings.get_string("hour_type"))

func _icon_button(icon_name: String, label: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.icon = load(ICON_DIR + icon_name + ".png")
	b.expand_icon = true
	b.text = label
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.custom_minimum_size = Vector2(72, 50)
	b.add_theme_constant_override("icon_max_width", 24)
	b.add_theme_font_size_override("font_size", 11)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, Color(0.1, 0.1, 0.12))
	b.tooltip_text = tip
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	_toolbar.add_child(b)
	return b

## The window toolbar (Flatland uses an NSToolbar with icon-and-label items).
func _build_toolbar() -> void:
	_toolbar_bar = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#dcdde2")
	sb.border_color = Color("#a8a9ae")
	sb.border_width_bottom = 1
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	_toolbar_bar.add_theme_stylebox_override("panel", sb)
	_toolbar_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_toolbar_bar.offset_top = _menu_height()
	_toolbar_bar.offset_bottom = _menu_height() + TOOLBAR_HEIGHT
	add_child(_toolbar_bar)
	_toolbar = HBoxContainer.new()
	_toolbar.add_theme_constant_override("separation", 4)
	_toolbar_bar.add_child(_toolbar)
	_icon_button("InfoIcon", "About", "View information about Flatland.", _action_about)
	_icon_button("DebugIcon", "Debugger", "Open the debugger.", func() -> void: _popup(_debugger))
	_icon_button("LiveStatus", "Live Data", "See current live data status and statistics.", _action_live_status)
	_icon_button("GearIcon", "Preferences", "Change Flatland's settings.", _action_preferences)
	_lock_button = _icon_button("UnlockWorldIcon", "Lock", "Lock or unlock the world.", func() -> void:
		Settings.set_value("world_locked", not Settings.get_bool("world_locked")))
	_icon_button("ResetViewIcon", "Reset View", "Reset the 3D view.", _action_reset_view)
	_icon_button("CameraButtonUnpressed", "Snapshot", "Take a snapshot of the view.", _action_snapshot)
	_icon_button("EarthquakeIcon", "Earthquakes", "Show the list of earthquakes.", _action_quake_list)

func _build_dialogs() -> void:
	_prefs = load("res://scripts/ui/prefs_dialog.gd").new()
	_about = load("res://scripts/ui/about_dialog.gd").new()
	_times = load("res://scripts/ui/todays_times_dialog.gd").new()
	_quake_list = load("res://scripts/ui/quake_list_dialog.gd").new()
	_live_status = load("res://scripts/ui/live_status_dialog.gd").new()
	_locations = load("res://scripts/ui/locations_dialog.gd").new()
	_regions = load("res://scripts/ui/regions_dialog.gd").new()
	_debugger = load("res://scripts/ui/debug_dialog.gd").new()
	for w in [_prefs, _about, _times, _quake_list, _live_status, _locations, _regions, _debugger]:
		w.visible = false
		add_child(w)
	_quake_list.quake_chosen.connect(_on_quake_chosen)
	_snapshot_dialog = FileDialog.new()
	_snapshot_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_snapshot_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_snapshot_dialog.filters = PackedStringArray(["*.png ; PNG image"])
	_snapshot_dialog.title = "Save Snapshot"
	_snapshot_dialog.file_selected.connect(_save_snapshot)
	add_child(_snapshot_dialog)

# MARK: - Actions (names follow Flatland's IBActions)

func _popup(w: Window, size_hint: Vector2i = Vector2i.ZERO) -> void:
	if size_hint != Vector2i.ZERO:
		w.size = size_hint
	w.popup_centered()

func _action_preferences() -> void: _popup(_prefs)
func _action_about() -> void: _popup(_about)
func _action_times() -> void: _popup(_times)
func _action_quake_list() -> void: _popup(_quake_list)
func _action_live_status() -> void: _popup(_live_status)

func _action_select_map() -> void:
	_prefs.popup_centered()
	var tabs := _prefs.find_children("*", "TabContainer", true, false)
	if tabs.size() > 0:
		(tabs[0] as TabContainer).current_tab = 1

func _action_reset_view() -> void:
	_globe.reset_view()

func _action_snapshot() -> void:
	var d := Time.get_datetime_dict_from_system()
	_snapshot_dialog.current_file = "Flatland Snapshot %04d-%02d-%02d %02d.%02d.%02d.png" % [d["year"], d["month"], d["day"], d["hour"], d["minute"], d["second"]]
	var docs := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if docs != "":
		_snapshot_dialog.current_dir = docs
	_snapshot_dialog.popup_centered_ratio(0.6)

func _save_snapshot(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img.save_png(path) == OK:
		_status.post("Snapshot saved to " + path, 5.0)
	else:
		_status.post("Could not save the snapshot.", 5.0)

# MARK: - Events

func _on_setting_changed(key: String, _value: Variant) -> void:
	match key:
		"view_type":
			_apply_view_type()
		"world_locked":
			_lock_button.icon = load(ICON_DIR + ("LockWorldIcon" if Settings.get_bool("world_locked") else "UnlockWorldIcon") + ".png")
		"show_debug_grid":
			_debug_grid.visible = Settings.get_bool("show_debug_grid")
		"color_background":
			_bg.color = Settings.get_color("color_background")

func _apply_view_type() -> void:
	var view := Settings.get_string("view_type")
	var is_globe := view == Settings.VIEW_GLOBE or view == Settings.VIEW_CUBIC
	_globe_container.visible = is_globe
	_flat.visible = not is_globe
	if not is_globe:
		_flat.set_view(view)
	for key in _view_buttons.keys():
		var b: Button = _view_buttons[key]
		b.icon = b.get_meta("selected") if key == view else b.get_meta("normal")
	_lock_button.icon = load(ICON_DIR + ("LockWorldIcon" if Settings.get_bool("world_locked") else "UnlockWorldIcon") + ".png")
	# The time label sits opposite the sun: at the bottom for the south-centered map.
	if view == Settings.VIEW_FLAT_SOUTH:
		_time_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_time_label.offset_top = -126
		_time_label.offset_bottom = -62
		_status.visible = Settings.get_bool("show_status_bar")
	else:
		_time_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
		_time_label.offset_top = 8
		_time_label.offset_bottom = 72

func _on_hover(lat: float, lon: float, over: bool) -> void:
	if over:
		var city := CityDB.find_nearest(lat, lon, 150.0)
		var text := Geo.pretty_coordinates(lat, lon)
		if not city.is_empty():
			text += "   near " + str(city["Name"])
		_status.show_persistent(text)
	else:
		_status.show_persistent("")

func _on_location_clicked(lat: float, lon: float) -> void:
	CityDB.last_clicked = Vector2(lat, lon)
	var now := Solar.now()
	var lines: Array = ["[b]%s[/b]" % Geo.pretty_coordinates(lat, lon, 4)]
	var city := CityDB.find_nearest(lat, lon, 300.0)
	if not city.is_empty():
		lines.append("Nearest city: %s, %s" % [city["Name"], city.get("Country", "")])
	lines.append("Solar time: " + _solar_time(lon, now))
	lines.append("Sun: " + ("up (day)" if Solar.is_daylight(lat, lon, now) else "down (night)"))
	var r := Solar.sunrise_sunset(lat, lon, now)
	if r["status"] == "ok":
		lines.append("Sunrise %s UTC   Sunset %s UTC" % [_hm(r["sunrise"]), _hm(r["sunset"])])
	elif r["status"] == "polar_day":
		lines.append("Sun does not set today")
	else:
		lines.append("Sun does not rise today")
	_whats_here_label.text = "\n".join(lines)
	_whats_here.position = Vector2i(get_viewport().get_mouse_position()) + Vector2i(DisplayServer.window_get_position())
	_whats_here.reset_size()
	_whats_here.popup()

func _hm(unix: float) -> String:
	var d := Time.get_time_dict_from_unix_time(int(unix))
	return "%02d:%02d" % [d["hour"], d["minute"]]

func _solar_time(lon: float, unix: float) -> String:
	var secs := fposmod(unix + lon * 240.0 + Solar.equation_of_time(unix) * 60.0, 86400.0)
	return "%02d:%02d" % [int(secs / 3600.0), int(fposmod(secs, 3600.0) / 60.0)]

func _on_quake_chosen(lat: float, lon: float) -> void:
	if _globe_container.visible:
		_globe.look_at_location(lat, lon)

func _on_new_quake(q: Dictionary) -> void:
	if q["magnitude"] < Settings.get_float("quake_min_magnitude"):
		return
	var d := Time.get_datetime_dict_from_unix_time(int(q["time"]))
	_status.post("New quake: M %.1f - %s, %04d-%02d-%02d %02d:%02d:%02d GMT" % [q["magnitude"], q["place"],
		d["year"], d["month"], d["day"], d["hour"], d["minute"], d["second"]], 8.0)
	if Settings.get_bool("enable_sounds"):
		var file := Settings.get_string("quake_sound")
		if not _sounds.has(file):
			_sounds[file] = load("res://Assets/Sounds/" + file)
		if _sounds[file] != null:
			_player.stream = _sounds[file]
			_player.play()

func _update_debug_grid() -> void:
	if not _debug_grid.visible:
		return
	var up := (Time.get_ticks_msec() - _start_msec) / 1000
	_debug_values["Version"].text = "v" + APP_VERSION
	_debug_values["Build"].text = Engine.get_version_info()["string"]
	_debug_values["Build date"].text = "9 November 2026"
	_debug_values["Uptime"].text = "%d:%02d:%02d" % [up / 3600, (up % 3600) / 60, up % 60]
	_debug_values["Memory Used"].text = "%.2f GB" % (OS.get_static_memory_usage() / 1073741824.0)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_1: Settings.set_value("view_type", Settings.VIEW_GLOBE)
			KEY_2: Settings.set_value("view_type", Settings.VIEW_FLAT_NORTH)
			KEY_3: Settings.set_value("view_type", Settings.VIEW_FLAT_SOUTH)
			KEY_4: Settings.set_value("view_type", Settings.VIEW_RECT)
			KEY_5: Settings.set_value("view_type", Settings.VIEW_CUBIC)
			KEY_R: _action_reset_view()

func _process(_delta: float) -> void:
	if _resize_to != "" and _shot_frames == 100:
		var wh := _resize_to.split("x")
		get_window().size = Vector2i(int(wh[0]), int(wh[1]))
	if _shot_path != "":
		_shot_frames -= 1
		if _shot_frames <= 0:
			get_viewport().get_texture().get_image().save_png(_shot_path)
			_shot_path = ""
			get_tree().quit()

func _open_for_test(what: String) -> void:
	match what:
		"prefs": _action_preferences()
		"map": _action_select_map()
		"about": _action_about()
		"times": _action_times()
		"quakes": _action_quake_list()
		"live": _action_live_status()
		"debug": _popup(_debugger)
		"locations": _popup(_locations)
		"regions": _popup(_regions)
		"click": _on_location_clicked(35.0, -100.0)
