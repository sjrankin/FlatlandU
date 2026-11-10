extends Node
## Map catalog (autoload "MapCatalog"): the counterpart of Flatland's MapList/MapItem.
## A small set of maps is embedded in the app (res://Assets/BuiltIn) so it always works; the
## rest are loaded from res://Maps when present. A live NASA satellite map is downloaded on demand.
## Images are loaded on a worker thread, turned into mip-mapped textures and cached.

signal texture_ready(file_name: String, texture: Texture2D)

const MAPS_DIR := "res://Maps/"
const BUILTIN_DIR := "res://Assets/BuiltIn/"
const SAT_NAME := "@satellite"
const GIBS := "https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi?SERVICE=WMS&REQUEST=GetMap&VERSION=1.1.1" \
	+ "&LAYERS=MODIS_Terra_CorrectedReflectance_TrueColor&SRS=EPSG:4326&BBOX=-180,-90,180,90" \
	+ "&WIDTH=2048&HEIGHT=1024&FORMAT=image/jpeg&TIME=%s"

var maps: Array = []                  # Array of Dictionary (id, name, globe, north, south, light, sea)
var satellite_status := "Not retrieved"
var _cache: Dictionary = {}           # file path -> Texture2D
var _pending: Dictionary = {}
var _sat_image: Image
var _http: HTTPRequest

func _ready() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps.json"))
	if parsed is Array:
		for m in parsed:
			if str(m["globe"]) == "":
				continue
			if str(m["north"]) == "":
				m["north"] = str(m["globe"])
			if str(m["south"]) == "":
				m["south"] = str(m["globe"])
			if _exists(str(m["globe"])):
				maps.append(m)
	maps.append({"id": "SatelliteMODIS", "name": "NASA MODIS Terra (live)", "globe": SAT_NAME,
		"north": SAT_NAME + "_north", "south": SAT_NAME + "_south", "light": 1.0, "sea": ""})
	_http = HTTPRequest.new()
	_http.timeout = 60.0
	add_child(_http)
	_http.request_completed.connect(_on_sat_downloaded)

func _exists(file_name: String) -> bool:
	return ResourceLoader.exists(BUILTIN_DIR + file_name) or FileAccess.file_exists(MAPS_DIR + file_name)

func map_for(id: String) -> Dictionary:
	for m in maps:
		if m["name"] == id or m["id"] == id:
			return m
	for m in maps:
		if m["id"] == "Simple":
			return m
	return maps[0]

## Folder-style grouping used by the map picker (mirrors the asset catalog groups).
func group_for(m: Dictionary) -> String:
	var id: String = m["id"]
	if id.begins_with("Satellite"):
		return "Satellite (live)"
	if id.begins_with("Debug"):
		return "Debug"
	for key in ["Mars", "MOLA", "LRO", "Lunar", "Jupiter", "Gaia", "Tycho", "NASAStars"]:
		if id.contains(key):
			return "Extraterrestrial"
	for key in ["TimeZone", "Zone"]:
		if id.contains(key):
			return "Time zones"
	for key in ["BlueMarble", "Marble", "MODIS", "Topo", "Tectonic", "Aerosol", "USGS", "Earthquake", "CitiesAtNight"]:
		if id.contains(key):
			return "Physical"
	for key in ["Standard", "Simple", "Continents", "Political", "Transparent"]:
		if id.contains(key):
			return "Standard and simple"
	return "Artistic"

## Returns the texture if available, otherwise starts loading it and returns null
## (`texture_ready` fires when it arrives).
func request(file_name: String) -> Texture2D:
	if file_name.begins_with(SAT_NAME):
		return _request_satellite(file_name)
	var builtin := BUILTIN_DIR + file_name
	if ResourceLoader.exists(builtin):
		return load(builtin)
	var path := MAPS_DIR + file_name
	if _cache.has(path):
		return _cache[path]
	if not _pending.has(path):
		_pending[path] = true
		WorkerThreadPool.add_task(_load_in_thread.bind(path, file_name))
	return null

func _load_in_thread(path: String, file_name: String) -> void:
	var img := Image.load_from_file(path)
	_finish_load.call_deferred(path, file_name, img)

func _finish_load(path: String, file_name: String, img: Image) -> void:
	_pending.erase(path)
	if img == null or img.is_empty():
		push_warning("Could not load image " + path)
		return
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[path] = tex
	texture_ready.emit(file_name, tex)

# MARK: - Live satellite map (NASA GIBS, MODIS Terra true color, yesterday's UTC date)

func _sat_date() -> String:
	var d := Time.get_date_dict_from_unix_time(int(Time.get_unix_time_from_system() - 86400.0))
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]

func _request_satellite(file_name: String) -> Texture2D:
	if _cache.has(file_name):
		return _cache[file_name]
	if _sat_image != null:
		_build_sat_textures()
		return _cache.get(file_name)
	if _pending.has(SAT_NAME):
		return null
	_pending[SAT_NAME] = true
	var cached := "user://satellite_%s.jpg" % _sat_date()
	if FileAccess.file_exists(cached):
		_set_sat_image(Image.load_from_file(cached))
		return _cache.get(file_name)
	satellite_status = "Downloading…"
	_http.request(GIBS % _sat_date())
	return null

func _on_sat_downloaded(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_pending.erase(SAT_NAME)
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		satellite_status = "Failed (HTTP %d)" % code
		return
	var img := Image.new()
	if img.load_jpg_from_buffer(body) != OK:
		satellite_status = "Bad image"
		return
	var f := FileAccess.open("user://satellite_%s.jpg" % _sat_date(), FileAccess.WRITE)
	if f != null:
		f.store_buffer(body)
		f.close()
	_set_sat_image(img)

func _set_sat_image(img: Image) -> void:
	_pending.erase(SAT_NAME)
	_sat_image = img
	satellite_status = "OK (%s)" % _sat_date()
	_build_sat_textures()

func _build_sat_textures() -> void:
	if not _cache.has(SAT_NAME):
		var eq := _sat_image.duplicate() as Image
		eq.generate_mipmaps()
		var tex := ImageTexture.create_from_image(eq)
		_cache[SAT_NAME] = tex
		texture_ready.emit(SAT_NAME, tex)
	for hemi: String in ["_north", "_south"]:
		var key := SAT_NAME + hemi
		if not _cache.has(key) and not _pending.has(key):
			_pending[key] = true
			WorkerThreadPool.add_task(_polar_in_thread.bind(key, hemi == "_north"))

## Equirectangular -> polar azimuthal-equidistant (the layout of Flatland's flat maps).
func _polar_in_thread(key: String, north: bool) -> void:
	var n := 1024
	var src := _sat_image
	var w := src.get_width()
	var h := src.get_height()
	var out := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in range(n):
		var dy := (float(y) + 0.5) / n * 2.0 - 1.0
		for x in range(n):
			var dx := (float(x) + 0.5) / n * 2.0 - 1.0
			var r := sqrt(dx * dx + dy * dy)
			if r > 1.0:
				continue
			var ang := rad_to_deg(atan2(-dy, dx))
			var lon: float
			var lat: float
			if north:
				lon = ang - 90.0
				lat = 90.0 - r * 180.0
			else:
				lon = 90.0 - ang
				lat = r * 180.0 - 90.0
			lon = wrapf(lon, -180.0, 180.0)
			var u := clampi(int((lon + 180.0) / 360.0 * w), 0, w - 1)
			var v := clampi(int((90.0 - lat) / 180.0 * h), 0, h - 1)
			out.set_pixel(x, y, src.get_pixel(u, v))
	_polar_done.call_deferred(key, out)

func _polar_done(key: String, img: Image) -> void:
	_pending.erase(key)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	texture_ready.emit(key, tex)
