extends Window
## Status of the asynchronous data Flatland retrieves (Flatland's Live Data Status view).

var _grid: GridContainer

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

func update_rows() -> void:
	for c in _grid.get_children():
		c.queue_free()
	var last := "never"
	if QuakeService.last_fetch_unix > 0.0:
		var d := Time.get_datetime_dict_from_unix_time(int(QuakeService.last_fetch_unix))
		last = "%04d-%02d-%02d %02d:%02d:%02d UTC" % [d["year"], d["month"], d["day"], d["hour"], d["minute"], d["second"]]
	for row in [["Source", "USGS earthquake feed"], ["URL", QuakeService.FEED_URL],
			["Enabled", "yes" if Settings.get_bool("enable_earthquakes") else "no"],
			["Fetch interval", "%d s" % int(Settings.get_float("quake_fetch_interval"))],
			["Last retrieved", last], ["Status", QuakeService.last_status],
			["Earthquakes in feed", str(QuakeService.quakes.size())],
			["Earthquakes displayed", str(QuakeService.visible_quakes().size())]]:
		var a := Label.new()
		a.text = row[0]
		a.add_theme_color_override("font_color", Color("#8fb8ff"))
		var b := Label.new()
		b.text = row[1]
		_grid.add_child(a)
		_grid.add_child(b)
