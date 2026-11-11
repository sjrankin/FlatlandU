extends Control
## Main window: the counterpart of Flatland's MainController. Hosts the 3D globe and the flat
## view, the time label, toolbar, status bar and all dialogs. All UI is Godot UI.

const ICON_DIR := "res://Assets/Icons/"
const APP_VERSION := "1.0 (Godot)"
const TOOLBAR_HEIGHT := 60

## Height of the toolbar (scaled up on phones).
func _toolbar_height() -> int:
	return int(TOOLBAR_HEIGHT * Layout.ui_scale())

## The safe-area insets (camera cut-out, rounded corners, home indicator).
func _insets() -> Vector4:
	return Layout.safe_insets()

var _content: Control
var _toolbar_bar: PanelContainer
var _globe_container: SubViewportContainer
var _globe_viewport: SubViewport
var _globe: Node3D
var _flat: FlatStage
var _time_label: Label
var _star_tip: PanelContainer
var _star_tip_label: Label
var _star_tip_timer: Timer
var _star_tip_pos := Vector2.ZERO
var _welcome_button: Button
var _more_button: Button
var _more_menu: PopupMenu
var _fps_label: Label
var _fps_accum := 0.0
var _status: PanelContainer
var _toolbar: Container
var _toolbar_style: StyleBoxFlat
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
var _satellites: Window
var _debugger: Window
var _bg: ColorRect
var _snapshot_dialog: FileDialog
var _snapshot_image: Image          # captured when the Snapshot button is pressed, saved when the dialog is confirmed
var _whats_here: PopupPanel
var _whats_here_label: RichTextLabel
var _start_msec := Time.get_ticks_msec()
var _sounds: Dictionary = {}
var _player: AudioStreamPlayer
var _open_on_start := ""
var _resize_to := ""
var _native_snap := ""
var _cam_args := PackedFloat64Array()
var _shot_path := ""
var _shot_frames := 0

func _ready() -> void:
	_parse_command_line()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if Layout.is_phone():
		# Bigger default text for every label, button, menu and dialog on a phone.
		theme = PhoneTheme.build()
	_bg = ColorRect.new()
	_bg.color = Settings.get_color("color_background")
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	_content = Control.new()
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.offset_top = _insets().y if Layout.is_phone() else _toolbar_height() + _insets().y
	_content.offset_bottom = -(_toolbar_height() + _insets().w) if Layout.is_phone() else 0.0   # phones: toolbar at the bottom
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	_build_views()
	_build_overlays()
	_build_toolbar()
	_build_dialogs()
	_player = AudioStreamPlayer.new()
	add_child(_player)
	Settings.changed.connect(_on_setting_changed)
	QuakeService.new_quake.connect(_on_new_quake)
	QuakeService.biggest_new_quake.connect(_on_biggest_new_quake)
	QuakeService.fetch_started.connect(func() -> void:
		if QuakeService.fetch_count == 0:
			_status.post("Refreshing earthquake data.", 4.0))
	QuakeService.fetch_failed.connect(func(reason: String) -> void: _status.post("Earthquake data: " + reason, 5.0))
	_apply_view_type()
	_update_debug_grid()
	get_window().size_changed.connect(_relayout)   # the safe area changes when a phone is rotated
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
		elif arg.begins_with("--native-snap="):
			_native_snap = arg.substr(14)   # development: save a picture of the native screen, then quit
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
	_globe.star_tooltip_changed.connect(_on_star_tooltip)   # macOS only
	_globe_container.mouse_entered.connect(_globe.set_mouse_inside.bind(true))
	_globe_container.mouse_exited.connect(func() -> void:
		_globe.set_mouse_inside(false)
		_on_star_tooltip("", Vector2.ZERO)
		_on_hover(0.0, 0.0, false))
	_flat = FlatStage.new()
	_flat.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flat.hover_changed.connect(_on_hover)
	_flat.location_clicked.connect(_on_location_clicked)
	_content.add_child(_flat)

## Star tooltip: drawn by us (not Godot's built-in tooltip) so it can sit beside the mouse pointer
## instead of under it.
func _on_star_tooltip(text: String, pos: Vector2) -> void:
	_star_tip_timer.stop()
	_star_tip.visible = false
	if text == "":
		return
	_star_tip_label.text = text
	_star_tip_pos = pos
	_star_tip_timer.start()

func _show_star_tooltip() -> void:
	_star_tip.reset_size()
	_star_tip.visible = true
	# Below and to the right of the pointer, clear of the cursor image; flip to stay inside the view.
	var spot := _star_tip_pos + Vector2(18.0, 30.0)
	var limit := _content.size - _star_tip.size
	if spot.x > limit.x:
		spot.x = _star_tip_pos.x - _star_tip.size.x - 10.0
	if spot.y > limit.y:
		spot.y = _star_tip_pos.y - _star_tip.size.y - 12.0
	_star_tip.position = spot.clamp(Vector2.ZERO, limit.max(Vector2.ZERO))

func _build_overlays() -> void:
	_star_tip = PanelContainer.new()
	_star_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_star_tip.visible = false
	var tip_style := StyleBoxFlat.new()
	tip_style.bg_color = Color(0.1, 0.1, 0.12, 0.92)
	tip_style.border_color = Color(0.45, 0.5, 0.6)
	tip_style.set_border_width_all(1)
	tip_style.set_corner_radius_all(4)
	tip_style.content_margin_left = 8
	tip_style.content_margin_right = 8
	tip_style.content_margin_top = 4
	tip_style.content_margin_bottom = 4
	_star_tip.add_theme_stylebox_override("panel", tip_style)
	_star_tip_label = Label.new()
	_star_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_star_tip.add_child(_star_tip_label)
	_star_tip_timer = Timer.new()
	_star_tip_timer.one_shot = true
	_star_tip_timer.wait_time = 0.35
	_star_tip_timer.timeout.connect(_show_star_tooltip)
	add_child(_star_tip_timer)
	_time_label = load("res://scripts/ui/time_label.gd").new()
	_time_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_time_label.offset_top = 8
	_time_label.offset_bottom = 8 + 64 * maxf(1.0, Layout.ui_scale() * 0.7)
	_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_time_label)
	_fps_label = Label.new()
	_fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_fps_label.offset_top = 8
	_fps_label.offset_right = -14 - _insets().z
	_fps_label.add_theme_font_size_override("font_size", Layout.font(20, 0.8))
	_fps_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.85))
	_fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_fps_label.add_theme_constant_override("outline_size", 6)
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_label.visible = Settings.get_bool("show_fps")
	_content.add_child(_fps_label)
	_content.add_child(_star_tip)
	Settings.changed.connect(func(k: String, v: Variant) -> void:
		if k == "show_fps":
			_fps_label.visible = bool(v))

	_status = load("res://scripts/ui/status_bar.gd").new()
	_status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status.anchor_left = 0.04
	_status.anchor_right = 0.96
	# One line on a desktop; two lines of larger text on a phone, kept above the home indicator.
	var bottom_gap := 12.0 * Layout.ui_scale() + (0.0 if Layout.is_phone() else _insets().w)   # phones: the content area already stops above the toolbar
	_status.offset_bottom = -bottom_gap
	_status.offset_top = -bottom_gap - (44.0 if not Layout.is_phone() else 2.0 * Layout.font(22, 0.85) * 1.5 + 36.0)
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

## There is no menu bar on any platform. Nearly everything the menus held is in the toolbar or Preferences; this one
## "More" button holds the few commands that were only in the menus.
func _build_more_button() -> void:
	var more := PopupMenu.new()
	more.add_item("Today's Times…", 1)
	more.add_item("My Locations…", 2)
	more.add_item("Earthquake Regions…", 3)
	more.add_item("Refresh Earthquakes", 4)
	more.id_pressed.connect(_on_more_menu)
	add_child(more)
	_more_menu = more
	_more_button = _icon_button("BlackList", "More", "Today's times, my locations, earthquake regions and refresh.", func() -> void:
		var below := Vector2i(_more_button.get_screen_position()) + Vector2i(0, int(_more_button.size.y))
		more.popup(Rect2i(below, Vector2i.ZERO)))

func _on_more_menu(id: int) -> void:
	match id:
		1: _action_times()
		2: _popup(_locations)
		3: _popup(_regions)
		4:
			QuakeService.refresh()
			_status.post("Refreshing earthquake data.", 4.0)

func _update_welcome_button(showing: bool) -> void:
	_welcome_button.icon = load(ICON_DIR + ("GlobeIconSelected" if showing else "GlobeIcon") + ".png")
	NativeUI.refresh_toolbar()

func _icon_button(icon_name: String, label: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.icon = load(ICON_DIR + icon_name + ".png")
	b.expand_icon = true
	b.text = label
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	var s := Layout.ui_scale()
	b.custom_minimum_size = Vector2(60 if Layout.is_phone() else 72, 50) * s
	if Layout.is_phone():
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL   # the buttons share the row evenly
		# The phone theme's big button padding would make these icon buttons far wider than their label.
		for box_name in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			var e := StyleBoxEmpty.new()
			e.content_margin_left = 4
			e.content_margin_right = 4
			e.content_margin_top = 2
			e.content_margin_bottom = 2
			b.add_theme_stylebox_override(box_name, e)
	b.add_theme_constant_override("icon_max_width", int(24 * s))
	b.add_theme_font_size_override("font_size", Layout.font(11))
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
	_toolbar_style = sb
	add_child(_toolbar_bar)
	_place_toolbar()
	# The toolbar scrolls sideways when it is wider than the screen (a phone in portrait).
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER   # still scrolls by touch or wheel
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_toolbar_bar.add_child(scroll)
	if Layout.is_phone():
		# A grid, so every button is visible: it wraps onto a second row instead of scrolling sideways.
		var grid := GridContainer.new()
		grid.add_theme_constant_override("h_separation", int(4 * Layout.ui_scale()))
		grid.add_theme_constant_override("v_separation", 0)
		_toolbar = grid
	else:
		_toolbar = HBoxContainer.new()
		_toolbar.add_theme_constant_override("separation", int(4 * Layout.ui_scale()))
	_toolbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_toolbar)
	_icon_button("InfoIcon", "About", "View information about Flatland.", _action_about)
	_icon_button("DebugIcon", "Debugger", "Open the debugger.", func() -> void: _popup(_debugger))
	_icon_button("LiveStatus", "Live Data", "See current live data status and statistics.", _action_live_status)
	_icon_button("GearIcon", "Preferences", "Change Flatland's settings.", _action_preferences)
	_lock_button = _icon_button("UnlockWorldIcon", "Lock", "Lock or unlock the world.", func() -> void:
		Settings.set_value("world_locked", not Settings.get_bool("world_locked")))
	_icon_button("ResetViewIcon", "Reset View", "Reset the 3D view.", _action_reset_view)
	_icon_button("CameraButtonUnpressed", "Snapshot", "Take a snapshot of the view.", _action_snapshot)
	_icon_button("EarthquakeIcon", "Earthquakes", "Show the list of earthquakes.", _action_quake_list)
	_welcome_button = _icon_button("GlobeIcon", "Welcome", "Show or hide the welcome text.", _globe.toggle_intro)
	_build_more_button()
	_globe.intro_changed.connect(_update_welcome_button)
	_update_welcome_button(_globe.is_intro_showing())
	_place_toolbar()   # now that the buttons exist, size the bar to the rows they need
	if NativeUI.toolbar_wanted() and NativeUI.show_toolbar(self) and _native_toolbar_on():
		_toolbar_bar.visible = false

func _build_dialogs() -> void:
	_prefs = load("res://scripts/ui/prefs_dialog.gd").new()
	_about = load("res://scripts/ui/about_dialog.gd").new()
	_times = load("res://scripts/ui/todays_times_dialog.gd").new()
	_quake_list = load("res://scripts/ui/quake_list_dialog.gd").new()
	_live_status = load("res://scripts/ui/live_status_dialog.gd").new()
	_locations = load("res://scripts/ui/locations_dialog.gd").new()
	_regions = load("res://scripts/ui/regions_dialog.gd").new()
	_debugger = load("res://scripts/ui/debug_dialog.gd").new()
	_satellites = load("res://scripts/ui/satellites_dialog.gd").new()
	for w in [_prefs, _about, _times, _quake_list, _live_status, _locations, _regions, _debugger, _satellites]:
		w.visible = false
		add_child(w)
		PhoneSheet.wrap(w)   # full-screen sheet on phones; no-op on desktop
	_quake_list.quake_chosen.connect(_on_quake_chosen)
	_prefs.open_satellites.connect(func() -> void: _popup(_satellites))
	_snapshot_dialog = FileDialog.new()
	_snapshot_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_snapshot_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_snapshot_dialog.filters = PackedStringArray(["*.png ; PNG image"])
	_snapshot_dialog.title = "Save Snapshot"
	_snapshot_dialog.file_selected.connect(_save_snapshot)
	add_child(_snapshot_dialog)

# MARK: - Actions (names follow Flatland's IBActions)

func _popup(w: Window, size_hint: Vector2i = Vector2i.ZERO) -> void:
	# iOS (and macOS with --native-ui): the dialog's native SwiftUI screen, when the extension is there.
	if NativeUI.wanted() and NativeUI.present(w):
		return
	if Layout.is_phone() and w.has_meta("phone_sheet"):
		# A full-screen sheet that slides up from the toolbar at the bottom (see PhoneSheet).
		var ins := _insets()
		var area := get_viewport_rect().size
		var rect := Rect2i(Vector2i(ins.x, ins.y), Vector2i(area.x - ins.x - ins.z, area.y - ins.y - ins.w))
		PhoneSheet.present(w, rect, int(area.y - ins.w - _phone_toolbar_height()))
		return
	if size_hint != Vector2i.ZERO:
		w.size = size_hint
	if Layout.is_phone() and not w.has_meta("phone_sized"):
		# Dialogs were laid out for a desktop; enlarge them for the bigger phone text, within the screen.
		w.set_meta("phone_sized", true)
		var area := get_viewport_rect().size
		var s := Layout.ui_scale()
		w.size = Vector2i(minf(w.size.x * s, area.x * 0.96), minf(w.size.y * s, area.y * 0.88))
	w.popup_centered()

func _action_preferences() -> void: _popup(_prefs)
func _action_about() -> void: _popup(_about)
func _action_times() -> void: _popup(_times)
func _action_quake_list() -> void: _popup(_quake_list)
func _action_live_status() -> void: _popup(_live_status)

func _action_select_map() -> void:
	_popup(_prefs)
	var tabs := _prefs.find_children("*", "TabContainer", true, false)
	if tabs.size() > 0:
		(tabs[0] as TabContainer).current_tab = 1

func _action_reset_view() -> void:
	if _flat.visible:
		_flat.reset_view()
	else:
		_globe.reset_view()

func _action_snapshot() -> void:
	# Grab the picture now, before the dialog opens, so the snapshot shows the view at the moment
	# of the button press rather than whenever the file is saved (or with the dialog on top).
	_snapshot_image = get_viewport().get_texture().get_image()
	var d := Time.get_datetime_dict_from_system()
	_snapshot_dialog.current_file = "Flatland Snapshot %04d-%02d-%02d %02d.%02d.%02d.png" % [d["year"], d["month"], d["day"], d["hour"], d["minute"], d["second"]]
	# Open where the last snapshot was saved; the first time (or if that folder is gone), use Pictures.
	var start_dir := Settings.get_string("snapshot_dir")
	if start_dir == "" or not DirAccess.dir_exists_absolute(start_dir):
		start_dir = OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if start_dir != "":
		_snapshot_dialog.current_dir = start_dir
	_snapshot_dialog.popup_centered_ratio(0.6)

func _save_snapshot(path: String) -> void:
	if _snapshot_image != null and _snapshot_image.save_png(path) == OK:
		Settings.set_value("snapshot_dir", path.get_base_dir())
		_status.post("Snapshot saved to " + path, 5.0)
	else:
		_status.post("Could not save the snapshot.", 5.0)
	_snapshot_image = null

# MARK: - Touch pinch

var _touches := {}          # finger index -> screen position, for the fingers currently down
var _pinch_span := 0.0      # distance between the first two fingers at the last event

## Godot only synthesizes pinch (magnify) gestures from a trackpad, not from a touch screen, so
## pinch-to-zoom is worked out here from the raw touch events and sent to the visible view.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
		_pinch_span = _touch_span()
		_pinching_view(_touches.size() >= 2)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touches[sd.index] = sd.position
		if _touches.size() >= 2:
			var span := _touch_span()
			if _pinch_span > 1.0 and span > 1.0:
				var view: Node = _flat if _flat.visible else _globe
				view.pinch_zoom(span / _pinch_span)
			_pinch_span = span

func _touch_span() -> float:
	if _touches.size() < 2:
		return 0.0
	var keys := _touches.keys()
	keys.sort()
	return (_touches[keys[0]] as Vector2).distance_to(_touches[keys[1]])

func _pinching_view(on: bool) -> void:
	_flat.set_pinching(on)
	_globe.set_pinching(on)

# MARK: - Events

func _on_setting_changed(key: String, _value: Variant) -> void:
	match key:
		"view_type":
			_apply_view_type()
		"world_locked":
			NativeUI.refresh_toolbar()
			_lock_button.icon = load(ICON_DIR + ("LockWorldIcon" if Settings.get_bool("world_locked") else "UnlockWorldIcon") + ".png")
		"show_debug_grid":
			_debug_grid.visible = Settings.get_bool("show_debug_grid")
		"color_background":
			_bg.color = Settings.get_color("color_background")

## Phones: how many toolbar buttons fit in one row of the current width.
func _phone_toolbar_columns() -> int:
	var ins := _insets()
	var width := get_viewport_rect().size.x - ins.x - ins.z - 24.0
	var per_button := 60.0 * Layout.ui_scale()
	for b in _toolbar.get_children():   # the widest button (its label) decides how many fit
		per_button = maxf(per_button, (b as Control).get_combined_minimum_size().x + 4.0 * Layout.ui_scale())
	return clampi(int(floor(width / per_button)), 1, maxi(1, _toolbar.get_child_count()))

## Phones: height of the toolbar, which is two (or more) rows when the buttons do not fit in one.
func _phone_toolbar_height() -> int:
	if _native_toolbar_on():
		return NativeUI.toolbar_height()   # the SwiftUI bar measures itself
	if _toolbar == null or not (_toolbar is GridContainer):
		return _toolbar_height()
	var cols := _phone_toolbar_columns()
	(_toolbar as GridContainer).columns = cols
	var rows := int(ceil(float(_toolbar.get_child_count()) / float(cols)))
	return _toolbar_height() * maxi(rows, 1)

## On iOS the button bar is a SwiftUI view (see NativeUI) and the Godot one stays hidden.
func _native_toolbar_on() -> bool:
	return Layout.is_ios() and NativeUI.toolbar_wanted()

## The native bar's buttons (same commands as the Godot toolbar).
func native_toolbar() -> Array:
	return [
		{"id": "about", "title": "About", "symbol": "info.circle"},
		{"id": "debugger", "title": "Debugger", "symbol": "ladybug"},
		{"id": "live", "title": "Live Data", "symbol": "antenna.radiowaves.left.and.right"},
		{"id": "prefs", "title": "Preferences", "symbol": "gearshape"},
		{"id": "lock", "title": "Lock", "symbol": "lock.fill" if Settings.get_bool("world_locked") else "lock.open"},
		{"id": "reset", "title": "Reset View", "symbol": "arrow.counterclockwise"},
		{"id": "snapshot", "title": "Snapshot", "symbol": "camera"},
		{"id": "quakes", "title": "Earthquakes", "symbol": "waveform.path.ecg"},
		{"id": "welcome", "title": "Welcome", "symbol": "globe", "selected": _globe.is_intro_showing()},
		{"id": "more", "title": "More", "symbol": "ellipsis.circle", "menu": [
			{"id": "times", "title": "Today's Times…"},
			{"id": "locations", "title": "My Locations…"},
			{"id": "regions", "title": "Earthquake Regions…"},
			{"id": "refresh", "title": "Refresh Earthquakes"}]},
	]

func native_toolbar_event(id: String) -> void:
	match id:
		"about": _action_about()
		"debugger": _popup(_debugger)
		"live": _action_live_status()
		"prefs": _action_preferences()
		"lock": Settings.set_value("world_locked", not Settings.get_bool("world_locked"))
		"reset": _action_reset_view()
		"snapshot": _action_snapshot()
		"quakes": _action_quake_list()
		"welcome": _globe.toggle_intro()
		"times": _on_more_menu(1)
		"locations": _on_more_menu(2)
		"regions": _on_more_menu(3)
		"refresh": _on_more_menu(4)

## The native bar's height changed (first shown, or the phone was rotated): make room for it.
func native_toolbar_resized() -> void:
	_place_toolbar()
	_relayout()

## Put the toolbar where it belongs: along the top on a desktop, along the bottom (above the home
## indicator, with the views shifted up to make room) on iOS and Android.
func _place_toolbar() -> void:
	var ins := _insets()
	if Layout.is_phone():
		var bar_h := _phone_toolbar_height()
		_content.offset_top = ins.y
		_content.offset_bottom = -(bar_h + ins.w)
		_toolbar_bar.anchor_left = 0.0
		_toolbar_bar.anchor_right = 1.0
		_toolbar_bar.anchor_top = 1.0
		_toolbar_bar.anchor_bottom = 1.0
		_toolbar_bar.offset_left = 0
		_toolbar_bar.offset_right = 0
		_toolbar_bar.offset_top = -(bar_h + ins.w)
		_toolbar_bar.offset_bottom = 0
		_toolbar_style.border_width_bottom = 0
		_toolbar_style.border_width_top = 1
		_toolbar_style.content_margin_bottom = 4 + ins.w   # the bar reaches the screen edge, behind the home indicator
	else:
		_toolbar_bar.anchor_left = 0.0
		_toolbar_bar.anchor_right = 1.0
		_toolbar_bar.anchor_top = 0.0
		_toolbar_bar.anchor_bottom = 0.0
		_toolbar_bar.offset_left = 0
		_toolbar_bar.offset_right = 0
		_toolbar_bar.offset_top = ins.y
		_toolbar_bar.offset_bottom = ins.y + _toolbar_height()

## Recompute the positions that depend on the safe-area insets (after the phone is rotated).
func _relayout() -> void:
	if not Layout.is_phone():
		return
	var ins := _insets()
	_place_toolbar()
	_fps_label.offset_right = -14 - ins.z
	var bottom_gap := 12.0 * Layout.ui_scale()
	_status.offset_bottom = -bottom_gap
	_status.offset_top = -bottom_gap - (2.0 * Layout.font(22, 0.85) * 1.5 + 36.0)

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
	# The time label is at the top on every map.
	_time_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_time_label.offset_top = 8
	_time_label.offset_bottom = 8 + 64 * maxf(1.0, Layout.ui_scale() * 0.7)

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
	if Settings.get_bool("enable_sounds"):
		var file := Settings.get_string("quake_sound")
		if not _sounds.has(file):
			_sounds[file] = load("res://Assets/Sounds/" + file)
		if _sounds[file] != null:
			_player.stream = _sounds[file]
			_player.play()

## Like Flatland, the biggest new quake stays in the status bar (for ten minutes) whenever
## nothing else is being shown.
func _on_biggest_new_quake(q: Dictionary) -> void:
	var d := Time.get_datetime_dict_from_unix_time(int(q["time"]))
	_status.push("New quake: M %.1f %s, %04d-%02d-%02d %02d:%02d:%02d GMT" % [q["magnitude"], q["place"],
		d["year"], d["month"], d["day"], d["hour"], d["minute"], d["second"]], 600.0)

func _update_debug_grid() -> void:
	if not _debug_grid.visible:
		return
	var up := (Time.get_ticks_msec() - _start_msec) / 1000
	_debug_values["Version"].text = "v" + APP_VERSION
	_debug_values["Build"].text = "%d (Godot %s)" % [BuildInfo.build_number(), Engine.get_version_info()["string"]]
	_debug_values["Build date"].text = BuildInfo.timestamp()
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

func _process(delta: float) -> void:
	if _flat.visible:
		# Tell the flat map how much room the clock (top) and the status bar (bottom) take, so it fills the rest.
		var pad := 14.0 * Layout.ui_scale()
		_flat.reserved_top = _time_label.position.y + _time_label.size.y + pad
		_flat.reserved_bottom = (-_status.offset_top if _status.visible else 0.0) + pad
	_fps_accum += delta
	if _fps_accum >= 0.5 and _fps_label.visible:
		_fps_accum = 0.0
		_fps_label.text = "%d FPS" % int(Engine.get_frames_per_second())
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
		"prefsclose":
			_action_preferences()
			get_tree().create_timer(1.2).timeout.connect(func() -> void: PhoneSheet.dismiss(_prefs))
		"home": _action_preferences(); (_prefs.find_children("*", "TabContainer", true, false)[0] as TabContainer).current_tab = 6
		"grid": _action_preferences(); (_prefs.find_children("*", "TabContainer", true, false)[0] as TabContainer).current_tab = 3
		"satellites": _popup(_satellites)
		"map": _action_select_map()
		"about": _action_about()
		"times": _action_times()
		"quakes": _action_quake_list()
		"live": _action_live_status()
		"debug": _popup(_debugger)
		"toolbar": pass   # the native button bar is shown at start-up
		"locations": _popup(_locations)
		"regions": _popup(_regions)
		"click": _on_location_clicked(35.0, -100.0)
	if _native_snap != "" and NativeUI.is_open():
		get_tree().create_timer(2.0).timeout.connect(func() -> void: NativeUI._call("debug_snapshot", _native_snap))
		get_tree().create_timer(3.5).timeout.connect(get_tree().quit)
	elif _native_snap != "" and _open_on_start == "toolbar":
		# development: a picture of the native button bar
		get_tree().create_timer(2.0).timeout.connect(func() -> void: NativeUI._call("debug_toolbar_snapshot", _native_snap))
		get_tree().create_timer(3.5).timeout.connect(get_tree().quit)
