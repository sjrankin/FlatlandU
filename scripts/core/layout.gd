class_name Layout
extends RefCounted
## Phone-aware sizing. On iPhone and Android the UI is scaled up and kept clear of the camera cut-out
## (Dynamic Island), the rounded corners and the home indicator. On desktop everything is unchanged.
##
## Development flags (after `--`): `--phone` pretends to be a phone, `--ui-scale=N` sets the scale and
## `--safe=top,bottom,left,right` sets the safe-area insets in pixels, so the phone layout can be checked
## in a normal window.

static var _forced_phone := false
static var _forced_scale := -1.0
static var _forced_safe: Variant = null
static var _parsed := false

static func _parse() -> void:
	if _parsed:
		return
	_parsed = true
	for arg in OS.get_cmdline_user_args():
		if arg == "--phone":
			_forced_phone = true
		elif arg.begins_with("--ui-scale="):
			_forced_scale = float(arg.substr(11))
		elif arg.begins_with("--safe="):
			var p := arg.substr(7).split_floats(",")
			if p.size() == 4:
				_forced_safe = p

## True on iOS (or with the `--phone` development flag). iOS has no menu bar, so the app hides it there.
static func is_ios() -> bool:
	_parse()
	return _forced_phone or OS.get_name() == "iOS"

static func is_phone() -> bool:
	_parse()
	return _forced_phone or OS.has_feature("mobile")

## Multiplier for fonts and control sizes: 1 on desktop, about 2.4 on a 3x iPhone.
static func ui_scale() -> float:
	_parse()
	if _forced_scale > 0.0:
		return _forced_scale
	if not is_phone():
		return 1.0
	# Use whichever of the screen's pixel density and the window's pixel size says the screen is bigger, so a
	# phone is never left at 1x if the platform reports its scale as 1.
	var from_dpi := float(DisplayServer.screen_get_dpi()) / 192.0
	var window := DisplayServer.window_get_size()
	var from_size := float(mini(window.x, window.y)) / 540.0
	var from_scale := DisplayServer.screen_get_scale() * 0.8
	return clampf(maxf(maxf(from_dpi, from_size), from_scale), 1.0, 3.2)

## Space to keep clear on each side: x = left, y = top, z = right, w = bottom (pixels).
static func safe_insets() -> Vector4:
	_parse()
	if _forced_safe != null:
		var p: PackedFloat64Array = _forced_safe
		return Vector4(p[2], p[0], p[3], p[1])
	if not OS.has_feature("mobile"):
		return Vector4.ZERO
	var window_size := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO
	return Vector4(
		maxf(0.0, safe.position.x),
		maxf(0.0, safe.position.y),
		maxf(0.0, window_size.x - safe.end.x),
		maxf(0.0, window_size.y - safe.end.y))

## A font size for phones: `base` scaled by the UI scale (times `bias`), or `base` unchanged on desktop.
static func font(base: int, bias: float = 1.0) -> int:
	if not is_phone():
		return base
	return int(round(base * ui_scale() * bias))
