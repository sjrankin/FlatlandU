extends Control
## Main window: the counterpart of Flatland's MainController. Hosts the 3D globe and the flat
## view, the time label, toolbar, status bar and all dialogs. The button bar and the dialogs are native (SwiftUI on iOS and
## macOS, Compose on Android; see NativeUI). Windows and Linux, which have no native code, use Godot's own.

## Folder of the toolbar icon pictures.
const ICON_DIR := "res://Assets/Icons/"
## The version text shown in the debug text grid.
const APP_VERSION := "1.0 (Godot)"
## Height of Godot's own toolbar in points before scaling; see [method _toolbar_height].
const TOOLBAR_HEIGHT := 60

## Height of Godot's own toolbar, scaled up on phones.
##
## Returns: pixels.
func _toolbar_height() -> int:
	return int(TOOLBAR_HEIGHT * Layout.ui_scale())

## The safe-area insets (camera cut-out, rounded corners, home indicator); see [method Layout.safe_insets].
##
## Returns: a Vector4 (left, top, right, bottom) in pixels.
func _insets() -> Vector4:
	return Layout.safe_insets()

## The area the views, clock, FPS label and status bar live in; shrunk to leave room for the toolbar.
var _content: Control
## Godot's own toolbar panel; null when the native bar is used.
var _toolbar_bar: PanelContainer
## Container that shows the 3D globe's viewport; gets the globe's mouse input.
var _globe_container: SubViewportContainer
## The SubViewport the globe is drawn in.
var _globe_viewport: SubViewport
## The globe view script, loaded by path: its camera-mode enum is used here without a global class name (a global
## class name was not found in the exported app, and nothing was drawn).
const GlobeScript := preload("res://scripts/views/globe_view.gd")

## The 3D globe ([GlobeScript]).
var _globe: Node3D
## The flat maps on a 3D plane ([FlatStage]).
var _flat: FlatStage
## The clock at the top ([TimeLabel] script).
var _time_label: Label
## The panel that shows the star tooltip beside the mouse pointer (macOS).
var _star_tip: PanelContainer
## The tooltip's text.
var _star_tip_label: Label
## Delay of 0.35 s before the tooltip appears.
var _star_tip_timer: Timer
## Where the mouse was when the tooltip text arrived.
var _star_tip_pos := Vector2.ZERO
## Godot toolbar's Welcome button (its icon shows whether the text is on); null with the native bar.
var _welcome_button: Button
## Godot toolbar's More button.
var _more_button: Button
## The menu the More button opens.
var _more_menu: PopupMenu
## The frame rate shown at the top right (the `show_fps` setting).
var _fps_label: Label
## Seconds since the frame rate text was last updated (twice a second).
var _fps_accum := 0.0
## The status bar ([StatusBar] script) at the bottom.
var _status: PanelContainer
## The last "downloading the satellite image" message posted to the status bar, so the final message can replace it.
var _satellite_msg := ""
## The container Godot's own toolbar buttons are added to.
var _toolbar: Container
## The toolbar panel's style, adjusted when it moves to the bottom.
var _toolbar_style: StyleBoxFlat
## The debug text grid in the lower left (version, build, uptime, memory).
var _debug_grid: GridContainer
## The value labels of the debug grid, by row name.
var _debug_values: Dictionary = {}
## View-type buttons by view name, from an older toolbar; no longer filled in, kept so [method _apply_view_type] can
## update them if they exist.
var _view_buttons: Dictionary = {}
## Godot toolbar's Lock button (its icon shows the lock state).
var _lock_button: Button
## The Preferences dialog.
var _prefs: Window
## The About dialog.
var _about: Window
## The Today's Times dialog.
var _times: Window
## The earthquake list dialog.
var _quake_list: Window
## The Live Data Status dialog.
var _live_status: Window
## The My Locations dialog.
var _locations: Window
## The Earthquake Regions dialog.
var _regions: Window
## The Satellites dialog.
var _satellites: Window
## The Debugger dialog.
var _debugger: Window
## The background rectangle, in the `color_background` setting's color.
var _bg: ColorRect
## The file dialog that asks where to save a snapshot.
var _snapshot_dialog: FileDialog
## The file dialog that asks where to save a video.
var _video_dialog: FileDialog
## Godot toolbar's Record button (turns into a red Stop button while recording).
var _video_button: Button
## Records the window to a movie (video_recorder.gd).
var _recorder: Node
## The picture taken when the Snapshot button is pressed (before the dialog opens, so it shows the view at that
## moment); saved when the dialog is confirmed.
var _snapshot_image: Image
## The popup that says what is at a clicked place.
var _whats_here: PopupPanel
## The popup's text.
var _whats_here_label: RichTextLabel
## `Time.get_ticks_msec()` at start, for the uptime in the debug grid.
var _start_msec := Time.get_ticks_msec()
## New-quake sounds already loaded, by file name.
var _sounds: Dictionary = {}
## Plays the new-quake sound.
var _player: AudioStreamPlayer
## The `--open=` development flag: which dialog to open at start-up (see [method _open_for_test]).
var _open_on_start := ""
## The `--fake-quakes` development flag: show made-up earthquakes (no network needed).
var _fake_quakes := false
## The `--resize=WxH` development flag: set the window to this size shortly after start.
var _resize_to := ""
## The `--native-snap=` development flag: save a picture of the native screen to this path, then quit.
var _native_snap := ""
## The `--cam=yaw,pitch,distance` development flag.
var _cam_args := PackedFloat64Array()
## The `--shot=` development flag: save a picture of the window here after 150 frames, then quit.
var _shot_path := ""
## Frames left before the `--shot=` picture is taken.
var _shot_frames := 0

## Builds the main window: reads the development flags, applies the phone theme, adds the background and content area,
## builds the views, overlays, toolbar and dialogs, connects settings and earthquake events, then starts the "Please
## Wait" cover ([method _begin_startup_wait]) and any development actions (recording test, camera vantage, dialog to
## open, fake quakes). Also prints whether native UI is used.
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
	_content.offset_top = _insets().y if _toolbar_at_bottom() else _toolbar_height() + _insets().y
	_content.offset_bottom = -((_toolbar_height() if Layout.is_phone() else NativeUI.toolbar_height()) + _insets().w) if _toolbar_at_bottom() else 0.0
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
	MapCatalog.satellite_progress.connect(func(text: String, done: bool) -> void:
		if done:
			_status.update_current(text, 6.0, _satellite_msg)
			_satellite_msg = ""
		elif _satellite_msg != "":
			# A second "downloading" message (the fallback source) replaces the first.
			_status.update_current(text, 90.0, _satellite_msg)
			_satellite_msg = text
		else:
			_satellite_msg = text
			_status.post(text, 90.0))
	QuakeService.fetch_failed.connect(func(reason: String) -> void: _status.post("Earthquake data: " + reason, 5.0))
	_apply_view_type()
	_update_debug_grid()
	_begin_startup_wait()
	print("Native UI: %s (embedded in the editor: %s)" % ["used" if NativeUI.wanted() else "not used", Engine.is_embedded_in_editor()])
	get_window().size_changed.connect(_relayout)   # the safe area changes when a phone is rotated
	if _record_test != "":
		get_tree().create_timer(2.0).timeout.connect(func() -> void:
			_recorder.start(_record_test)
			await get_tree().create_timer(4.0).timeout
			await _recorder.stop()
			get_tree().quit())
	if _vantage == "flightreset":
		_globe.set_camera_mode(GlobeScript.CamMode.FLIGHT)
		get_tree().create_timer(0.5).timeout.connect(func() -> void: _globe.reset_view())
	elif _vantage != "":
		_globe.set_camera_mode({"moon": GlobeScript.CamMode.FROM_MOON, "sun": GlobeScript.CamMode.FROM_SUN, "lookmoon": GlobeScript.CamMode.LOOK_AT_MOON, "flight": GlobeScript.CamMode.FLIGHT}.get(_vantage, 0))
	if _cam_args.size() == 3:
		_globe.set_camera(_cam_args[0], _cam_args[1], _cam_args[2])
		_flat.set_camera(_cam_args[0], _cam_args[1])
	if _open_on_start != "":
		call_deferred("_open_for_test", _open_on_start)
	if _fake_quakes:
		call_deferred("_inject_fake_quakes")
	var t := Timer.new()
	t.wait_time = 1.0
	t.autostart = true
	t.timeout.connect(_update_debug_grid)
	add_child(t)

## Reads the development flags after `--`: `--time=<unix>` shows another moment, `--view=`, `--map=`,
## `--set=key=value`, `--fake-quakes`, `--shot=<file>`, `--cam=`, `--record=<file>`, `--vantage=`, `--resize=`,
## `--open=`, `--native-snap=` and `--hours=`. Settings flags use [method Settings.override], so they are not saved.
## See also [Layout] for `--phone`, `--ui-scale=` and `--safe=`.
func _parse_command_line() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--time="):
			Solar.time_offset = float(arg.substr(7)) - Time.get_unix_time_from_system()
		elif arg == "--fake-quakes":
			_fake_quakes = true   # development: show made-up earthquakes (no network needed)
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
		elif arg.begins_with("--record="):
			_record_test = arg.substr(9)   # development: record 4 seconds to this file, then quit
		elif arg.begins_with("--vantage="):
			_vantage = arg.substr(10)   # development: moon, sun or lookmoon
		elif arg.begins_with("--resize="):
			_resize_to = arg.substr(9)
		elif arg.begins_with("--open="):
			_open_on_start = arg.substr(7)
		elif arg.begins_with("--native-snap="):
			_native_snap = arg.substr(14)   # development: save a picture of the native screen, then quit
		elif arg.begins_with("--hours="):
			Settings.override("hour_type", arg.substr(8))

# MARK: - Construction

## Builds the 3D globe (in a SubViewport inside a container that forwards the mouse to the globe) and the flat map
## stage, and connects their hover, click, star tooltip, context menu and camera-mode signals.
func _build_views() -> void:
	_globe_container = SubViewportContainer.new()
	_globe_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_globe_container.stretch = true
	_globe_container.mouse_filter = Control.MOUSE_FILTER_PASS
	_content.add_child(_globe_container)
	_globe_viewport = SubViewport.new()
	PowerManager.register_viewport(_globe_viewport)
	_globe_viewport.handle_input_locally = true
	_globe_viewport.gui_disable_input = false
	_globe_container.add_child(_globe_viewport)
	_globe = GlobeScript.new()
	_globe_viewport.add_child(_globe)
	_globe.hover_changed.connect(_on_hover)
	_globe.location_clicked.connect(_on_location_clicked)
	_globe_container.gui_input.connect(_globe.handle_gui_input)
	_globe.star_tooltip_changed.connect(_on_star_tooltip)   # macOS only
	_globe.context_requested.connect(_on_globe_context_requested)
	_globe.camera_mode_changed.connect(func(_m: int) -> void: _refresh_context_menu())
	_globe_container.mouse_entered.connect(_globe.set_mouse_inside.bind(true))
	_globe_container.mouse_exited.connect(func() -> void:
		_globe.set_mouse_inside(false)
		_on_star_tooltip("", Vector2.ZERO)
		_on_hover(0.0, 0.0, false))
	_flat = FlatStage.new()
	_flat.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flat.hover_changed.connect(_on_hover)
	_flat.context_requested.connect(_on_flat_context_requested)
	_content.add_child(_flat)

## Star tooltip: drawn here (not with Godot's built-in tooltip) so it can sit beside the mouse pointer instead of
## under it. A star must stay under the mouse for 0.35 s before the tooltip shows.
##
## [param text]: the tooltip text, or "" to hide it.
## [param pos]: the mouse position in pixels.
func _on_star_tooltip(text: String, pos: Vector2) -> void:
	_star_tip_timer.stop()
	_star_tip.visible = false
	if text == "":
		return
	_star_tip_label.text = text
	_star_tip_pos = pos
	_star_tip_timer.start()

## Shows the tooltip below and to the right of the pointer (clear of the cursor image), flipping to stay inside the
## view.
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

## Builds the things drawn over the views: the star tooltip, the clock, the FPS label, the status bar, the debug text
## grid and the What's Here popup.
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
	var bottom_gap := 12.0 * Layout.ui_scale() + (0.0 if _toolbar_at_bottom() else _insets().w)   # the content area already stops above a bottom toolbar
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

## Builds the More button and its menu (Today's Times, My Locations, Earthquake Regions, Refresh Earthquakes). There
## is no menu bar on any platform: nearly everything the menus held is in the toolbar or Preferences, and this holds
## the few commands that were only in the menus.
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

# MARK: - Context menu

## Context menu item id: Show Earth from Moon.
const CTX_FROM_MOON := 1
## Context menu item id: Show Earth from Sun.
const CTX_FROM_SUN := 2
## Context menu item id: View Moon from Earth.
const CTX_MOON_FROM_EARTH := 3
## Context menu item id: Reset View.
const CTX_RESET := 4
## Context menu item id: What's Here? (only offered when the click is on the Earth).
const CTX_WHATS_HERE := 5
## Context menu item id: Camera Flight.
const CTX_FLIGHT := 6

## Context menu item ids from here up are the map types: this plus the index in [constant CTX_MAP_TYPES].
const CTX_MAP_TYPE_BASE := 100
## The map types offered in the context menu, as [menu text, `view_type` setting value], in menu order.
const CTX_MAP_TYPES := [
	["Globe", Settings.VIEW_GLOBE],
	["Equirectangular", Settings.VIEW_RECT],
	["North Polar", Settings.VIEW_FLAT_NORTH],
	["South Polar", Settings.VIEW_FLAT_SOUTH],
	["Cubic", Settings.VIEW_CUBIC],
]

## The context menu for the 3D views; created on first use.
var _context_menu: PopupMenu
## The `--vantage=` development flag: moon, sun, lookmoon, flight or flightreset, to start in that camera mode.
var _vantage := ""
## The `--record=<file>` development flag: record 4 seconds to this file, then quit.
var _record_test := ""
## Where in the view the menu was asked for (used by What's Here).
var _context_point := Vector2.ZERO
## Whether the menu was asked for in a flat map (true) or the globe or cube (false); the camera modes are only offered
## for the globe.
var _context_in_flat := false

## The globe asked for the context menu (right click, or a long press on a phone or tablet): shows it at that point.
## Choosing outside it closes it. The camera modes are not saved; they last until the camera is moved or the view is
## reset.
##
## [param at]: where in the globe view, in pixels.
func _on_globe_context_requested(at: Vector2) -> void:
	_show_context_menu(at, false)

## A flat map asked for the context menu (right click, or a long press on a phone or tablet): shows it at that point.
##
## [param at]: where in the flat map's view, in pixels.
func _on_flat_context_requested(at: Vector2) -> void:
	_show_context_menu(at, true)

## Creates the context menu on first use, fills it for the view and shows it at a point.
##
## [param at]: where in the view, in pixels.
## [param in_flat]: true if the view is a flat map, false for the globe or cube.
func _show_context_menu(at: Vector2, in_flat: bool) -> void:
	if _context_menu == null:
		_context_menu = PopupMenu.new()
		_context_menu.id_pressed.connect(_on_context_menu)
		if Layout.is_phone():
			_context_menu.add_theme_font_size_override("font_size", Layout.font(18))
		add_child(_context_menu)
	_context_point = at
	_context_in_flat = in_flat
	_refresh_context_menu()
	var origin: Vector2 = _flat.get_screen_position() if in_flat else _globe_container.get_screen_position()
	_context_menu.popup(Rect2i(Vector2i(origin + at), Vector2i.ZERO))

## Rebuilds the menu's items (the camera modes only for the globe): Show Earth from Moon and from Sun and Camera Flight (with check marks for the active
## mode), View Moon from Earth, Reset View, a divider and the map types (the current one checked), and What's Here? if
## the click was on the Earth. Called each time the menu opens and when the camera mode changes.
func _refresh_context_menu() -> void:
	if _context_menu == null:
		return
	var mode: int = _globe.camera_mode()
	_context_menu.clear()
	if not _context_in_flat:
		_context_menu.add_check_item("Show Earth from Moon", CTX_FROM_MOON)
		_context_menu.set_item_checked(_context_menu.item_count - 1, mode == GlobeScript.CamMode.FROM_MOON)
		_context_menu.add_check_item("Show Earth from Sun", CTX_FROM_SUN)
		_context_menu.set_item_checked(_context_menu.item_count - 1, mode == GlobeScript.CamMode.FROM_SUN)
		_context_menu.add_item("View Moon from Earth", CTX_MOON_FROM_EARTH)
		_context_menu.add_check_item("Camera Flight", CTX_FLIGHT)
		_context_menu.set_item_checked(_context_menu.item_count - 1, mode == GlobeScript.CamMode.FLIGHT)
	_context_menu.add_item("Reset View", CTX_RESET)
	_context_menu.add_separator()
	var current := Settings.get_string("view_type")
	for i in CTX_MAP_TYPES.size():
		_context_menu.add_radio_check_item(CTX_MAP_TYPES[i][0], CTX_MAP_TYPE_BASE + i)
		_context_menu.set_item_checked(_context_menu.item_count - 1, CTX_MAP_TYPES[i][1] == current)
	if _context_pick().get("hit", false):
		_context_menu.add_separator()
		_context_menu.add_item("What's Here?", CTX_WHATS_HERE)

## The place under the point the context menu was asked for, in whichever view it was asked in.
##
## Returns: {"hit": false}, or {"hit": true, "lat", "lon"}.
func _context_pick() -> Dictionary:
	return _flat.pick_screen(_context_point) if _context_in_flat else _globe.pick(_context_point)

## Runs the chosen menu item: choosing an active mode again turns it off (back to orbit); Reset View is the same as a
## double click; a map type switches to that view (the `view_type` setting); What's Here? shows the place popup.
##
## [param id]: the item's id (a CTX_ constant).
func _on_context_menu(id: int) -> void:
	var mode: int = _globe.camera_mode()
	if id >= CTX_MAP_TYPE_BASE and id < CTX_MAP_TYPE_BASE + CTX_MAP_TYPES.size():
		Settings.set_value("view_type", CTX_MAP_TYPES[id - CTX_MAP_TYPE_BASE][1])
		return
	match id:
		CTX_FROM_MOON:
			_globe.set_camera_mode(GlobeScript.CamMode.ORBIT if mode == GlobeScript.CamMode.FROM_MOON else GlobeScript.CamMode.FROM_MOON)
		CTX_FROM_SUN:
			_globe.set_camera_mode(GlobeScript.CamMode.ORBIT if mode == GlobeScript.CamMode.FROM_SUN else GlobeScript.CamMode.FROM_SUN)
		CTX_MOON_FROM_EARTH:
			_globe.set_camera_mode(GlobeScript.CamMode.LOOK_AT_MOON)
		CTX_FLIGHT:
			_globe.set_camera_mode(GlobeScript.CamMode.ORBIT if mode == GlobeScript.CamMode.FLIGHT else GlobeScript.CamMode.FLIGHT)
		CTX_RESET:
			_action_reset_view()
		CTX_WHATS_HERE:
			var p := _context_pick()
			if p.get("hit", false):
				_on_location_clicked(p["lat"], p["lon"])

# MARK: - Start-up

## Everything is built before anything moves: puts a "Please Wait…" cover over the window, which
## [method _finish_startup] removes. Without the cover the welcome animation would run for a second and then stall
## while the rest was made.
func _begin_startup_wait() -> void:
	var cover := ColorRect.new()
	cover.color = Settings.get_color("color_background")
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	var label := Label.new()
	label.text = "Please Wait…"
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", Layout.font(28))
	cover.add_child(label)
	add_child(cover)
	_finish_startup(cover)

## Waits for the first earthquake data (up to 8 seconds, or until a fetch fails), plus four frames to draw it, then
## removes the cover and starts the welcome text.
##
## [param cover]: the Please Wait cover to remove.
func _finish_startup(cover: Control) -> void:
	var state := {"arrived": true}      # a dictionary: a lambda gets its own copy of a plain variable
	if Settings.get_bool("enable_earthquakes") and not _fake_quakes:
		state["arrived"] = false
		QuakeService.quakes_updated.connect(func(_q: Array) -> void: state["arrived"] = true, CONNECT_ONE_SHOT)
		QuakeService.fetch_failed.connect(func(_r: String) -> void: state["arrived"] = true, CONNECT_ONE_SHOT)
	var give_up := Time.get_ticks_msec() + 8000
	while not state["arrived"] and Time.get_ticks_msec() < give_up:
		await get_tree().process_frame
	for i in range(4):      # let the views draw what has just been built
		await get_tree().process_frame
	cover.queue_free()
	_globe.start_intro()

## Runs a More-menu command.
##
## [param id]: 1 Today's Times, 2 My Locations, 3 Earthquake Regions, 4 Refresh Earthquakes.
func _on_more_menu(id: int) -> void:
	match id:
		1: _action_times()
		2: _popup(_locations)
		3: _popup(_regions)
		4:
			QuakeService.refresh()
			_status.post("Refreshing earthquake data.", 4.0)

## Updates the Welcome button's icon, and the native bar, when the welcome text appears or goes away.
##
## [param showing]: true while it is on screen.
func _update_welcome_button(showing: bool) -> void:
	if _welcome_button != null:      # the native bar draws its own icon
		_welcome_button.icon = load(ICON_DIR + ("GlobeIconSelected" if showing else "GlobeIcon") + ".png")
	NativeUI.refresh_toolbar()

## Adds a button with an icon and a label to Godot's toolbar, sized for the platform (buttons share the row on a
## phone).
##
## [param icon_name]: the icon file's name in [constant ICON_DIR], without ".png".
## [param label]: the text under the icon.
## [param tip]: the tooltip.
## [param action]: the Callable run when pressed.
## Returns: the Button.
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

## Builds the button bar. Where there is native code (iOS, macOS, Android) it is a native view along the bottom of the
## window and Godot builds nothing; if it has not come up after 3 seconds (its window could not be found), Godot's own
## bar is used instead. Otherwise (Windows, Linux, or a build without the extension) Godot's bar is built, along the
## top on a desktop and along the bottom on a phone.
func _build_toolbar() -> void:
	if NativeUI.toolbar_wanted() and NativeUI.show_toolbar(self):
		_globe.intro_changed.connect(func(_showing: bool) -> void: NativeUI.refresh_toolbar())
		_place_toolbar()
		# If the native bar has not come up after a few seconds (its window could not be found), use Godot's own.
		get_tree().create_timer(3.0).timeout.connect(func() -> void:
			if NativeUI.toolbar_height() == 0 and _toolbar_bar == null:
				NativeUI.give_up_toolbar()
				_build_godot_toolbar()
				_place_toolbar())
		return
	_build_godot_toolbar()

## Builds Godot's own toolbar: a panel with a scrolling row (a wrapping grid on phones) of buttons: About, Debugger,
## Live Data, Preferences, Lock, Reset View, Snapshot, Record, Earthquakes, Welcome and More. The native bar
## ([method native_toolbar]) lists the same commands.
func _build_godot_toolbar() -> void:
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
	_video_button = _icon_button("VideoIcon", "Record", "Record a video of the view; press again to stop.", _action_video)
	_icon_button("EarthquakeIcon", "Earthquakes", "Show the list of earthquakes.", _action_quake_list)
	_welcome_button = _icon_button("GlobeIcon", "Welcome", "Show or hide the welcome text.", _globe.toggle_intro)
	_build_more_button()
	_globe.intro_changed.connect(_update_welcome_button)
	_update_welcome_button(_globe.is_intro_showing())
	_place_toolbar()   # now that the buttons exist, size the bar to the rows they need

## Creates the dialogs (Preferences, About, Today's Times, Earthquakes, Live Data, My Locations, Earthquake Regions,
## Debugger, Satellites; each is wrapped as a full-screen sheet on phones), the snapshot and video file dialogs and
## the video recorder, and connects their signals.
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
	_video_dialog = FileDialog.new()
	_video_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_video_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_video_dialog.filters = PackedStringArray(["*.mov ; QuickTime movie"])
	_video_dialog.title = "Save Video"
	_video_dialog.file_selected.connect(_start_video)
	add_child(_video_dialog)
	_recorder = load("res://scripts/core/video_recorder.gd").new()
	add_child(_recorder)
	_recorder.recording_changed.connect(_update_video_button)
	_recorder.finished.connect(func(path: String, frames: int, seconds: float) -> void:
		_status.post("Video saved to %s (%d frames, %.1f seconds)" % [path, frames, seconds], 6.0))
	_recorder.failed.connect(func(reason: String) -> void: _status.post("Could not record the video: " + reason, 6.0))

# MARK: - Actions (names follow Flatland's IBActions)

## Shows a dialog the right way for the platform: its native screen if there is one ([method NativeUI.present]); a
## full-screen sheet sliding up from the toolbar on phones; otherwise a centered window (enlarged on phones).
##
## [param w]: the dialog Window.
## [param size_hint]: a size for the window, or Vector2i.ZERO to keep its own.
func _popup(w: Window, size_hint: Vector2i = Vector2i.ZERO) -> void:
	# The dialog's native screen (SwiftUI on iOS and macOS, Compose on Android), when the extension is there.
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

## Opens Preferences.
func _action_preferences() -> void: _popup(_prefs)
## Opens About.
func _action_about() -> void: _popup(_about)
## Opens Today's Times.
func _action_times() -> void: _popup(_times)
## Opens the earthquake list.
func _action_quake_list() -> void: _popup(_quake_list)
## Opens Live Data Status.
func _action_live_status() -> void: _popup(_live_status)

## Opens Preferences on the Map page.
func _action_select_map() -> void:
	_popup(_prefs)
	var tabs := _prefs.find_children("*", "TabContainer", true, false)
	if tabs.size() > 0:
		(tabs[0] as TabContainer).current_tab = 1

## Resets the view: the flat stage's camera or the globe's (Reset View button, the R key and the context menu).
func _action_reset_view() -> void:
	if _flat.visible:
		_flat.reset_view()
	else:
		_globe.reset_view()

## The Snapshot button: grabs the picture of the view (with any dialogs that are open hidden for one frame, so they are
## not in it, even if the button is pressed again while the Save dialog is up), then asks where to save it (starting in
## the last folder used, or Pictures). The picture is taken before the dialog opens, so it shows the view at the moment
## of the press, not whenever the file is saved. See [method _save_snapshot].
func _action_snapshot() -> void:
	# Hide the open dialogs (they are drawn into the window), wait for a frame without them, and take the picture.
	var hidden: Array[Window] = []
	for child in get_children():
		if child is Window and (child as Window).visible:
			hidden.append(child as Window)
			(child as Window).visible = false
	if not hidden.is_empty():
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
	_snapshot_image = get_viewport().get_texture().get_image()
	for w in hidden:
		w.visible = true
	var d := Time.get_datetime_dict_from_system()
	_snapshot_dialog.current_file = "Flatland Snapshot %04d-%02d-%02d %02d.%02d.%02d.png" % [d["year"], d["month"], d["day"], d["hour"], d["minute"], d["second"]]
	# Open where the last snapshot was saved; the first time (or if that folder is gone), use Pictures.
	var start_dir := Settings.get_string("snapshot_dir")
	if start_dir == "" or not DirAccess.dir_exists_absolute(start_dir):
		start_dir = OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if start_dir != "":
		_snapshot_dialog.current_dir = start_dir
	_snapshot_dialog.popup_centered_ratio(0.6)

## The Record button: stops the recording in progress, or starts a new one. On a desktop a Save dialog asks for the
## file first (starting in the last video folder, or Movies); on a phone or tablet the movie goes straight to the
## Movies folder (the app's own folder if there is none). See [method _start_video].
func _action_video() -> void:
	if _recorder.is_recording():
		_recorder.stop()
		return
	var d := Time.get_datetime_dict_from_system()
	var file := "Flatland Video %04d-%02d-%02d %02d.%02d.%02d.mov" % [d["year"], d["month"], d["day"], d["hour"], d["minute"], d["second"]]
	var start_dir := Settings.get_string("video_dir")
	if start_dir == "" or not DirAccess.dir_exists_absolute(start_dir):
		start_dir = OS.get_system_dir(OS.SYSTEM_DIR_MOVIES)
	if Layout.is_phone():
		# No file dialog on a phone or tablet: the movie goes straight to the Movies folder (the app's own folder if there is none).
		if start_dir == "" or not DirAccess.dir_exists_absolute(start_dir):
			start_dir = OS.get_user_data_dir()
		_start_video(start_dir.path_join(file))
		return
	_video_dialog.current_file = file
	if start_dir != "":
		_video_dialog.current_dir = start_dir
	_video_dialog.popup_centered_ratio(0.6)

## Starts recording to a file, after the dialog has had three frames to close (so it is not in the first pictures).
## Adds ".mov" if missing and remembers the folder.
##
## [param path]: the movie file's path.
func _start_video(path: String) -> void:
	if not path.to_lower().ends_with(".mov"):
		path += ".mov"
	Settings.set_value("video_dir", path.get_base_dir())
	# Let the dialog finish closing first, so it is not in the first pictures.
	for i in range(3):
		await get_tree().process_frame
	if _recorder.start(path):
		_status.post("Recording… press Record again to stop.", 4.0)

## Changes the Record button (and the native bar's) to a red "Stop" while recording and back afterwards.
##
## [param recording]: true while recording.
func _update_video_button(recording: bool) -> void:
	if _video_button != null:
		_video_button.icon = load(ICON_DIR + ("VideoRecordingIcon" if recording else "VideoIcon") + ".png")
		_video_button.text = "Stop" if recording else "Record"
	NativeUI.refresh_toolbar()

## Saves the snapshot taken by [method _action_snapshot] as a PNG, remembers the folder and reports the result in the
## status bar.
##
## [param path]: the file path chosen in the Save dialog.
func _save_snapshot(path: String) -> void:
	if _snapshot_image != null and _snapshot_image.save_png(path) == OK:
		Settings.set_value("snapshot_dir", path.get_base_dir())
		_status.post("Snapshot saved to " + path, 5.0)
	else:
		_status.post("Could not save the snapshot.", 5.0)
	_snapshot_image = null

# MARK: - Touch pinch

## Fingers currently down: finger index to screen position.
var _touches := {}
## The distance between the first two fingers at the last event, to work out the pinch's change.
var _pinch_span := 0.0

## On macOS the mouse cursor can stay an I-beam (text cursor) after the mouse leaves a text field, because the system
## cursor is only changed when a control asks for a different shape. Called on every mouse move: unless the mouse is over
## a control that wants another shape (a text field's I-beam, a button's pointing hand, a resize edge), puts the arrow
## back. Does nothing while a menu or dialog (a [Window]) is open.
func _keep_arrow_cursor() -> void:
	# Leave the cursor alone while a menu or dialog is open: they are windows of their own and manage their own cursor.
	for child in get_children():
		if child is Window and (child as Window).visible:
			return
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered != null and hovered.get_cursor_shape(hovered.get_local_mouse_position()) != Control.CURSOR_ARROW:
		return
	DisplayServer.cursor_set_shape(DisplayServer.CURSOR_ARROW)

## Two-finger pinch on a touch screen. Godot only makes pinch (magnify) gestures from a trackpad, so pinch-to-zoom is
## worked out here from the raw touch events and sent to the visible view ([method GlobeView.pinch_zoom] or
## [method FlatStage.pinch_zoom]); while two fingers are down both views are told so the emulated one-finger drag does
## not also turn the globe.
##
## [param event]: the input event.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and OS.get_name() == "macOS":
		_keep_arrow_cursor()
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

## The distance between the first two fingers down.
##
## Returns: pixels, or 0 if fewer than two fingers are down.
func _touch_span() -> float:
	if _touches.size() < 2:
		return 0.0
	var keys := _touches.keys()
	keys.sort()
	return (_touches[keys[0]] as Vector2).distance_to(_touches[keys[1]])

## Tells both views whether a pinch is in progress.
##
## [param on]: true while two or more fingers are down.
func _pinching_view(on: bool) -> void:
	_flat.set_pinching(on)
	_globe.set_pinching(on)

# MARK: - Events

## Reacts to settings: changes the view type, updates the lock icon and native bar, shows or hides the debug grid and
## sets the background color.
##
## [param key]: the setting's key.
## [param _value]: its new value (read again from Settings).
func _on_setting_changed(key: String, _value: Variant) -> void:
	match key:
		"view_type":
			_apply_view_type()
		"world_locked":
			NativeUI.refresh_toolbar()
			if _lock_button != null:
				_lock_button.icon = load(ICON_DIR + ("LockWorldIcon" if Settings.get_bool("world_locked") else "UnlockWorldIcon") + ".png")
		"show_debug_grid":
			_debug_grid.visible = Settings.get_bool("show_debug_grid")
		"color_background":
			_bg.color = Settings.get_color("color_background")

## Phones (Godot's own toolbar): how many buttons fit in one row of the current width; the widest button decides.
##
## Returns: the number of columns (at least 1).
func _phone_toolbar_columns() -> int:
	var ins := _insets()
	var width := get_viewport_rect().size.x - ins.x - ins.z - 24.0
	var per_button := 60.0 * Layout.ui_scale()
	for b in _toolbar.get_children():   # the widest button (its label) decides how many fit
		per_button = maxf(per_button, (b as Control).get_combined_minimum_size().x + 4.0 * Layout.ui_scale())
	return clampi(int(floor(width / per_button)), 1, maxi(1, _toolbar.get_child_count()))

## The toolbar's height: the native bar measures itself; Godot's grid is one row high, or more when the buttons do not
## fit in one row.
##
## Returns: pixels.
func _phone_toolbar_height() -> int:
	if _native_toolbar_on():
		return NativeUI.toolbar_height()   # the SwiftUI bar measures itself
	if _toolbar == null or not (_toolbar is GridContainer):
		return _toolbar_height()
	var cols := _phone_toolbar_columns()
	(_toolbar as GridContainer).columns = cols
	var rows := int(ceil(float(_toolbar.get_child_count()) / float(cols)))
	return _toolbar_height() * maxi(rows, 1)

## Whether the button bar is a native view (SwiftUI, Compose; see [NativeUI]) rather than Godot's own.
##
## Returns: true if native.
func _native_toolbar_on() -> bool:
	return NativeUI.toolbar_wanted()

## Whether the bar is along the bottom of the window: on phones and wherever it is native (macOS too). Godot's own bar
## on Windows and Linux stays along the top.
##
## Returns: true for the bottom.
func _toolbar_at_bottom() -> bool:
	return Layout.is_phone() or OS.get_name() == "macOS"

## The native bar's buttons, the same commands as Godot's toolbar. NativeUI calls this
## ([method NativeUI.show_toolbar]) and again whenever [method NativeUI.refresh_toolbar] is called.
##
## Returns: an Array of {id, title, symbol, selected?, menu?}; the Record button's title, symbol and selected state
##   follow the recording, the Welcome button's state follows the welcome text, and the lock symbol follows the lock.
func native_toolbar() -> Array:
	return [
		{"id": "about", "title": "About", "symbol": "info.circle"},
		{"id": "debugger", "title": "Debugger", "symbol": "ladybug"},
		{"id": "live", "title": "Live Data", "symbol": "antenna.radiowaves.left.and.right"},
		{"id": "prefs", "title": "Preferences", "symbol": "gearshape"},
		{"id": "lock", "title": "Lock", "symbol": "lock.fill" if Settings.get_bool("world_locked") else "lock.open"},
		{"id": "reset", "title": "Reset View", "symbol": "arrow.counterclockwise"},
		{"id": "snapshot", "title": "Snapshot", "symbol": "camera"},
		{"id": "video", "title": "Stop" if _recorder != null and _recorder.is_recording() else "Record",
			"symbol": "stop.circle.fill" if _recorder != null and _recorder.is_recording() else "video",
			"selected": _recorder != null and _recorder.is_recording()},
		{"id": "quakes", "title": "Earthquakes", "symbol": "waveform.path.ecg"},
		{"id": "welcome", "title": "Welcome", "symbol": "globe", "selected": _globe.is_intro_showing()},
		{"id": "more", "title": "More", "symbol": "ellipsis.circle", "menu": [
			{"id": "times", "title": "Today's Times…"},
			{"id": "locations", "title": "My Locations…"},
			{"id": "regions", "title": "Earthquake Regions…"},
			{"id": "refresh", "title": "Refresh Earthquakes"}]},
	]

## A native bar button was tapped: runs the same action as Godot's button of that name.
##
## [param id]: the button's or menu item's id.
func native_toolbar_event(id: String) -> void:
	match id:
		"about": _action_about()
		"debugger": _popup(_debugger)
		"live": _action_live_status()
		"prefs": _action_preferences()
		"lock": Settings.set_value("world_locked", not Settings.get_bool("world_locked"))
		"reset": _action_reset_view()
		"snapshot": _action_snapshot()
		"video": _action_video()
		"quakes": _action_quake_list()
		"welcome": _globe.toggle_intro()
		"times": _on_more_menu(1)
		"locations": _on_more_menu(2)
		"regions": _on_more_menu(3)
		"refresh": _on_more_menu(4)

## The native bar's height changed (first shown, or the phone was rotated): makes room for it.
func native_toolbar_resized() -> void:
	_place_toolbar()
	_relayout()

## Puts the toolbar where it belongs: along the bottom (above the home indicator, with the views shifted up to make
## room) on phones and for the native bar, along the top for Godot's own bar on a desktop.
func _place_toolbar() -> void:
	var ins := _insets()
	if _toolbar_at_bottom():
		var bar_h := _phone_toolbar_height()
		_content.offset_top = ins.y
		_content.offset_bottom = -(bar_h + ins.w)
		if _toolbar_bar == null:
			return      # the native bar is not a Godot control and places itself
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
	elif _toolbar_bar != null:
		_toolbar_bar.anchor_left = 0.0
		_toolbar_bar.anchor_right = 1.0
		_toolbar_bar.anchor_top = 0.0
		_toolbar_bar.anchor_bottom = 0.0
		_toolbar_bar.offset_left = 0
		_toolbar_bar.offset_right = 0
		_toolbar_bar.offset_top = ins.y
		_toolbar_bar.offset_bottom = ins.y + _toolbar_height()

## Recomputes the positions that depend on the safe-area insets (after a phone is rotated or the window changes size):
## the toolbar, the FPS label and the status bar.
func _relayout() -> void:
	var ins := _insets()
	_place_toolbar()
	if not Layout.is_phone():
		return
	_fps_label.offset_right = -14 - ins.z
	var bottom_gap := 12.0 * Layout.ui_scale()
	_status.offset_bottom = -bottom_gap
	_status.offset_top = -bottom_gap - (2.0 * Layout.font(22, 0.85) * 1.5 + 36.0)

## Shows the globe or the flat map for the `view_type` setting (the cube counts as the globe), updates any view
## buttons and the lock icon, and keeps the clock at the top.
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
	if _lock_button != null:
		_lock_button.icon = load(ICON_DIR + ("LockWorldIcon" if Settings.get_bool("world_locked") else "UnlockWorldIcon") + ".png")
	# The time label is at the top on every map.
	_time_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_time_label.offset_top = 8
	_time_label.offset_bottom = 8 + 64 * maxf(1.0, Layout.ui_scale() * 0.7)

## The mouse moved over a view: shows the coordinates, with the nearest city within 150 km, in the status bar (or
## clears it when not over the map).
##
## [param lat]: latitude under the mouse.
## [param lon]: longitude under the mouse.
## [param over]: true if over the Earth or map.
func _on_hover(lat: float, lon: float, over: bool) -> void:
	if over:
		var city := CityDB.find_nearest(lat, lon, 150.0)
		var text := Geo.pretty_coordinates(lat, lon)
		if not city.is_empty():
			text += "   near " + str(city["Name"])
		_status.show_persistent(text)
	else:
		_status.show_persistent("")

## What's Here: remembers the place ([member CityDB.last_clicked]) and pops up its coordinates, nearest city, solar
## time, whether the Sun is up, and sunrise and sunset.
##
## [param lat]: latitude.
## [param lon]: longitude.
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

## Formats a time of day.
##
## [param unix]: a Unix time.
## Returns: "HH:MM" (UTC).
func _hm(unix: float) -> String:
	var d := Time.get_time_dict_from_unix_time(int(unix))
	return "%02d:%02d" % [d["hour"], d["minute"]]

## Local solar time at a longitude (corrected by the equation of time).
##
## [param lon]: longitude in degrees.
## [param unix]: Unix time (UTC).
## Returns: "HH:MM".
func _solar_time(lon: float, unix: float) -> String:
	var secs := fposmod(unix + lon * 240.0 + Solar.equation_of_time(unix) * 60.0, 86400.0)
	return "%02d:%02d" % [int(secs / 3600.0), int(fposmod(secs, 3600.0) / 60.0)]

## An earthquake was chosen in the list: turns the globe to it (when the globe is the view shown).
##
## [param lat]: its latitude.
## [param lon]: its longitude.
func _on_quake_chosen(lat: float, lon: float) -> void:
	if _globe_container.visible:
		_globe.look_at_location(lat, lon)

## A new earthquake arrived: plays the new-quake sound (loaded on first use) if sounds are on, the sound is not "No Sound"
## ([constant Settings.NO_SOUND]) and the quake meets the minimum magnitude.
##
## [param q]: the quake Dictionary.
func _on_new_quake(q: Dictionary) -> void:
	if q["magnitude"] < Settings.get_float("quake_min_magnitude"):
		return
	if Settings.get_bool("enable_sounds"):
		var file := Settings.get_string("quake_sound")
		if file == Settings.NO_SOUND:
			return
		if not _sounds.has(file):
			_sounds[file] = load("res://Assets/Sounds/" + file)
		if _sounds[file] != null:
			_player.stream = _sounds[file]
			_player.play()

## Like Flatland, the biggest new quake stays in the status bar (for ten minutes) whenever nothing else is being
## shown.
##
## [param q]: the quake Dictionary.
func _on_biggest_new_quake(q: Dictionary) -> void:
	var d := Time.get_datetime_dict_from_unix_time(int(q["time"]))
	_status.push("New quake: M %.1f %s, %04d-%02d-%02d %02d:%02d:%02d GMT" % [q["magnitude"], q["place"],
		d["year"], d["month"], d["day"], d["hour"], d["minute"], d["second"]], 600.0)

## Updates the debug text grid (version, build, build date, uptime, memory) once a second while it is shown.
func _update_debug_grid() -> void:
	if not _debug_grid.visible:
		return
	var up := (Time.get_ticks_msec() - _start_msec) / 1000
	_debug_values["Version"].text = "v" + APP_VERSION
	_debug_values["Build"].text = "%d (Godot %s)" % [BuildInfo.build_number(), Engine.get_version_info()["string"]]
	_debug_values["Build date"].text = BuildInfo.timestamp()
	_debug_values["Uptime"].text = "%d:%02d:%02d" % [up / 3600, (up % 3600) / 60, up % 60]
	_debug_values["Memory Used"].text = "%.2f GB" % (OS.get_static_memory_usage() / 1073741824.0)

## Keyboard shortcuts: 1 globe, 2 north-centered map, 3 south-centered map, 4 rectangular map, 5 cubic world, R reset
## view.
##
## [param event]: the input event.
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_1: Settings.set_value("view_type", Settings.VIEW_GLOBE)
			KEY_2: Settings.set_value("view_type", Settings.VIEW_FLAT_NORTH)
			KEY_3: Settings.set_value("view_type", Settings.VIEW_FLAT_SOUTH)
			KEY_4: Settings.set_value("view_type", Settings.VIEW_RECT)
			KEY_5: Settings.set_value("view_type", Settings.VIEW_CUBIC)
			KEY_R: _action_reset_view()

## Every frame: on the flat map, tells it how much room the clock and status bar take; updates the FPS label twice a
## second; and handles the development flags (resize the window, save the `--shot=` picture and quit).
##
## [param delta]: seconds since the last frame.
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

## Development: replaces the real quake list with six made-up earthquakes (stopping the real fetch), for testing
## without a network (`--fake-quakes`).
func _inject_fake_quakes() -> void:
	var now := Time.get_unix_time_from_system()
	var list := [[3.0, 35.0, -118.0], [4.5, 38.0, 142.0], [5.5, -20.0, -70.0], [6.5, 10.0, 125.0], [7.5, 0.0, 0.0], [8.5, 60.0, -150.0]]
	var out: Array = []
	for i in range(list.size()):
		out.append({"id": "fake%d" % i, "magnitude": list[i][0], "place": "Test", "time": now - 600.0 * (i + 1),
			"lat": list[i][1], "lon": list[i][2], "depth": 10.0})
	QuakeService._http.cancel_request()   # keep the made-up ones: no real fetch
	QuakeService._timer.stop()
	QuakeService.quakes = out
	QuakeService.quakes_updated.emit(out)

## Development: opens a named dialog (the `--open=` flag), and with `--native-snap=` saves a picture of the native
## screen and quits.
##
## [param what]: "prefs", "home", "grid", "satellites", "map", "about", "times", "quakes", "live", "debug",
##   "locations", "regions", "click" and so on.
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
