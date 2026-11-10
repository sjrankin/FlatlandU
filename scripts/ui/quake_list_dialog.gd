extends Window
## Table of current earthquakes (Flatland's Earthquake Viewer).

signal quake_chosen(lat: float, lon: float)

var _tree: Tree
var _status: Label

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

func populate() -> void:
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

func _on_activated() -> void:
	var it := _tree.get_selected()
	if it != null:
		var q: Dictionary = it.get_metadata(0)
		quake_chosen.emit(q["lat"], q["lon"])
