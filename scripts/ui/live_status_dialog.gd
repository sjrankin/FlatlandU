extends Window
## Status of the asynchronous data Flatland retrieves (Flatland's Live Data Status view).

## Two-column grid of heading and value labels.
var _grid: GridContainer

## Builds the window: the grid of rows, a Refresh Now button (runs [method QuakeService.refresh]) and a Close button;
## refreshes the rows when quakes update or a fetch fails and each time it opens.
func _ready() -> void:
	title = "Live Data Status"
	size = Vector2i(640, 260)
	exclusive = false
	transient = true
	close_requested.connect(hide)
	var root := PanelContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var vb := VBoxContainer.new()
	root.add_child(vb)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 24)
	vb.add_child(_grid)
	var bar := HBoxContainer.new()
	var refresh := Button.new()
	refresh.text = "Refresh Now"
	refresh.pressed.connect(QuakeService.refresh)
	bar.add_child(refresh)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(hide)
	bar.add_child(close)
	vb.add_child(bar)
	QuakeService.quakes_updated.connect(func(_q: Array) -> void: update_rows())
	QuakeService.fetch_failed.connect(func(_r: String) -> void: update_rows())
	about_to_popup.connect(update_rows)
	update_rows()

## The label/value pairs shown: source, URL, enabled, fetch interval, last retrieved, status and earthquake counts.
## The Godot and native versions share them.
##
## Returns: an Array of [heading, value] pairs of text.
func _rows() -> Array:
	var last := "never"
	if QuakeService.last_fetch_unix > 0.0:
		var d := Time.get_datetime_dict_from_unix_time(int(QuakeService.last_fetch_unix))
		last = "%04d-%02d-%02d %02d:%02d:%02d UTC" % [d["year"], d["month"], d["day"], d["hour"], d["minute"], d["second"]]
	return [["Source", "USGS earthquake feed"], ["URL", QuakeService.FEED_URL],
			["Enabled", "yes" if Settings.get_bool("enable_earthquakes") else "no"],
			["Fetch interval", "%d s" % int(Settings.get_float("quake_fetch_interval"))],
			["Last retrieved", last], ["Status", QuakeService.last_status],
			["Earthquakes in feed", str(QuakeService.quakes.size())],
			["Earthquakes displayed", str(QuakeService.visible_quakes().size())]]

## Rebuilds the grid from [method _rows] and tells NativeUI the data changed so the native screen updates too.
func update_rows() -> void:
	NativeUI.refresh(self)
	for c in _grid.get_children():
		c.queue_free()
	for row in _rows():
		var a := Label.new()
		a.text = row[0]
		a.add_theme_color_override("font_color", Color("#8fb8ff"))
		var b := Label.new()
		b.text = row[1]
		if Layout.is_phone():
			# Long values (URLs, status text) wrap in the space beside the heading.
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.custom_minimum_size.x = 120
		_grid.add_child(a)
		_grid.add_child(b)

# MARK: - Native (SwiftUI) version; see NativeUI

## Describes this dialog for the native (SwiftUI/Compose) screen: an info row per [method _rows] entry and a "Refresh
## Now" button. See [NativeUI].
##
## Returns: {"screen": ..., "values": {}}.
func native_screen() -> Dictionary:
	var items: Array = []
	for row in _rows():
		items.append({"type": "info", "title": row[0], "detail": row[1]})
	items.append({"type": "action", "id": "refresh", "title": "Refresh Now", "style": "prominent"})
	return {"screen": {"title": "Live Data Status", "pages": [{"title": "Live Data", "items": items}]}, "values": {}}

## Handles an event from the native screen; the "refresh" action runs [method QuakeService.refresh].
##
## [param kind]: "value", "action" or "closed".
## [param key]: the control or button id.
## [param _value]: the new value (unused here).
func native_event(kind: String, key: String, _value: Variant) -> void:
	if kind == "action" and key == "refresh":
		QuakeService.refresh()
