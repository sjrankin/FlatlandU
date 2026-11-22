extends Node
## Power management (autoload "PowerManager"): keeps Flatland from using more battery than it needs.
##
## - Frame rate: the "frame_rate" setting is Auto, 30, 60 or 120. Auto is 60 fps while you are touching the screen
##   and for a couple of seconds afterwards, then 30 fps (phones; on a desktop Auto is not limited).
## - Draw on demand (setting "draw_on_demand", phones): when nothing has been touched for a couple of seconds, drawing
##   drops to STILL_FPS (a static view, only the clock and sun move) or LIVE_FPS (something is animated: radiating
##   quake rings, satellites, attract mode). Touching the screen brings the chosen frame rate back at once.
## - Low Power Mode / heat: the native code reports the device's power state ("normal", "low_power", "thermal",
##   "critical"). With "follow_low_power" on, Low Power Mode or a hot device lowers the cap to 30 fps (20 when critical).
## - Window hidden (macOS): while the display sleeps, the screen is locked or the window is minimized or fully covered,
##   Godot stops drawing; a long run that kept rendering to a dark display crashed in the Metal driver.
## - Covered or in the background: while a native sheet covers the screen, or (phones and tablets only) the app is not in front, Godot stops
##   drawing altogether (scripts and timers keep running, so the sheets still get fresh data).
## - Graphics quality: the "graphics_quality" setting (Auto, High, Medium, Low) sets the anti-aliasing and the
##   resolution the 3D views are drawn at, and whether 3D shadows are drawn. Auto is Medium on a phone, High elsewhere.
## - Screen: the "keep_screen_on" setting decides whether the phone may auto-lock while Flatland is in front.

## How long the Auto frame rate stays at [constant ACTIVE_FPS] after the last touch or key press, in seconds.
const ACTIVE_SECONDS := 2.5
## The Auto frame rate cap on a phone while the user is touching the screen (and for [constant ACTIVE_SECONDS]
## afterwards).
const ACTIVE_FPS := 60
## The Auto frame rate cap on a phone when nothing has been touched for a while; also the cap in Low Power Mode or
## when the device is warm.
const IDLE_FPS := 30
## The frame rate cap when the device reports a critical heat/power state and "follow_low_power" is on.
const HOT_FPS := 20
## Draw-on-demand frame rate when idle and nothing on screen is animated (only the clock and Sun move).
const STILL_FPS := 5
## Draw-on-demand frame rate when idle but something is animated (radiating quake rings, satellites, attract mode);
## see [method _animating].
const LIVE_FPS := 15

## When the user last touched, clicked or pressed a key, in seconds since the app started (`Time.get_ticks_msec() /
## 1000`). Starts well in the past so the app begins idle.
var _last_input := -100.0
## The device's power state from [method NativeUI.power_state]: "normal", "low_power", "thermal" or "critical".
## Refreshed every 5 seconds by [method _poll_power_state].
var _power_state := "normal"
## True while a native dialog covers the window, when drawing underneath is pointless. Set by [method set_covered].
var _covered := false
## True while the app is not in front (focus lost or app paused); set from [method _notification]. Only stops drawing
## on phones and tablets, see [method drawing].
var _backgrounded := false
## False while the desktop window cannot be seen (display asleep, screen locked, window minimized or covered), from
## [method NativeUI.window_shown]. Rendering to a display macOS is not presenting to ends in a Metal fence time-out and a
## crash, so [method drawing] is false meanwhile. Refreshed by [method _apply].
var _window_shown := true
## The 3D sub-viewports registered with [method register_viewport], restyled when the graphics quality changes.
var _viewports: Array[SubViewport] = []

## The graphics quality levels: for each, the anti-aliasing mode ("msaa"), the fraction of the screen resolution the
## 3D views are drawn at ("scale") and whether 3D shadows are drawn ("shadows"). Chosen by [method quality].
const QUALITY := {
	"High": {"msaa": Viewport.MSAA_4X, "scale": 1.0, "shadows": true},
	"Medium": {"msaa": Viewport.MSAA_2X, "scale": 0.8, "shadows": true},
	"Low": {"msaa": Viewport.MSAA_DISABLED, "scale": 0.65, "shadows": false},
}

## Sets the node to keep running while the app is paused, listens for setting changes, and starts two timers: one
## every 0.5 s that re-applies the frame rate (so the idle time-out takes effect) and one every 5 s that polls the
## power state. Applies the settings once.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Settings.changed.connect(func(key: String, _v: Variant) -> void:
		if key in ["frame_rate", "follow_low_power", "keep_screen_on", "draw_on_demand"]:
			_apply()
		elif key == "graphics_quality":
			_apply_quality())
	var fast := Timer.new()
	fast.wait_time = 0.5
	fast.autostart = true
	fast.timeout.connect(_apply)
	add_child(fast)
	var slow := Timer.new()
	slow.wait_time = 5.0
	slow.autostart = true
	slow.timeout.connect(_poll_power_state)
	add_child(slow)
	_poll_power_state()
	_apply()

## Notes user activity (touch, drag, mouse button, key, or a mouse drag), so Auto frame rate and draw-on-demand know
## the user is active. If the app was idle, the frame rate is raised immediately rather than at the next timer tick.
##
## [param event]: the input event.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouseButton \
			or event is InputEventKey or (event is InputEventMouseMotion and event.button_mask != 0):
		var was_idle := _is_idle()
		_last_input = Time.get_ticks_msec() / 1000.0
		if was_idle:
			_apply()   # leave the slow idle rate now, not at the next timer tick

## Tracks whether the app is in front. Focus lost or app paused sets [member _backgrounded]; focus regained or resumed
## clears it and re-reads the power state. Either way the draw state is re-applied.
##
## [param what]: the notification constant.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			_backgrounded = true
			_apply()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED:
			_backgrounded = false
			_poll_power_state()
			_apply()

## The graphics quality in force.
##
## Returns: "High", "Medium" or "Low": the "graphics_quality" setting, or for "Auto" Medium on a phone and High
##   elsewhere.
func quality() -> String:
	var q := Settings.get_string("graphics_quality")
	if QUALITY.has(q):
		return q
	return "Medium" if Layout.is_phone() else "High"

## Whether 3D shadows may be drawn at the current quality (the "show_shadows_3d" setting also applies).
##
## Returns: true unless the quality is Low.
func shadows_allowed() -> bool:
	return QUALITY[quality()]["shadows"]

## Called once by each 3D view so its anti-aliasing and resolution follow the quality setting from then on.
##
## [param vp]: the SubViewport to manage. It is styled immediately with [method _style_viewport].
func register_viewport(vp: SubViewport) -> void:
	_viewports.append(vp)
	_style_viewport(vp)

## Applies the current quality's anti-aliasing and 3D resolution scale to one viewport.
##
## [param vp]: the SubViewport.
func _style_viewport(vp: SubViewport) -> void:
	var q: Dictionary = QUALITY[quality()]
	vp.msaa_3d = q["msaa"]
	vp.scaling_3d_scale = q["scale"]

## Restyles every registered viewport after the quality setting changed (dropping any that were freed).
func _apply_quality() -> void:
	_viewports = _viewports.filter(func(v: SubViewport) -> bool: return is_instance_valid(v))
	for vp in _viewports:
		_style_viewport(vp)

## Whether the app should be drawing at all. It is false while the window cannot be seen (see [member _window_shown]), while a native dialog covers the window, or (on phones and
## tablets only) while the app is not in front. A desktop window that is merely behind another keeps animating. The 3D
## views skip their per-frame work when this is false.
##
## Returns: true to draw. See [method set_covered].
func drawing() -> bool:
	# Losing focus only pauses drawing on phones and tablets, where it means the app left the screen. A desktop window
	# that is merely behind another keeps animating.
	return _window_shown and not (_covered or (_backgrounded and OS.has_feature("mobile")))

## A native dialog starts or stops covering the window. While covered, drawing stops, because a desktop window half
## hidden behind another can make Godot wait for the display and starve the dialog.
##
## [param covered]: true when a dialog opens, false when it closes. Called by [method NativeUI.present] and NativeUI's
##   close handler.
func set_covered(covered: bool) -> void:
	_covered = covered
	_apply()

## Whether the user has not touched anything for [constant ACTIVE_SECONDS].
##
## Returns: true when idle.
func _is_idle() -> bool:
	return Time.get_ticks_msec() / 1000.0 - _last_input >= ACTIVE_SECONDS

## Whether anything on screen moves by itself (attract mode, satellites, or animated earthquake indicators); decides
## the draw-on-demand rate.
##
## Returns: true if something animates. See [method quakes_animate].
func _animating() -> bool:
	return Settings.get_bool("attract_mode") or Settings.get_bool("show_satellites") or quakes_animate()

## Whether new earthquakes are marked with a moving ring on the 2D map: earthquakes are on and the indicator is
## neither "None" nor the still "Arrow and Ring".
##
## Returns: true if the indicator animates.
func quakes_animate() -> bool:
	return Settings.get_bool("enable_earthquakes") and not Settings.get_string("quake_indicator") in ["None", "Arrow and Ring"]

## The last power state read from the device.
##
## Returns: "normal", "low_power", "thermal" or "critical".
func power_state() -> String:
	return _power_state

## The frame rate limit that applies now, from the "frame_rate" setting (Auto, 30, 60 or 120), draw-on-demand when
## idle on a phone, and Low Power Mode or heat when "follow_low_power" is on.
##
## Returns: frames per second, or 0 for no limit.
func target_fps() -> int:
	var cap := 0
	match Settings.get_string("frame_rate"):
		"30": cap = 30
		"60": cap = 60
		"120": cap = 120
		_:   # Auto
			if Layout.is_phone():
				var recent := Time.get_ticks_msec() / 1000.0 - _last_input < ACTIVE_SECONDS
				cap = ACTIVE_FPS if recent else IDLE_FPS
	if Settings.get_bool("draw_on_demand") and Layout.is_phone() and _is_idle():
		var idle_cap := LIVE_FPS if _animating() else STILL_FPS
		cap = idle_cap if cap == 0 else mini(cap, idle_cap)
	if Settings.get_bool("follow_low_power"):
		if _power_state == "critical":
			cap = HOT_FPS
		elif _power_state != "normal" and (cap == 0 or cap > IDLE_FPS):
			cap = IDLE_FPS
	return cap

## Puts the current decisions into effect: sets the maximum frame rate ([method target_fps]), turns the render loop on
## or off ([method drawing]) and sets whether the screen may sleep ("keep_screen_on"). Cheap, so it is called often
## (timers, input, focus changes).
func _apply() -> void:
	_window_shown = NativeUI.window_shown()
	var fps := target_fps()
	if Engine.max_fps != fps:
		Engine.max_fps = fps
	var drawing := drawing()
	if RenderingServer.render_loop_enabled != drawing:
		RenderingServer.render_loop_enabled = drawing
	var keep_on := Settings.get_bool("keep_screen_on")
	if DisplayServer.screen_is_kept_on() != keep_on:
		DisplayServer.screen_set_keep_on(keep_on)

## Reads the device power state from the native code into [member _power_state].
func _poll_power_state() -> void:
	_power_state = NativeUI.power_state()
