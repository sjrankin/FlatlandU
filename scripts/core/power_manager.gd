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
## - Covered or in the background: while a native sheet covers the screen, or (phones and tablets only) the app is not in front, Godot stops
##   drawing altogether (scripts and timers keep running, so the sheets still get fresh data).
## - Graphics quality: the "graphics_quality" setting (Auto, High, Medium, Low) sets the anti-aliasing and the
##   resolution the 3D views are drawn at, and whether 3D shadows are drawn. Auto is Medium on a phone, High elsewhere.
## - Screen: the "keep_screen_on" setting decides whether the phone may auto-lock while Flatland is in front.

const ACTIVE_SECONDS := 2.5     ## Auto stays at the active rate this long after the last touch
const ACTIVE_FPS := 60
const IDLE_FPS := 30
const HOT_FPS := 20
const STILL_FPS := 5            ## draw on demand, nothing animated
const LIVE_FPS := 15            ## draw on demand, something animated

var _last_input := -100.0
var _power_state := "normal"
var _covered := false
var _backgrounded := false
var _viewports: Array[SubViewport] = []

## Per level: anti-aliasing, the fraction of the screen resolution the 3D views are drawn at, and shadows.
const QUALITY := {
	"High": {"msaa": Viewport.MSAA_4X, "scale": 1.0, "shadows": true},
	"Medium": {"msaa": Viewport.MSAA_2X, "scale": 0.8, "shadows": true},
	"Low": {"msaa": Viewport.MSAA_DISABLED, "scale": 0.65, "shadows": false},
}

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

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouseButton \
			or event is InputEventKey or (event is InputEventMouseMotion and event.button_mask != 0):
		var was_idle := _is_idle()
		_last_input = Time.get_ticks_msec() / 1000.0
		if was_idle:
			_apply()   # leave the slow idle rate now, not at the next timer tick

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			_backgrounded = true
			_apply()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED:
			_backgrounded = false
			_poll_power_state()
			_apply()

## The quality level in force: "High", "Medium" or "Low".
func quality() -> String:
	var q := Settings.get_string("graphics_quality")
	if QUALITY.has(q):
		return q
	return "Medium" if Layout.is_phone() else "High"

## Whether 3D shadows may be drawn at the current quality (the "show 3D shadows" setting also applies).
func shadows_allowed() -> bool:
	return QUALITY[quality()]["shadows"]

## A 3D view calls this once; its anti-aliasing and resolution then follow the quality setting.
func register_viewport(vp: SubViewport) -> void:
	_viewports.append(vp)
	_style_viewport(vp)

func _style_viewport(vp: SubViewport) -> void:
	var q: Dictionary = QUALITY[quality()]
	vp.msaa_3d = q["msaa"]
	vp.scaling_3d_scale = q["scale"]

func _apply_quality() -> void:
	_viewports = _viewports.filter(func(v: SubViewport) -> bool: return is_instance_valid(v))
	for vp in _viewports:
		_style_viewport(vp)

## False while nothing is being drawn (a native sheet covers the screen, or the app is in the background);
## the 3D views skip their per-frame work then.
func drawing() -> bool:
	# Losing focus only pauses drawing on phones and tablets, where it means the app left the screen. A desktop window
	# that is merely behind another keeps animating.
	return not (_covered or (_backgrounded and OS.has_feature("mobile")))

## A native sheet is (not) covering the screen: stop (resume) drawing underneath it.
func set_covered(covered: bool) -> void:
	_covered = covered
	_apply()

func _is_idle() -> bool:
	return Time.get_ticks_msec() / 1000.0 - _last_input >= ACTIVE_SECONDS

## Something on screen moves by itself (radiating quake rings on the map, satellites, a spinning globe).
func _animating() -> bool:
	return Settings.get_bool("attract_mode") or Settings.get_bool("show_satellites") or quakes_animate()

## New earthquakes are marked with a moving ring on the 2D map (every indicator except "None" and the still
## "Arrow and Ring").
func quakes_animate() -> bool:
	return Settings.get_bool("enable_earthquakes") and not Settings.get_string("quake_indicator") in ["None", "Arrow and Ring"]

func power_state() -> String:
	return _power_state

## The frame rate limit now in force; 0 means not limited.
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

func _apply() -> void:
	var fps := target_fps()
	if Engine.max_fps != fps:
		Engine.max_fps = fps
	var drawing := drawing()
	if RenderingServer.render_loop_enabled != drawing:
		RenderingServer.render_loop_enabled = drawing
	var keep_on := Settings.get_bool("keep_screen_on")
	if DisplayServer.screen_is_kept_on() != keep_on:
		DisplayServer.screen_set_keep_on(keep_on)

func _poll_power_state() -> void:
	_power_state = NativeUI.power_state()
