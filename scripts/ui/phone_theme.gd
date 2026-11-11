class_name PhoneTheme
extends RefCounted
## The Theme used on phones (iOS and Android): readable text, finger-sized controls, and one button
## style everywhere (a plain rounded rectangle with text). Godot draws its own controls, so the
## defaults (tiny check boxes, drop-down arrows and spin chevrons, short square buttons) are replaced
## here once, for every dialog, instead of control by control. On desktop nothing uses this.

const TOUCH_HEIGHT := 44.0   # Apple's minimum touch target, in points
const BUTTON_FILL := Color(0.2, 0.22, 0.28)
const BUTTON_PRESSED := Color(0.27, 0.42, 0.72)
const BUTTON_BORDER := Color(0.5, 0.55, 0.68)
const BLUE := Color("#8fb8ff")

## Text size inside dialogs; icons that go with text (check marks, arrows) match it.
static func text_px() -> int:
	return Layout.font(16)

## Size of section headings: slightly larger than the text under them.
static func heading_px() -> int:
	return int(round(text_px() * 1.2))

static func build() -> Theme:
	var s := Layout.ui_scale()
	var fs := text_px()
	var base := ThemeDB.get_default_theme()
	var t := Theme.new()
	t.default_font_size = fs
	var pad_v := int(round(maxf(8.0, (TOUCH_HEIGHT * s * 0.5 - fs) * 0.5 + fs * 0.2)))
	var pad_h := int(round(fs * 0.9))
	var radius := int(round(fs * 0.5))
	# One button look for Button, OptionButton and MenuButton: a rounded rectangle with text.
	for type_name in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type_name, _button_box(BUTTON_FILL, radius, pad_h, pad_v))
		t.set_stylebox("hover", type_name, _button_box(BUTTON_FILL.lightened(0.08), radius, pad_h, pad_v))
		t.set_stylebox("pressed", type_name, _button_box(BUTTON_PRESSED, radius, pad_h, pad_v))
		t.set_stylebox("hover_pressed", type_name, _button_box(BUTTON_PRESSED, radius, pad_h, pad_v))
		t.set_stylebox("disabled", type_name, _button_box(BUTTON_FILL.darkened(0.3), radius, pad_h, pad_v))
		t.set_stylebox("focus", type_name, StyleBoxEmpty.new())
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			t.set_color(c, type_name, Color.WHITE)
	# Text fields (also the number part of a spin box).
	var field := _button_box(Color(0.1, 0.11, 0.14), radius, pad_h, pad_v)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", _button_box(Color(0.1, 0.11, 0.14), radius, pad_h, pad_v, BLUE))
	t.set_stylebox("read_only", "LineEdit", field)
	# Check boxes: only the vertical padding grows; the box itself is drawn below.
	for box_name in ["normal", "pressed", "disabled", "hover", "hover_pressed", "focus"]:
		var e := StyleBoxEmpty.new()
		e.content_margin_top = pad_v
		e.content_margin_bottom = pad_v
		e.content_margin_left = 0
		e.content_margin_right = 0
		t.set_stylebox(box_name, "CheckBox", e)
	# Check boxes about as big as the text, and clearly visible whether on or off.
	var box_px := int(round(fs * 1.05))
	for n in ["checked", "checked_disabled"]:
		t.set_icon(n, "CheckBox", _box_icon(box_px, true))
	for n in ["unchecked", "unchecked_disabled"]:
		t.set_icon(n, "CheckBox", _box_icon(box_px, false))
	t.set_constant("h_separation", "CheckBox", int(round(fs * 0.5)))
	# Drop-down arrows as big as the text.
	t.set_icon("arrow", "OptionButton", _chevron(fs, true, false))
	t.set_constant("arrow_margin", "OptionButton", int(round(fs * 0.4)))
	t.set_constant("h_separation", "OptionButton", int(round(fs * 0.4)))
	# Tree rows (lists of maps, earthquakes, satellites): the same check boxes and arrows.
	t.set_icon("checked", "Tree", _box_icon(box_px, true))
	t.set_icon("unchecked", "Tree", _box_icon(box_px, false))
	var tri := _triangle(int(round(fs * 0.8)))   # folding arrows: open (down) and closed (right)
	t.set_icon("arrow", "Tree", tri)
	var right_img := tri.get_image()
	right_img.rotate_90(COUNTERCLOCKWISE)
	t.set_icon("arrow_collapsed", "Tree", ImageTexture.create_from_image(right_img))
	# Spin box chevrons (the increase/decrease control): large and light.
	var cw := int(round(fs * 1.6))
	var ch := int(round(fs * 0.9))
	for pair in [["up", false], ["down", true]]:   # [name, points down]
		for suffix in ["", "_hover", "_pressed", "_disabled"]:
			t.set_icon(pair[0] + suffix, "SpinBox", _chevron_wide(cw, ch, pair[1]))
		for suffix in ["_icon_modulate", "_hover_icon_modulate", "_pressed_icon_modulate"]:
			t.set_color(pair[0] + suffix, "SpinBox", Color(0.92, 0.94, 1.0))
	t.set_constant("buttons_width", "SpinBox", int(round(fs * 2.2)))
	t.set_constant("set_min_buttons_width_from_icons", "SpinBox", 1)
	# Dividers (between the Preferences section buttons): clearly visible.
	var line := StyleBoxLine.new()
	line.color = BUTTON_BORDER
	line.thickness = 3
	line.vertical = true
	t.set_stylebox("separator", "VSeparator", line)
	t.set_constant("separation", "VSeparator", int(round(fs * 0.5)))
	t.set_constant("separation", "VBoxContainer", int(round(fs * 0.4)))
	t.set_constant("separation", "HBoxContainer", int(round(fs * 0.4)))
	return t

static func _button_box(fill: Color, radius: int, pad_h: int, pad_v: int, border: Color = BUTTON_BORDER) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	return sb

## Distance from point p to the segment a-b.
static func _seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)

## A rounded square: outlined and dark when off, solid blue with a white tick when on.
static func _box_icon(n: int, checked: bool) -> Texture2D:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var edge := maxf(2.0, n * 0.1)
	var r := n * 0.22
	var half := n * 0.5
	var stroke := maxf(2.0, n * 0.12)
	var tick_a := Vector2(n * 0.24, n * 0.52)
	var tick_b := Vector2(n * 0.43, n * 0.72)
	var tick_c := Vector2(n * 0.78, n * 0.3)
	for y in range(n):
		for x in range(n):
			var p := Vector2(x + 0.5, y + 0.5)
			var dx := maxf(absf(p.x - half) - (half - r), 0.0)
			var dy := maxf(absf(p.y - half) - (half - r), 0.0)
			var d := sqrt(dx * dx + dy * dy)
			var col := Color(0, 0, 0, 0)
			if d <= r - edge:
				col = BUTTON_PRESSED.lightened(0.1) if checked else Color(0.08, 0.09, 0.12)
			elif d <= r:
				col = BLUE if checked else Color(0.72, 0.75, 0.82)
			if checked and d <= r - edge and minf(_seg(p, tick_a, tick_b), _seg(p, tick_b, tick_c)) <= stroke * 0.5:
				col = Color.WHITE
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

## A downward chevron (v) of the given square size, for drop-down arrows.
static func _chevron(n: int, down: bool, _unused: bool) -> Texture2D:
	return _chevron_wide(n, int(round(n * 0.6)), down)

## A chevron w pixels wide and h tall, pointing down or up.
static func _chevron_wide(w: int, h: int, down: bool) -> Texture2D:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var stroke := maxf(2.0, h * 0.28)
	var pad := stroke
	var l := Vector2(pad, pad if down else h - pad)
	var m := Vector2(w * 0.5, h - pad if down else pad)
	var rr := Vector2(w - pad, pad if down else h - pad)
	for y in range(h):
		for x in range(w):
			var p := Vector2(x + 0.5, y + 0.5)
			if minf(_seg(p, l, m), _seg(p, m, rr)) <= stroke * 0.5:
				img.set_pixel(x, y, Color(0.95, 0.96, 1.0, 1.0))
	return ImageTexture.create_from_image(img)

## A filled triangle pointing down, n pixels across.
static func _triangle(n: int) -> Texture2D:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in range(n):
		var half := (1.0 - (y + 0.5) / n) * n * 0.5   # half the width at this row: widest at the top
		for x in range(n):
			if absf(x + 0.5 - n * 0.5) <= half:
				img.set_pixel(x, y, Color(0.8, 0.85, 1.0, 1.0))
	return ImageTexture.create_from_image(img)
