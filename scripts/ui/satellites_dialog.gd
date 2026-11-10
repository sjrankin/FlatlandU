extends Window
## Satellites dialog: turn satellites on or off and choose which of the ten are tracked, all in one list. A
## tracked satellite shows its position right now; an unticked one is dimmed and is missing from every map.

var _tree: Tree
var _status: Label
var _items: Dictionary = {}     # NORAD id -> TreeItem

func _ready() -> void:
	title = "Satellites"
	size = Vector2i(680, 560)
	min_size = Vector2i(520, 420)
	exclusive = false
	transient = true
	close_requested.connect(hide)
	var root := PanelContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var vb := VBoxContainer.new()
	root.add_child(vb)
	vb.add_child(SettingControls.check("Show satellites on the globe and the maps", "show_satellites"))
	vb.add_child(SettingControls.section("Satellites (tick the ones to track)"))
	_tree = Tree.new()
	_tree.columns = 6
	_tree.column_titles_visible = true
	for i in range(6):
		_tree.set_column_title(i, ["Track", "Satellite", "NORAD", "Latitude", "Longitude", "Altitude"][i])
	_tree.set_column_expand(0, false)
	_tree.set_column_custom_minimum_width(0, 70)
	_tree.set_column_expand(1, true)
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size.y = 300
	_tree.item_edited.connect(_on_item_edited)
	vb.add_child(_tree)
	var tree_root := _tree.create_item()
	for entry in SatelliteService.CATALOG:
		var id := int(entry[0])
		var item := _tree.create_item(tree_root)
		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item.set_editable(0, true)
		item.set_checked(0, SatelliteService.is_tracked(id))
		item.set_text(1, str(entry[1]))
		item.set_text(2, str(id) if id > 0 else "—")
		item.set_metadata(0, id)
		_items[id] = item
	var bar := HBoxContainer.new()
	vb.add_child(bar)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bar.add_child(_status)
	var refresh := Button.new()
	refresh.text = "Refresh Data"
	refresh.pressed.connect(SatelliteService.refresh)
	bar.add_child(refresh)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(hide)
	bar.add_child(close)
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_refresh_list)
	add_child(timer)
	Settings.changed.connect(func(key: String, _v: Variant) -> void:
		if key == "tracked_satellites":
			_refresh_list())
	_refresh_list()

## The checkbox in the first column turns tracking of that satellite on or off.
func _on_item_edited() -> void:
	var item := _tree.get_edited()
	if item == null or _tree.get_edited_column() != 0:
		return
	SatelliteService.set_tracked(int(item.get_metadata(0)), item.is_checked(0))

## Update every row in place (the rows are never rebuilt, so a click is never lost): tracked satellites show
## their position now, and untracked ones are dimmed and show none.
func _refresh_list() -> void:
	if not visible:
		return
	_status.text = "Orbit data: " + SatelliteService.last_status
	var live := {}
	for s in SatelliteService.positions(Solar.now()):
		live[int(s["id"])] = s
	for id in _items.keys():
		var item: TreeItem = _items[id]
		var tracked := SatelliteService.is_tracked(int(id))
		if item.is_checked(0) != tracked:
			item.set_checked(0, tracked)
		var dim := Color(0.5, 0.5, 0.55)
		for col in range(1, 6):
			item.set_custom_color(col, Color.WHITE if tracked else dim)
		if live.has(id):
			var s: Dictionary = live[id]
			item.set_text(3, "%.2f°" % float(s["lat"]))
			item.set_text(4, "%.2f°" % float(s["lon"]))
			item.set_text(5, SatelliteService.format_altitude(float(s["alt_km"])))
		else:
			item.set_text(3, "")
			item.set_text(4, "")
			item.set_text(5, "")
