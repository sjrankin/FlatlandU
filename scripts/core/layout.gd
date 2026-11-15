class_name Layout
extends RefCounted
## Phone-aware sizing. On iPhone and Android the UI is scaled up and kept clear of the camera cut-out
## (Dynamic Island), the rounded corners and the home indicator. On desktop everything is unchanged.
##
## Development flags (after `--`): `--phone` pretends to be a phone, `--ui-scale=N` sets the scale and
## `--safe=top,bottom,left,right` sets the safe-area insets in pixels, so the phone layout can be checked
## in a normal window.

## True when the `--phone` development flag was given: the app then behaves as on a phone. Set by [method _parse].
static var _forced_phone := false
## The scale from `--ui-scale=N`, or -1 when not given; overrides the computed scale in [method ui_scale].
static var _forced_scale := -1.0
## The insets from `--safe=top,bottom,left,right` as a PackedFloat64Array, or null when not given; used by [method safe_insets].
static var _forced_safe: Variant = null
## True once the command line has been read, so [method _parse] runs once.
static var _parsed := false

## Reads the development flags `--phone`, `--ui-scale=` and `--safe=` from the command line (after the `--`) into the
## `_forced_*` variables. Every public function here calls it first, and it only does work the first time.
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

## Whether this is iOS (or the `--phone` flag was given). iOS has no menu bar, so the app hides it there.
##
## Returns: true on iOS.
static func is_ios() -> bool:
	_parse()
	return _forced_phone or OS.get_name() == "iOS"

## Whether the phone/tablet layout should be used: iOS or Android (any "mobile" platform), or the `--phone` flag. Used
## all over the UI to choose sizes, dialogs and gestures.
##
## Returns: true on a phone or tablet.
static func is_phone() -> bool:
	_parse()
	return _forced_phone or OS.has_feature("mobile")

## The multiplier for fonts and control sizes: 1 on a desktop, up to about 3.2 on a high-density phone. It is the
## largest of three estimates (screen density, window size, platform scale) so a phone is never left at 1x if the
## platform reports its scale as 1.
##
## Returns: the scale (1.0 to 3.2), or the `--ui-scale=` value if given. See [method font].
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

## The space to keep clear of the screen's camera cut-out, rounded corners and home indicator.
##
## Returns: a Vector4 in pixels: x = left, y = top, z = right, w = bottom. All zero on a desktop. The `--safe=` flag
##   overrides it for testing.
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

## A font size that is scaled up on phones and left alone on a desktop.
##
## [param base]: the size for a desktop.
## [param bias]: an extra factor on phones only (default 1.0).
## Returns: `base` on a desktop, otherwise `base` times [method ui_scale] times [param bias], rounded.
static func font(base: int, bias: float = 1.0) -> int:
	if not is_phone():
		return base
	return int(round(base * ui_scale() * bias))
