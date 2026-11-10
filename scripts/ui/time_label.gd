extends Label
## The large UTC/local time readout at the top (or bottom, for south-centered) of the view.

func _ready() -> void:
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Menlo", "SF Mono", "Monaco", "Courier New", "monospace"])
	f.font_weight = 600
	add_theme_font_override("font", f)
	add_theme_font_size_override("font_size", 46)
	add_theme_color_override("font_color", Color.WHITE)
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 6)
	var t := Timer.new()
	t.wait_time = 0.25
	t.autostart = true
	t.timeout.connect(update_text)
	add_child(t)
	Settings.changed.connect(func(_k: String, _v: Variant) -> void: update_text())
	update_text()

func update_text() -> void:
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
