extends Window
## Editor for earthquake regions (Flatland's earthquake region editor). When any region is
## enabled, only earthquakes meeting a region's limits are shown. Stored in user://regions.json.

## The list of regions (name, enabled, bounds, magnitude range).
var _tree: Tree
## The text box for the region's name.
var _name: LineEdit
## The number boxes for the [constant FIELDS], by key.
var _spins: Dictionary = {}
## The check box that enables or disables the region being edited.
var _enabled: CheckBox
## The color button for the region's color (the tint of its row).
var _color: ColorPickerButton

## The numeric fields of a region: [key, label, minimum, maximum, default value]. The rectangle is given by two
## corners, upper-left (lat1, lon1) and lower-right (lat2, lon2); a region with lon1 greater than lon2 crosses the
## antimeridian (see [method QuakeService.region_matches]).
const FIELDS := [["lat1", "Upper-left latitude", -90, 90, 60.0], ["lon1", "Upper-left longitude", -180, 180, -130.0],
		["lat2", "Lower-right latitude", -90, 90, 20.0], ["lon2", "Lower-right longitude", -180, 180, -60.0],
		["min_mag", "Minimum magnitude", 0, 10, 4.0], ["max_mag", "Maximum magnitude", 0, 10, 10.0],
		["max_age_days", "Maximum age (days)", 0.1, 30, 7.0]]

## Builds the window: an explanatory note, the list of regions, the name box, the number fields, the enabled box and
## color button, and Add / Update / Delete / Close buttons.
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
	grid.columns = 2 if Layout.is_phone() else 4
	vb.add_child(grid)
	for f in FIELDS:
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
	var bar := PhoneSheet.button_bar()
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

## Refills the list from [member CityDB.regions] and tells NativeUI the data changed.
func populate() -> void:
	NativeUI.refresh(self)
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

## Reads the form into a region.
##
## Returns: a Dictionary with "name" (or "Region" if empty), "enabled", "color" and every field of [constant FIELDS].
func _current() -> Dictionary:
	var d := {"name": _name.text if _name.text != "" else "Region", "enabled": _enabled.button_pressed,
		"color": "#" + _color.color.to_html(false)}
	for k in _spins:
		d[k] = (_spins[k] as SpinBox).value
	return d

## A region was selected in the list: loads it into the form.
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

## Adds the form's region to [member CityDB.regions], saves ([method CityDB.save_regions]) and refreshes the list.
func _on_add() -> void:
	CityDB.regions.append(_current())
	CityDB.save_regions()
	populate()

## Replaces the selected region with the form's contents and saves. Does nothing if none is selected.
func _on_update() -> void:
	var it := _tree.get_selected()
	if it != null:
		CityDB.regions[it.get_metadata(0)] = _current()
		CityDB.save_regions()
		populate()

## Deletes the selected region and saves. Does nothing if none is selected.
func _on_delete() -> void:
	var it := _tree.get_selected()
	if it != null:
		CityDB.regions.remove_at(it.get_metadata(0))
		CityDB.save_regions()
		populate()

# MARK: - Native (SwiftUI) version; see NativeUI
# The native screen drives this dialog's own controls, so the list, the form and the saving stay in one place.

## Describes the dialog for the native UI. The native screen drives this dialog's own controls, so the list, the form
## and the saving stay in one place: a row per region, then fields (name, enabled, color, each number) and Add /
## Update Selected / Delete Selected actions.
##
## Returns: {"screen": ..., "values": {"reg.*": ...}}.
func native_screen() -> Dictionary:
	var selected := -1
	if _tree.get_selected() != null:
		selected = int(_tree.get_selected().get_metadata(0))
	var items: Array = [{"type": "paragraph", "style": "caption", "title": "Regions are rectangles (upper-left to lower-right). With any region enabled, earthquakes are shown only inside regions, using each region's limits."}]
	for i in range(CityDB.regions.size()):
		var r: Dictionary = CityDB.regions[i]
		items.append({"type": "row", "id": "reg:%d" % i, "leading": "▭", "accent": str(r.get("color", "#ffcc00")),
			"title": str(r["name"]), "subtitle": "%.1f,%.1f to %.1f,%.1f · M%.1f–%.1f" % [r["lat1"], r["lon1"], r["lat2"], r["lon2"], r["min_mag"], r["max_mag"]],
			"detail": "On" if r.get("enabled", true) else "Off", "selected": i == selected})
	items.append_array([{"type": "section", "title": "Details"},
		{"type": "text", "key": "reg.name", "title": "Region name"},
		{"type": "toggle", "key": "reg.enabled", "title": "Enabled"},
		{"type": "color", "key": "reg.color", "title": "Color"}])
	var values := {"reg.name": _name.text, "reg.enabled": _enabled.button_pressed, "reg.color": "#" + _color.color.to_html(false)}
	for f in FIELDS:
		items.append({"type": "number", "key": "reg." + f[0], "title": f[1], "min": f[2], "max": f[3], "step": 0.1})
		values["reg." + f[0]] = (_spins[f[0]] as SpinBox).value
	items.append_array([{"type": "section", "title": "Actions"},
		{"type": "action", "id": "add", "title": "Add", "style": "prominent"},
		{"type": "action", "id": "update", "title": "Update Selected"},
		{"type": "action", "id": "delete", "title": "Delete Selected", "style": "destructive"}])
	return {"screen": {"title": "Earthquake Regions", "pages": [{"title": "Regions", "items": items}]}, "values": values}

## Handles native events: "reg.*" values are copied into the form's controls; a "reg:N" action selects region N;
## "add", "update" and "delete" run the matching buttons. The screen is refreshed afterwards.
##
## [param kind]: "value", "action" or "closed".
## [param key]: the control or button id.
## [param value]: the new value for "value" events.
func native_event(kind: String, key: String, value: Variant) -> void:
	if kind == "value":
		if key == "reg.name":
			_name.text = str(value)
		elif key == "reg.enabled":
			_enabled.button_pressed = bool(value)
		elif key == "reg.color":
			_color.color = Color(str(value))
		elif key.begins_with("reg.") and _spins.has(key.substr(4)):
			(_spins[key.substr(4)] as SpinBox).value = float(value)
		return
	if kind != "action":
		return
	if key.begins_with("reg:"):
		var i := int(key.substr(4))
		var root := _tree.get_root()
		if root != null and i >= 0 and i < root.get_child_count():
			root.get_child(i).select(0)
			_on_selected()
	else:
		match key:
			"add": _on_add()
			"update": _on_update()
			"delete": _on_delete()
	NativeUI.refresh(self)
