extends Window
## Preferences window (counterpart of Flatland's PreferencePanel). Every control applies
## immediately and is saved through Settings.

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
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(tabs)
	_general(tabs)
	_map(tabs)
	_cities(tabs)
	_grid(tabs)
	_quakes(tabs)
	_colors(tabs)
	_location(tabs)
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_END
	var reset := Button.new()
	reset.text = "Reset All Settings"
	reset.pressed.connect(func() -> void: Settings.reset_all())
	bar.add_child(reset)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(hide)
	bar.add_child(close)
	vb.add_child(bar)

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
	p.add_child(SettingControls.check("Show sun", "show_sun"))
	p.add_child(SettingControls.check("Show shadows under 2D city markers", "show_shadows"))
	p.add_child(SettingControls.section("Day and night"))
	p.add_child(SettingControls.check("Show night", "show_night"))
	p.add_child(SettingControls.option("Night darkness", "night_darkness", [
		["Very light", "VeryLight"], ["Light", "Light"], ["Dark", "Dark"], ["Very dark", "VeryDark"]]))
	p.add_child(SettingControls.check("Show moon light on the night side (3D)", "show_moon_light"))
	p.add_child(SettingControls.check("Show star field behind the globe (3D)", "show_stars"))
	p.add_child(SettingControls.check("Attract mode (globe spins continuously)", "attract_mode"))
	p.add_child(SettingControls.section("Sounds"))
	p.add_child(SettingControls.check("Enable sounds", "enable_sounds"))

func _map(tabs: TabContainer) -> void:
	var picker: Control = load("res://scripts/ui/map_picker.gd").new()
	picker.name = "Map"
	tabs.add_child(picker)

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
		["Radiating Rings", "Radiating Rings"], ["Glowing Sphere", "Glowing Sphere"],
		["Triangle Ring Inward", "Triangle Ring Inward"], ["Triangle Ring Outward", "Triangle Ring Outward"]]))
	p.add_child(SettingControls.option("New means within", "quake_recent_hours", [
		["Last 12 hours", 12], ["Last 24 hours", 24], ["Last 48 hours", 48], ["Last 72 hours", 72],
		["Last week", 168], ["Last 10 days", 240]]))
	p.add_child(SettingControls.spin("Fetch interval", "quake_fetch_interval", 15, 3600, 15, " s"))
	p.add_child(SettingControls.option("New-quake sound", "quake_sound", [
		["Chime", "Chime.mp3"], ["Cymbal", "Cymbal.mp3"], ["Doorbell", "Doorbell.mp3"],
		["Fiddle", "Fiddle.mp3"], ["Gong", "Gong.mp3"], ["Pips", "gts_pips.mp3"]]))

func _colors(tabs: TabContainer) -> void:
	var p := SettingControls.page(tabs, "Colors and Fonts")
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
	(p.get_child(0) as Label).text = "Home location is used for \"relative to home location\" hours and Today's Times."
	p.add_child(SettingControls.spin("Latitude", "home_latitude", -90, 90, 0.0001))
	p.add_child(SettingControls.spin("Longitude", "home_longitude", -180, 180, 0.0001))
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Name"
	lbl.custom_minimum_size.x = 150
	row.add_child(lbl)
	var le := LineEdit.new()
	le.text = Settings.get_string("home_name")
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.text_submitted.connect(func(t: String) -> void: Settings.set_value("home_name", t))
	le.focus_exited.connect(func() -> void: Settings.set_value("home_name", le.text))
	row.add_child(le)
	p.add_child(row)
