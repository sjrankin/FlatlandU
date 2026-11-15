extends Window
## Preferences window (counterpart of Flatland's PreferencePanel). Every control applies
## immediately and is saved through Settings.

signal open_satellites

func _ready() -> void:
	title = "Flatland Preferences"
	size = Vector2i(760, 560)
	min_size = Vector2i(640, 460)
	exclusive = false
	transient = true
	wrap_controls = false
	close_requested.connect(hide)
	var root := PanelContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var vb := VBoxContainer.new()
	root.add_child(vb)
	var phone := Layout.is_phone()
	if phone:
		set_meta("sheet_no_scroll", true)   # every page scrolls by itself (see PhoneSheet.wrap)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	SettingControls.begin_recording()   # NativeUI builds its Preferences from what is recorded here
	_general(tabs)
	_map(tabs)
	_cities(tabs)
	_grid(tabs)
	_quakes(tabs)
	_colors(tabs)
	_location(tabs)
	_power(tabs)
	SettingControls.end_recording()
	var reset := Button.new()
	reset.text = "Reset All Settings"
	reset.pressed.connect(func() -> void: Settings.reset_all())
	if phone:
		# The sections are a row of buttons with separators (seven tabs do not fit a phone's width).
		tabs.tabs_visible = false
		vb.add_child(_section_buttons(tabs))
		vb.add_child(tabs)
		# PhoneSheet.wrap moves this bottom row to the footer, left of the Close button.
		var bar := HBoxContainer.new()
		bar.add_child(reset)
		vb.add_child(bar)
	else:
		vb.add_child(tabs)
		var bar := HBoxContainer.new()
		bar.alignment = BoxContainer.ALIGNMENT_END
		bar.add_child(reset)
		var close := Button.new()
		close.text = "Close"
		close.pressed.connect(hide)
		bar.add_child(close)
		vb.add_child(bar)

## Phone only: one rounded button per section with a thin divider between neighbours; the current
## section is highlighted. Wraps onto a second line when the buttons do not fit one.
func _section_buttons(tabs: TabContainer) -> Control:
	var flow := HFlowContainer.new()
	var group := ButtonGroup.new()
	var buttons: Array[Button] = []
	for i in range(tabs.get_tab_count()):
		if i > 0:
			var sep := VSeparator.new()
			flow.add_child(sep)
		var b := Button.new()
		b.text = tabs.get_tab_title(i)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == tabs.current_tab
		b.pressed.connect(func() -> void: tabs.current_tab = i)
		flow.add_child(b)
		buttons.append(b)
	tabs.tab_changed.connect(func(i: int) -> void:   # e.g. opened on the Map page from elsewhere
		for k in range(buttons.size()):
			buttons[k].set_pressed_no_signal(k == i))
	return flow

func _general(tabs: TabContainer) -> void:
	var p := SettingControls.page(tabs, "General")
	p.add_child(SettingControls.section("View"))
	p.add_child(SettingControls.option("View type", "view_type", [
		["3D Globe", Settings.VIEW_GLOBE], ["Flat - North centered", Settings.VIEW_FLAT_NORTH],
		["Flat - South centered", Settings.VIEW_FLAT_SOUTH], ["Rectangular", Settings.VIEW_RECT],
		["Cubic world", Settings.VIEW_CUBIC]]))
	p.add_child(SettingControls.option("Hour labels", "hour_type", [
		["None", Settings.HOURS_NONE], ["Solar time", Settings.HOURS_SOLAR], ["Relative to noon", Settings.HOURS_NOON],
		["Relative to home location", Settings.HOURS_LOCATION], ["Wall clock", Settings.HOURS_WALL]]))
	p.add_child(SettingControls.option("Time label", "time_label", [["None", "None"], ["UTC", "UTC"], ["Local", "Local"]]))
	p.add_child(SettingControls.check("Show seconds in the time label", "time_label_seconds"))
	p.add_child(SettingControls.check("Show status bar", "show_status_bar"))
	p.add_child(SettingControls.check("Show frames per second (FPS)", "show_fps"))
	p.add_child(SettingControls.check("Show sun", "show_sun"))
	p.add_child(SettingControls.check("Show moon", "show_moon"))
	p.add_child(SettingControls.check("Show the position of the sun on the Earth", "show_sun_point"))
	p.add_child(SettingControls.check("Show the position of the moon on the Earth", "show_moon_point"))
	p.add_child(SettingControls.check("Show stars", "show_stars"))
	p.add_child(SettingControls.check("Show shadows under 2D city markers", "show_shadows"))
	p.add_child(SettingControls.check("Show 3D shadows (labels, cities, earthquakes)", "show_shadows_3d"))
	p.add_child(SettingControls.section("Day and night"))
	p.add_child(SettingControls.check("Show night", "show_night"))
	p.add_child(SettingControls.option("Night darkness", "night_darkness", [
		["Very light", "VeryLight"], ["Light", "Light"], ["Dark", "Dark"], ["Very dark", "VeryDark"]]))
	p.add_child(SettingControls.check("Show moon light on the night side (3D)", "show_moon_light"))
	p.add_child(SettingControls.check("Attract mode (globe spins continuously)", "attract_mode"))
	p.add_child(SettingControls.section("Sounds"))
	p.add_child(SettingControls.check("Enable sounds", "enable_sounds"))

func _map(tabs: TabContainer) -> void:
	SettingControls.record_page("Map")
	var map_options: Array = []
	for m in MapCatalog.maps:
		map_options.append({"label": str(m["name"]), "value": str(m["name"]), "group": MapCatalog.group_for(m)})
	SettingControls.record_item({"type": "choice", "key": "map_type", "title": "Map", "options": map_options})
	SettingControls.record_item({"type": "action", "id": "satellites", "title": "Satellites…"})
	var picker: Control = load("res://scripts/ui/map_picker.gd").new()
	picker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.name = "Map"
	box.add_child(picker)
	var sats := Button.new()
	sats.text = "Satellites…"
	sats.tooltip_text = "Show or hide satellites and choose which are tracked."
	sats.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	sats.pressed.connect(func() -> void: open_satellites.emit())
	box.add_child(sats)
	if Layout.is_phone():
		var scroll := ScrollContainer.new()
		scroll.name = "Map"
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		box.name = "MapBox"
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(box)
		tabs.add_child(scroll)
		return
	tabs.add_child(box)

func _cities(tabs: TabContainer) -> void:
	var p := SettingControls.page(tabs, "Cities")
	p.add_child(SettingControls.check("Show cities", "show_cities"))
	p.add_child(SettingControls.check("Show city names", "show_city_names"))
	p.add_child(SettingControls.option("City shape (3D)", "city_shape", [
		["Uniform Flush Spheres", "Uniform Flush Spheres"], ["Relative Flush Spheres", "Relative Flush Spheres"],
		["Floating Spheres", "Floating Spheres"], ["Floating Boxes", "Floating Boxes"], ["Boxes", "Boxes"],
		["Cylinders", "Cylinders"], ["Pyramids", "Pyramids"], ["Names", "Names"], ["Sticks", "Sticks"]]))
	p.add_child(SettingControls.option("City scale", "city_scale", [["Small", "Small"], ["Normal", "Normal"], ["Large", "Large"]]))
	p.add_child(SettingControls.option("Cities to show", "city_filter", [
		["Largest cities (by rank)", "Rank"], ["All cities", "All"], ["Capitals only", "Capitals"]]))
	p.add_child(SettingControls.spin("Number of largest cities", "city_rank", 5, 500, 5))
	p.add_child(SettingControls.check("Show UNESCO World Heritage Sites", "show_heritage_sites"))
	p.add_child(SettingControls.check("Show points of interest", "show_user_pois"))

func _grid(tabs: TabContainer) -> void:
	var p := SettingControls.page(tabs, "Grid")
	p.add_child(SettingControls.check("Show grid lines", "show_grid"))
	p.add_child(SettingControls.check("Equator", "show_equator"))
	p.add_child(SettingControls.check("Tropics of Cancer and Capricorn", "show_tropics"))
	p.add_child(SettingControls.check("Arctic and Antarctic circles", "show_polar_circles"))
	p.add_child(SettingControls.check("Noon meridian", "show_noon_meridians"))
	p.add_child(SettingControls.check("Hour meridians (every 15°)", "show_minor_grid"))

func _quakes(tabs: TabContainer) -> void:
	var p := SettingControls.page(tabs, "Earthquakes")
	p.add_child(SettingControls.check("Show earthquakes (data from the USGS)", "enable_earthquakes"))
	p.add_child(SettingControls.option("Minimum magnitude", "quake_min_magnitude", [
		["4.0", 4.0], ["5.0", 5.0], ["6.0", 6.0], ["7.0", 7.0], ["8.0", 8.0]]))
	p.add_child(SettingControls.option("Maximum age", "quake_max_age_days", [
		["1 day", 1], ["2 days", 2], ["3 days", 3], ["5 days", 5], ["7 days", 7]]))
	p.add_child(SettingControls.option("Earthquake shape (3D)", "quake_shape", [
		["Sphere", "Sphere"], ["Pulsating Sphere", "Pulsating Sphere"], ["Animated Arrow", "Animated Arrow"],
		["Static Arrow", "Static Arrow"], ["Pyramid", "Pyramid"], ["Cone", "Cone"], ["Box", "Box"],
		["Cylinder", "Cylinder"], ["Capsule", "Capsule"], ["Tethered Magnitude", "Tethered Magnitude"]]))
	p.add_child(SettingControls.option("Indicator scale", "quake_scale", [["Small", "Small"], ["Normal", "Normal"], ["Large", "Large"]]))
	p.add_child(SettingControls.check("Highlight new earthquakes", "quake_highlight_new"))
	p.add_child(SettingControls.option("New earthquake indicator", "quake_indicator", [
		["None", "None"], ["Static Ring", "Static Ring"], ["Animated Ring", "Animated Ring"],
		["Arrow and Ring (still)", "Arrow and Ring"], ["Radiating Rings", "Radiating Rings"], ["Glowing Sphere", "Glowing Sphere"],
		["Triangle Ring Inward", "Triangle Ring Inward"], ["Triangle Ring Outward", "Triangle Ring Outward"]]))
	p.add_child(SettingControls.option("New means within", "quake_recent_hours", [
		["Last 12 hours", 12], ["Last 24 hours", 24], ["Last 48 hours", 48], ["Last 72 hours", 72],
		["Last week", 168], ["Last 10 days", 240]]))
	p.add_child(SettingControls.spin("Fetch interval", "quake_fetch_interval", 15, 3600, 15, " s"))
	p.add_child(SettingControls.option("New-quake sound", "quake_sound", [
		["Chime", "Chime.mp3"], ["Cymbal", "Cymbal.mp3"], ["Doorbell", "Doorbell.mp3"],
		["Fiddle", "Fiddle.mp3"], ["Gong", "Gong.mp3"], ["Pips", "gts_pips.mp3"]]))

func _colors(tabs: TabContainer) -> void:
	var p := SettingControls.page(tabs, "Colors" if Layout.is_phone() else "Colors and Fonts")
	p.add_child(SettingControls.section("Fonts"))
	p.add_child(SettingControls.font_picker("Label font (hours, cities, locations)", "label_font"))
	p.add_child(SettingControls.section("General"))
	p.add_child(SettingControls.color("Background", "color_background"))
	p.add_child(SettingControls.color("Grid lines (latitude and longitude)", "color_grid"))
	p.add_child(SettingControls.color("Hour labels (3D)", "color_hours"))
	p.add_child(SettingControls.color("Hour labels (2D)", "color_hours_2d"))
	p.add_child(SettingControls.section("Cities"))
	p.add_child(SettingControls.color("Cities in 2D views", "color_city_2d"))
	p.add_child(SettingControls.color("Capital cities (3D)", "color_city_capital"))
	p.add_child(SettingControls.color("African cities (3D)", "color_city_africa"))
	p.add_child(SettingControls.color("Asian cities (3D)", "color_city_asia"))
	p.add_child(SettingControls.color("European cities (3D)", "color_city_europe"))
	p.add_child(SettingControls.color("North American cities (3D)", "color_city_north_america"))
	p.add_child(SettingControls.color("South American cities (3D)", "color_city_south_america"))

func _location(tabs: TabContainer) -> void:
	var p := SettingControls.page(tabs, "Home")
	p.add_child(Label.new())
	(p.get_child(0) as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	(p.get_child(0) as Label).text = "Home location is used for \"relative to home location\" hours and Today's Times."
	p.add_child(SettingControls.spin("Latitude", "home_latitude", -90, 90, 0.0001))
	p.add_child(SettingControls.spin("Longitude", "home_longitude", -180, 180, 0.0001))
	SettingControls.record_item({"type": "text", "key": "home_name", "title": "Name"})
	var row := SettingControls.labeled_row("Name", 150)
	var le := LineEdit.new()
	le.text = Settings.get_string("home_name")
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.text_submitted.connect(func(t: String) -> void: Settings.set_value("home_name", t))
	le.focus_exited.connect(func() -> void: Settings.set_value("home_name", le.text))
	row.add_child(le)
	p.add_child(row)

func _power(tabs: TabContainer) -> void:
	var p := SettingControls.page(tabs, "Power")
	p.add_child(SettingControls.section("Frame rate"))
	p.add_child(SettingControls.option("Frame rate", "frame_rate", [
		["Auto (60 while touching, 30 when idle)", "Auto"], ["30 fps", "30"], ["60 fps", "60"], ["120 fps", "120"]]))
	p.add_child(SettingControls.check("Draw less often when nothing is touched or moving (phones)", "draw_on_demand"))
	p.add_child(SettingControls.check("Use 30 fps in Low Power Mode or when the device is hot", "follow_low_power"))
	p.add_child(SettingControls.section("Graphics"))
	p.add_child(SettingControls.option("Quality", "graphics_quality", [
		["Auto (Medium on a phone, High elsewhere)", "Auto"],
		["High (4x anti-aliasing, full resolution)", "High"],
		["Medium (2x anti-aliasing, 80% resolution)", "Medium"],
		["Low (no anti-aliasing, 65% resolution, no 3D shadows)", "Low"]]))
	p.add_child(SettingControls.section("Screen"))
	p.add_child(SettingControls.check("Keep the screen on (no auto-lock)", "keep_screen_on"))
	var note := Label.new()
	note.text = "Lower frame rates and lower graphics quality use much less battery and keep the device cooler. Flatland stops drawing while a dialog covers the screen."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(note)
	SettingControls.record_item({"type": "paragraph", "title": note.text, "style": "caption"})

# MARK: - Native (SwiftUI) version; see NativeUI

func native_screen() -> Dictionary:
	var pages: Array = SettingControls.recorded_pages.duplicate(true)
	for page in pages:
		if page["title"] == "Colors":
			page["title"] = "Colors and Fonts"
	var values := {}
	for page in pages:
		for item in page["items"]:
			if item.has("key"):
				values[item["key"]] = Settings.get_value(item["key"])
	return {"screen": {"title": "Flatland Preferences", "pages": pages, "root_items": [
		{"type": "action", "id": "reset", "title": "Reset All Settings", "style": "destructive",
			"confirm": "Reset every setting to its default?"}]}, "values": values}

func native_event(kind: String, key: String, value: Variant) -> void:
	if kind == "value":
		NativeUI.store_setting(key, value)
	elif kind == "action":
		if key == "reset":
			Settings.reset_all()
		elif key == "satellites":
			open_satellites.emit()
