extends Window
## Editor for earthquake regions (Flatland's earthquake region editor). When any region is
## enabled, only earthquakes meeting a region's limits are shown. Stored in user://regions.json.

var _tree: Tree
var _name: LineEdit
var _spins: Dictionary = {}
var _enabled: CheckBox
var _color: ColorPickerButton

func _ready() -> void:
	title = "Earthquake Regions"
	size = Vector2i(760, 560)
	exclusive = false
	transient = true
	close_requested.connect(hide)
	var root := PanelContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var vb := VBoxContainer.new()
	root.add_child(vb)
	var note := Label.new()
	note.text = "Regions are rectangles (upper-left to lower-right). With any region enabled, earthquakes are shown only inside regions, using each region's limits."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(note)
	_tree = Tree.new()
	_tree.columns = 4
	_tree.column_titles_visible = true
	for i in range(4):
		_tree.set_column_title(i, ["Name", "Enabled", "Bounds", "Magnitude"][i])
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_selected.connect(_on_selected)
	vb.add_child(_tree)
	_name = LineEdit.new()
	_name.placeholder_text = "Region name"
	vb.add_child(_name)
	var grid := GridContainer.new()
	grid.columns = 4
	vb.add_child(grid)
	for f in [["lat1", "Upper-left latitude", -90, 90, 60.0], ["lon1", "Upper-left longitude", -180, 180, -130.0],
			["lat2", "Lower-right latitude", -90, 90, 20.0], ["lon2", "Lower-right longitude", -180, 180, -60.0],
			["min_mag", "Minimum magnitude", 0, 10, 4.0], ["max_mag", "Maximum magnitude", 0, 10, 10.0],
			["max_age_days", "Maximum age (days)", 0.1, 30, 7.0]]:
		var l := Label.new()
		l.text = f[1]
		grid.add_child(l)
		var s := SpinBox.new()
		s.min_value = f[2]
		s.max_value = f[3]
		s.step = 0.1
		s.value = f[4]
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(s)
		_spins[f[0]] = s
	_enabled = CheckBox.new()
	_enabled.text = "Enabled"
	_enabled.button_pressed = true
	_color = ColorPickerButton.new()
	_color.color = Color("#ffcc00")
	_color.custom_minimum_size = Vector2(70, 28)
	var bar := HBoxContainer.new()
	vb.add_child(bar)
	bar.add_child(_enabled)
	bar.add_child(_color)
	for pair in [["Add", _on_add], ["Update", _on_update], ["Delete", _on_delete]]:
		var b := Button.new()
		b.text = pair[0]
		b.pressed.connect(pair[1])
		bar.add_child(b)
	var close := Button.new()
	close.text = "Close"
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(hide)
	bar.add_child(close)
	about_to_popup.connect(populate)
	populate()

func populate() -> void:
	_tree.clear()
	var root := _tree.create_item()
	for i in range(CityDB.regions.size()):
		var r: Dictionary = CityDB.regions[i]
		var it := _tree.create_item(root)
		it.set_text(0, str(r["name"]))
		it.set_text(1, "yes" if r.get("enabled", true) else "no")
		it.set_text(2, "%.1f,%.1f to %.1f,%.1f" % [r["lat1"], r["lon1"], r["lat2"], r["lon2"]])
		it.set_text(3, "M%.1f–%.1f" % [r["min_mag"], r["max_mag"]])
		it.set_custom_bg_color(0, Color(str(r.get("color", "#ffcc00"))).darkened(0.6))
		it.set_metadata(0, i)

func _current() -> Dictionary:
	var d := {"name": _name.text if _name.text != "" else "Region", "enabled": _enabled.button_pressed,
		"color": "#" + _color.color.to_html(false)}
	for k in _spins:
		d[k] = (_spins[k] as SpinBox).value
	return d

func _on_selected() -> void:
	var it := _tree.get_selected()
	if it == null:
		return
	var r: Dictionary = CityDB.regions[it.get_metadata(0)]
	_name.text = str(r["name"])
	_enabled.button_pressed = r.get("enabled", true)
	_color.color = Color(str(r.get("color", "#ffcc00")))
	for k in _spins:
		(_spins[k] as SpinBox).value = r[k]

func _on_add() -> void:
	CityDB.regions.append(_current())
	CityDB.save_regions()
	populate()

func _on_update() -> void:
	var it := _tree.get_selected()
	if it != null:
		CityDB.regions[it.get_metadata(0)] = _current()
		CityDB.save_regions()
		populate()

func _on_delete() -> void:
	var it := _tree.get_selected()
	if it != null:
		CityDB.regions.remove_at(it.get_metadata(0))
		CityDB.save_regions()
		populate()
