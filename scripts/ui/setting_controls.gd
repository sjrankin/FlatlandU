class_name SettingControls
extends RefCounted
## Builds Godot controls that are bound to Settings keys, so dialogs apply changes immediately
## (as Flatland's preference panels do).

static func check(text: String, key: String) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = text
	cb.button_pressed = Settings.get_bool(key)
	cb.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
	Settings.changed.connect(func(k: String, v: Variant) -> void:
		if k == key and is_instance_valid(cb) and cb.button_pressed != bool(v):
			cb.set_pressed_no_signal(bool(v)))
	return cb

## items: Array of [label, value].
static func option(text: String, key: String, items: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size.x = 150
	row.add_child(lbl)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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

static func spin(text: String, key: String, min_v: float, max_v: float, step: float, suffix: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size.x = 150
	row.add_child(lbl)
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
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color("#8fb8ff"))
	return l

static func page(parent: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(box)
	scroll.add_child(margin)
	parent.add_child(scroll)
	return box

static func color(text: String, key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size.x = 220
	row.add_child(lbl)
	var cp := ColorPickerButton.new()
	cp.custom_minimum_size = Vector2(90, 28)
	cp.edit_alpha = false
	cp.color = Settings.get_color(key)
	cp.color_changed.connect(func(c: Color) -> void: Settings.set_value(key, "#" + c.to_html(false)))
	Settings.changed.connect(func(k: String, v: Variant) -> void:
		if k == key and is_instance_valid(cp):
			cp.color = Color(str(v)))
	row.add_child(cp)
	return row

## Font chooser listing the fonts installed on this system.
static func font_picker(text: String, key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size.x = 220
	row.add_child(lbl)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
