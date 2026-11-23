extends Label
## The large UTC/local time readout at the top (or bottom, for south-centered) of the view.

## How long the clock stays bright red after an earthquake arrives, in seconds.
const ALERT_HOLD := 60.0
## How long the colour then takes to fade back to white, in seconds.
const ALERT_FADE := 30.0
## The clock colour right after an earthquake.
const ALERT_COLOR := Color(1.0, 0.05, 0.05)

## When the latest earthquake arrived, in seconds since the app started (`Time.get_ticks_msec() / 1000`); far in the
## past when none has. A newer earthquake resets it, so the minute starts over.
var _alert_start := -1000000.0

## Builds the clock: centered, in the bundled Noto Sans (its digits are all the same width and its zero is plain,
## unlike the system monospaced fonts), white with a black outline. Starts a 0.25 s timer that keeps the text current
## and also updates it when any setting changes.
func _ready() -> void:
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Noto Sans (bundled): its digits are all the same width and its zero is plain, not crossed or dotted, which
	# the system monospaced fonts (Menlo, SF Mono, Monaco) all have. The same face on every platform.
	add_theme_font_override("font", Geo.noto(500))
	_apply_size()
	get_viewport().size_changed.connect(_apply_size)
	add_theme_color_override("font_color", Color.WHITE)
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 6)
	var t := Timer.new()
	t.wait_time = 0.25
	t.autostart = true
	t.timeout.connect(update_text)
	add_child(t)
	Settings.changed.connect(func(_k: String, _v: Variant) -> void: update_text())
	# new_quake only announces earthquakes that arrive after the first load, so the ones already in the feed at
	# start-up do not turn the clock red (biggest_new_quake also covers the first load).
	QuakeService.new_quake.connect(func(q: Dictionary) -> void:
		if not QuakeService.visible_quakes().any(func(v: Dictionary) -> bool: return v["id"] == q["id"]):
			return   # filtered out by the user's magnitude, age or region limits
		_alert_start = Time.get_ticks_msec() / 1000.0
		update_text())
	update_text()

## Sizes the clock's text: larger in a big window (up to 2.5 times) and scaled by [method Layout.ui_scale] on phones,
## so it stays easy to read. Called at start and whenever the window size changes.
func _apply_size() -> void:
	var size_px := 46.0
	if Layout.is_phone():
		size_px = 46.0 * Layout.ui_scale() * 0.85
	else:
		size_px = 46.0 * clampf(get_viewport().get_visible_rect().size.x / 1280.0, 1.0, 2.5)
	add_theme_font_size_override("font_size", int(size_px))
	custom_minimum_size.y = size_px * 1.3

## Rewrites the clock text from the `time_label` setting: hidden for "None", otherwise UTC ("HH:MM:SS UTC") or local
## time with the zone name, with or without seconds (`time_label_seconds`). Uses [method Solar.now], so the debugger's
## clock changes show here.
func update_text() -> void:
	_update_color()
	var mode := Settings.get_string("time_label")
	visible = mode != "None"
	if not visible:
		return
	var secs := Settings.get_bool("time_label_seconds")
	var unix := Solar.now()
	if mode == "Local":
		var tz := Time.get_time_zone_from_system()
		unix += float(tz["bias"]) * 60.0
		var d := Time.get_time_dict_from_unix_time(int(unix))
		text = ("%02d:%02d:%02d %s" if secs else "%02d:%02d %s") % ([d["hour"], d["minute"], d["second"], tz["name"]] if secs else [d["hour"], d["minute"], tz["name"]])
	else:
		var d := Time.get_time_dict_from_unix_time(int(unix))
		text = ("%02d:%02d:%02d UTC" % [d["hour"], d["minute"], d["second"]]) if secs else ("%02d:%02d UTC" % [d["hour"], d["minute"]])

## Colours the clock bright red for [constant ALERT_HOLD] seconds after the latest earthquake, then fades it back to
## white over [constant ALERT_FADE] seconds.
func _update_color() -> void:
	var age := Time.get_ticks_msec() / 1000.0 - _alert_start
	var t := clampf((age - ALERT_HOLD) / ALERT_FADE, 0.0, 1.0)
	add_theme_color_override("font_color", ALERT_COLOR.lerp(Color.WHITE, t))
