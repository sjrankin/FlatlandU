extends Window
## Editor for user-defined locations (Flatland's "user POI" editor). Stored in user://user_locations.json.

var _tree: Tree
var _name: LineEdit
var _lat: SpinBox
var _lon: SpinBox
var _desc: LineEdit
var _color: ColorPickerButton

func _ready() -> void:
	title = "My Locations"
	size = Vector2i(720, 520)
	exclusive = false
	transient = true
	close_requested.connect(hide)
	var root := PanelContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var vb := VBoxContainer.new()
	root.add_child(vb)
	_tree = Tree.new()
	_tree.columns = 3
	_tree.column_titles_visible = true
	for i in range(3):
		_tree.set_column_title(i, ["Name", "Latitude", "Longitude"][i])
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_selected.connect(_on_selected)
	vb.add_child(_tree)
	var grid := GridContainer.new()
	grid.columns = 4
	vb.add_child(grid)
	_name = LineEdit.new()
	_name.placeholder_text = "Name"
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_desc = LineEdit.new()
	_desc.placeholder_text = "Description"
	_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lat = _spin(-90, 90)
	_lon = _spin(-180, 180)
	_color = ColorPickerButton.new()
	_color.color = Color("#ee44cc")
	_color.custom_minimum_size = Vector2(70, 28)
	for pair in [["Name", _name], ["Description", _desc], ["Latitude", _lat], ["Longitude", _lon], ["Color", _color]]:
		var l := Label.new()
		l.text = pair[0]
		grid.add_child(l)
		grid.add_child(pair[1])
	var bar := HBoxContainer.new()
	vb.add_child(bar)
	_button(bar, "Add", _on_add)
	_button(bar, "Update", _on_update)
	_button(bar, "Delete", _on_delete)
	_button(bar, "Use Last Clicked Location", func() -> void:
		_lat.value = CityDB.last_clicked.x
		_lon.value = CityDB.last_clicked.y)
	_button(bar, "Use Home", func() -> void:
		_lat.value = Settings.get_float("home_latitude")
		_lon.value = Settings.get_float("home_longitude"))
	var close := Button.new()
	close.text = "Close"
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(hide)
	bar.add_child(close)
	about_to_popup.connect(populate)
	populate()

func _spin(lo: float, hi: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.0001
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s

func _button(bar: HBoxContainer, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	bar.add_child(b)

func populate() -> void:
	_tree.clear()
	var root := _tree.create_item()
	for i in range(CityDB.user_pois.size()):
		var p: Dictionary = CityDB.user_pois[i]
		var it := _tree.create_item(root)
		it.set_text(0, str(p["Name"]))
		it.set_text(1, "%.4f" % p["Latitude"])
		it.set_text(2, "%.4f" % p["Longitude"])
		it.set_metadata(0, i)

func _current() -> Dictionary:
	return {"Name": _name.text if _name.text != "" else "Location", "Latitude": _lat.value, "Longitude": _lon.value,
		"Description": _desc.text, "POIType": 1, "Color": "#" + _color.color.to_html(false)}

func _on_selected() -> void:
	var it := _tree.get_selected()
	if it == null:
		return
	var p: Dictionary = CityDB.user_pois[it.get_metadata(0)]
	_name.text = str(p["Name"])
	_desc.text = str(p.get("Description", ""))
	_lat.value = p["Latitude"]
	_lon.value = p["Longitude"]
	_color.color = Color(str(p.get("Color", "#ee44cc")))

func _on_add() -> void:
	CityDB.user_pois.append(_current())
	CityDB.save_user_pois()
	populate()

func _on_update() -> void:
	var it := _tree.get_selected()
	if it != null:
		CityDB.user_pois[it.get_metadata(0)] = _current()
		CityDB.save_user_pois()
		populate()

func _on_delete() -> void:
	var it := _tree.get_selected()
	if it != null:
		CityDB.user_pois.remove_at(it.get_metadata(0))
		CityDB.save_user_pois()
		populate()
