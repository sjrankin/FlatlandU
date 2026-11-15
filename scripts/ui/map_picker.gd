extends SplitContainer
## Map chooser (Flatland's map preference panel): grouped list of every map plus a preview.

## Emitted when the user picks a map (the setting is already saved).
##
## [param map_name]: the map's name, as stored in the `map_type` setting.
signal map_chosen(map_name: String)

## The grouped list of maps.
var _tree: Tree
## The picture of the selected map.
var _preview: TextureRect
## Text under the preview: the map's name and file.
var _caption: Label
## File name of the preview being shown; the preview updates when [signal MapCatalog.texture_ready] reports that file.
var _preview_file := ""

## Builds the picker: a Tree of maps grouped by [method MapCatalog.group_for] beside (above, on phones) a preview and
## caption. Selects the current map, and connects selection and texture arrival.
func _ready() -> void:
	_tree = Tree.new()
	_tree.hide_root = true
	if Layout.is_phone():
		# List above, preview below, instead of side by side.
		vertical = true
		custom_minimum_size = Vector2(0, 760.0 * Layout.ui_scale() * 0.6)
		_tree.custom_minimum_size.y = 300.0 * Layout.ui_scale() * 0.6
	else:
		custom_minimum_size = Vector2(640, 380)
		_tree.custom_minimum_size.x = 260
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_tree)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.custom_minimum_size = Vector2(0, 160) if Layout.is_phone() else Vector2(320, 200)
	right.add_child(_preview)
	_caption = Label.new()
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if Layout.is_phone():
		_caption.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY   # a long file name must not widen the page
	right.add_child(_caption)
	add_child(right)
	var root := _tree.create_item()
	var groups := {}
	var current := Settings.get_string("map_type")
	for m in MapCatalog.maps:
		var g := MapCatalog.group_for(m)
		if not groups.has(g):
			var gi := _tree.create_item(root)
			gi.set_text(0, g)
			gi.set_selectable(0, false)
			gi.set_custom_color(0, Color("#8fb8ff"))
			groups[g] = gi
		var it := _tree.create_item(groups[g])
		it.set_text(0, str(m["name"]))
		it.set_metadata(0, m)
		if m["name"] == current:
			it.select(0)
			_show_preview(m)
	_tree.item_selected.connect(_on_selected)
	_tree.item_activated.connect(_on_selected)
	MapCatalog.texture_ready.connect(func(file: String, tex: Texture2D) -> void:
		if file == _preview_file and is_instance_valid(_preview):
			_preview.texture = tex)

## The user selected or double-clicked a map: shows its preview, saves it as the `map_type` setting and emits
## [signal map_chosen]. Group headings do nothing.
func _on_selected() -> void:
	var it := _tree.get_selected()
	if it == null or it.get_metadata(0) == null:
		return
	var m: Dictionary = it.get_metadata(0)
	_show_preview(m)
	Settings.set_value("map_type", m["name"])
	map_chosen.emit(m["name"])

## Shows a map's globe image (loading it with [method MapCatalog.request] if needed) and caption.
##
## [param m]: the map Dictionary.
func _show_preview(m: Dictionary) -> void:
	_preview_file = str(m["globe"])
	_caption.text = "%s  (%s)" % [m["name"], _preview_file]
	_preview.texture = MapCatalog.request(_preview_file)
