class_name SettingControls
extends RefCounted
## Builds Godot controls that are bound to Settings keys, so dialogs apply changes immediately
## (as Flatland's preference panels do).

# MARK: - Recording (for the native iOS/macOS Preferences)
# While `recording` is on, every control built through this class also adds a plain description of
# itself to `recorded_pages`. The native Preferences (see NativeUI) is built from that description, so
# the settings are defined once, in prefs_dialog.gd, and both user interfaces stay in step.

static var recording := false
static var recorded_pages: Array = []   # [{title, items: [ {type, key, title, ...} ]}]
static var _recording_page: Dictionary = {}

static func begin_recording() -> void:
	recording = true
	recorded_pages = []
	_recording_page = {}

static func end_recording() -> void:
	recording = false

## Start a recorded page by hand (for pages not built with page()).
static func record_page(title: String) -> void:
	if recording:
		_recording_page = {"title": title, "items": []}
		recorded_pages.append(_recording_page)

static func record_item(item: Dictionary) -> void:
	if recording and not _recording_page.is_empty():
		_recording_page["items"].append(item)

## A labelled form row. On desktop the label sits left of the control; on a phone it sits above it,
## so long labels and big text never fight over the width.
static func labeled_row(text: String, label_width: float) -> BoxContainer:
	var row: BoxContainer = VBoxContainer.new() if Layout.is_phone() else HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = text
	if Layout.is_phone():
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	else:
		lbl.custom_minimum_size.x = label_width
	row.add_child(lbl)
	return row

static func check(text: String, key: String) -> CheckBox:
	record_item({"type": "toggle", "key": key, "title": text})
	var cb := CheckBox.new()
	cb.text = text
	if Layout.is_phone():
		# Long labels wrap instead of forcing the whole page wider than the screen.
		cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cb.button_pressed = Settings.get_bool(key)
	cb.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
	Settings.changed.connect(func(k: String, v: Variant) -> void:
		if k == key and is_instance_valid(cb) and cb.button_pressed != bool(v):
			cb.set_pressed_no_signal(bool(v)))
	return cb

## items: Array of [label, value].
static func option(text: String, key: String, items: Array) -> BoxContainer:
	var opts: Array = []
	for it in items:
		opts.append({"label": it[0], "value": it[1]})
	record_item({"type": "choice", "key": key, "title": text, "options": opts})
	var row := labeled_row(text, 150)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.fit_to_longest_item = false   # the longest choice must not set the page's minimum width (matters on a phone)
	ob.clip_text = true
	var current: Variant = Settings.get_value(key)
	for i in range(items.size()):
		ob.add_item(items[i][0], i)
		if items[i][1] == current:
			ob.select(i)
	ob.item_selected.connect(func(i: int) -> void: Settings.set_value(key, items[i][1]))
	Settings.changed.connect(func(k: String, v: Variant) -> void:
		if k == key and is_instance_valid(ob):
			for i in range(items.size()):
				if items[i][1] == v:
					ob.select(i))
	row.add_child(ob)
	return row

static func spin(text: String, key: String, min_v: float, max_v: float, step: float, suffix: String = "") -> BoxContainer:
	record_item({"type": "number", "key": key, "title": text, "min": min_v, "max": max_v, "step": step, "suffix": suffix})
	var row := labeled_row(text, 150)
	var sb := SpinBox.new()
	sb.min_value = min_v
	sb.max_value = max_v
	sb.step = step
	sb.suffix = suffix
	sb.value = Settings.get_float(key)
	sb.value_changed.connect(func(v: float) -> void:
		var current: Variant = Settings.get_value(key)
		Settings.set_value(key, int(v) if current is int else v))
	row.add_child(sb)
	return row

static func section(text: String) -> Label:
	record_item({"type": "section", "title": text})
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", PhoneTheme.heading_px() if Layout.is_phone() else 15)
	l.add_theme_color_override("font_color", Color("#8fb8ff"))
	return l

static func page(parent: TabContainer, title: String) -> VBoxContainer:
	record_page(title)
	var scroll := ScrollContainer.new()
	scroll.name = title
	# DISABLED passes a too-wide child's minimum width up to the window; on a phone that would push the sheet off-screen.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER if Layout.is_phone() else ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", int(round(8.0 * (Layout.ui_scale() * 0.8 if Layout.is_phone() else 1.0))))
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(round(14.0 * (Layout.ui_scale() * 0.7 if Layout.is_phone() else 1.0))))
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(box)
	scroll.add_child(margin)
	parent.add_child(scroll)
	return box

static func color(text: String, key: String) -> BoxContainer:
	record_item({"type": "color", "key": key, "title": text})
	var row := labeled_row(text, 220)
	var cp := ColorPickerButton.new()
	cp.custom_minimum_size = Vector2(90, 28) * (Layout.ui_scale() * 0.8 if Layout.is_phone() else 1.0)
	cp.edit_alpha = false
	cp.color = Settings.get_color(key)
	cp.color_changed.connect(func(c: Color) -> void: Settings.set_value(key, "#" + c.to_html(false)))
	Settings.changed.connect(func(k: String, v: Variant) -> void:
		if k == key and is_instance_valid(cp):
			cp.color = Color(str(v)))
	row.add_child(cp)
	return row

## Font chooser listing the fonts installed on this system.
static func font_picker(text: String, key: String) -> BoxContainer:
	var font_opts: Array = [{"label": "Default", "value": ""}]
	var names := Array(OS.get_system_fonts())
	names.sort()
	for f in names:
		font_opts.append({"label": str(f), "value": str(f)})
	record_item({"type": "choice", "key": key, "title": text, "options": font_opts})
	var row := labeled_row(text, 220)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.fit_to_longest_item = false
	ob.clip_text = true
	ob.add_item("Default")
	var fonts := Array(OS.get_system_fonts())
	fonts.sort()
	var current := Settings.get_string(key)
	for f in fonts:
		ob.add_item(str(f))
		if str(f) == current:
			ob.select(ob.item_count - 1)
	ob.item_selected.connect(func(i: int) -> void: Settings.set_value(key, "" if i == 0 else ob.get_item_text(i)))
	row.add_child(ob)
	return row
