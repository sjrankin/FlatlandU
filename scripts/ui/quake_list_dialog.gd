extends Window
## Table of current earthquakes (Flatland's Earthquake Viewer).

## Emitted when the user double-clicks a quake (or taps it on a phone), so main.gd can turn the globe to it.
##
## [param lat]: the quake's latitude.
## [param lon]: the quake's longitude.
signal quake_chosen(lat: float, lon: float)

## The table of quakes (magnitude, location, time, depth, coordinates).
var _tree: Tree
## Text under the table: how many are shown and the feed status.
var _status: Label

## Builds the window: the table, a status label and Refresh and Close buttons; repopulates when quakes update and each
## time it opens.
func _ready() -> void:
	title = "Earthquakes"
	size = Vector2i(860, 480)
	exclusive = false
	transient = true
	close_requested.connect(hide)
	var root := PanelContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var vb := VBoxContainer.new()
	root.add_child(vb)
	_tree = Tree.new()
	_tree.columns = 5
	_tree.column_titles_visible = true
	for i in range(5):
		_tree.set_column_title(i, ["Mag", "Location", "Time (UTC)", "Depth (km)", "Coordinates"][i])
	_tree.set_column_expand(1, true)
	_tree.set_column_expand_ratio(1, 3)
	_tree.set_column_clip_content(1, true)
	_tree.set_column_custom_minimum_width(0, 60)
	_tree.set_column_custom_minimum_width(2, 170)
	_tree.set_column_custom_minimum_width(3, 90)
	_tree.set_column_custom_minimum_width(4, 190)
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_activated.connect(_on_activated)
	vb.add_child(_tree)
	var bar := HBoxContainer.new()
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_status)
	var refresh := Button.new()
	refresh.text = "Refresh"
	refresh.pressed.connect(QuakeService.refresh)
	bar.add_child(refresh)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(hide)
	bar.add_child(close)
	vb.add_child(bar)
	QuakeService.quakes_updated.connect(func(_q: Array) -> void: populate())
	about_to_popup.connect(populate)
	populate()

## Refills the table from [method QuakeService.visible_quakes], coloring each magnitude with
## [method QuakeService.magnitude_color], and updates the status text. Also tells NativeUI the data changed.
func populate() -> void:
	NativeUI.refresh(self)
	_tree.clear()
	var root := _tree.create_item()
	var list := QuakeService.visible_quakes()
	for q in list:
		var it := _tree.create_item(root)
		it.set_text(0, "%.1f" % q["magnitude"])
		it.set_custom_color(0, QuakeService.magnitude_color(q["magnitude"]))
		it.set_text(1, q["place"])
		var d := Time.get_datetime_dict_from_unix_time(int(q["time"]))
		it.set_text(2, "%04d-%02d-%02d %02d:%02d:%02d" % [d["year"], d["month"], d["day"], d["hour"], d["minute"], d["second"]])
		it.set_text(3, "%.1f" % q["depth"])
		it.set_text(4, Geo.pretty_coordinates(q["lat"], q["lon"], 2))
		it.set_metadata(0, q)
	_status.text = "%d earthquakes shown (%d in feed). %s" % [list.size(), QuakeService.quakes.size(), QuakeService.last_status]

## A row was double-clicked: emits [signal quake_chosen] with its position.
func _on_activated() -> void:
	var it := _tree.get_selected()
	if it != null:
		var q: Dictionary = it.get_metadata(0)
		quake_chosen.emit(q["lat"], q["lon"])

# MARK: - Native (SwiftUI) version; see NativeUI

## The quakes behind the rows currently shown in the native screen, in order, so a tapped row id ("quake:N") can be
## turned into a quake.
var _native_list: Array = []

## Describes the dialog for the native UI: one "row" per quake (magnitude, place, time and coordinates, depth), a
## status paragraph and a Refresh button. Stores the list in [member _native_list].
##
## Returns: {"screen": ..., "values": {}}.
func native_screen() -> Dictionary:
	_native_list = QuakeService.visible_quakes()
	var items: Array = []
	for i in range(_native_list.size()):
		var q: Dictionary = _native_list[i]
		var d := Time.get_datetime_dict_from_unix_time(int(q["time"]))
		items.append({"type": "row", "id": "quake:%d" % i, "leading": "%.1f" % q["magnitude"],
			"accent": "#" + QuakeService.magnitude_color(q["magnitude"]).to_html(false), "title": str(q["place"]),
			"subtitle": "%04d-%02d-%02d %02d:%02d:%02d UTC · %s" % [d["year"], d["month"], d["day"], d["hour"], d["minute"], d["second"], Geo.pretty_coordinates(q["lat"], q["lon"], 2)],
			"detail": "%.1f km" % q["depth"]})
	items.append({"type": "section", "title": "Status"})
	items.append({"type": "paragraph", "style": "caption", "title": "%d earthquakes shown (%d in feed). %s" % [_native_list.size(), QuakeService.quakes.size(), QuakeService.last_status]})
	items.append({"type": "action", "id": "refresh", "title": "Refresh", "style": "prominent"})
	return {"screen": {"title": "Earthquakes", "pages": [{"title": "Earthquakes", "items": items}]}, "values": {}}

## Handles native events: "refresh" fetches new data; "quake:N" emits [signal quake_chosen] and closes the screen so
## the globe, now pointing at the quake, can be seen.
##
## [param kind]: "value", "action" or "closed".
## [param key]: the button or row id.
## [param _value]: unused.
func native_event(kind: String, key: String, _value: Variant) -> void:
	if kind != "action":
		return
	if key == "refresh":
		QuakeService.refresh()
	elif key.begins_with("quake:"):
		var i := int(key.substr(6))
		if i >= 0 and i < _native_list.size():
			var q: Dictionary = _native_list[i]
			quake_chosen.emit(q["lat"], q["lon"])
			NativeUI.close()   # so the globe, now pointing at the quake, can be seen
