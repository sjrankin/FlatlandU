extends Node
## Map catalog (autoload "MapCatalog"): the counterpart of Flatland's MapList/MapItem.
## A small set of maps is embedded in the app (res://Assets/BuiltIn) so it always works; the
## rest are loaded from res://Maps when present. A live NASA satellite map is downloaded on demand.
## Images are loaded on a worker thread, turned into mip-mapped textures and cached.

## Emitted when a map image that was requested with [method request] has finished loading (or, for the live satellite
## map, converting).
##
## [param file_name]: the name that was requested.
## [param texture]: the finished, mip-mapped texture.
signal texture_ready(file_name: String, texture: Texture2D)

## Folder of the optional, larger map images (loaded on demand on a worker thread).
const MAPS_DIR := "res://Maps/"
## Folder of the few maps embedded in the app so it always has something to show; these load instantly.
const BUILTIN_DIR := "res://Assets/BuiltIn/"
## Pseudo file name for the live NASA satellite map. The polar versions append "_north" or "_south". [method request]
## recognizes it by this prefix.
const SAT_NAME := "@satellite"
## URL template for the live map: NASA GIBS (MODIS Terra true color, whole world, 2048 by 1024 JPEG). The `%s` is the
## date, see [method _sat_date].
const GIBS := "https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi?SERVICE=WMS&REQUEST=GetMap&VERSION=1.1.1" \
	+ "&LAYERS=MODIS_Terra_CorrectedReflectance_TrueColor&SRS=EPSG:4326&BBOX=-180,-90,180,90" \
	+ "&WIDTH=2048&HEIGHT=1024&FORMAT=image/jpeg&TIME=%s"

## The maps that can be chosen: Dictionaries with "id", "name", "globe", "north", "south" (file names for the 3D globe
## and the two polar maps), "light" (a brightness factor) and "sea" (an optional sea mask). Built from
## `res://data/maps.json` by [method _ready], keeping only maps whose picture exists, plus the live satellite map.
var maps: Array = []
## Text describing the live satellite map ("Not retrieved", "Downloading...", "OK (date)", "Failed (HTTP n)"); shown
## in the Live Data dialog.
var satellite_status := "Not retrieved"
## Finished textures by file path (or by satellite key), so each image is loaded once.
var _cache: Dictionary = {}
## Keys of images being loaded or converted right now, so the same request is not started twice.
var _pending: Dictionary = {}
## The downloaded equirectangular satellite image, kept to make the two polar versions; null until it arrives.
var _sat_image: Image
## The HTTPRequest node used to download the satellite image.
var _http: HTTPRequest

## Builds [member maps] from `res://data/maps.json` (filling in missing polar files from the globe file and skipping
## maps whose files are absent), adds the live satellite map and creates the HTTP request node.
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

## Whether a map image is available, built in or in the Maps folder.
##
## [param file_name]: the image's file name.
## Returns: true if found in [constant BUILTIN_DIR] or [constant MAPS_DIR].
func _exists(file_name: String) -> bool:
	return ResourceLoader.exists(BUILTIN_DIR + file_name) or FileAccess.file_exists(MAPS_DIR + file_name)

## Looks up a map by name or id.
##
## [param id]: the map's "name" or "id".
## Returns: the map Dictionary; if not found, the "Simple" map, or else the first one.
func map_for(id: String) -> Dictionary:
	for m in maps:
		if m["name"] == id or m["id"] == id:
			return m
	for m in maps:
		if m["id"] == "Simple":
			return m
	return maps[0]

## Chooses the group a map is listed under in the map picker (Standard and simple, Physical, Time zones,
## Extraterrestrial, Satellite (live), Debug, or Artistic), by looking for key words in its id.
##
## [param m]: a map Dictionary.
## Returns: the group name.
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

## Asks for a map picture. Built-in images come back at once; others are loaded on a worker thread without freezing
## the app.
##
## [param file_name]: the image's file name (or a [constant SAT_NAME] name).
## Returns: the texture if it is ready, otherwise null, and then [signal texture_ready] fires when it arrives. See
##   [method _request_satellite], [method _load_in_thread].
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

## Runs on a worker thread: reads an image file and hands it back to the main thread.
##
## [param path]: full path of the image.
## [param file_name]: the name that was requested (passed on to [method _finish_load]).
func _load_in_thread(path: String, file_name: String) -> void:
	var img := Image.load_from_file(path)
	_finish_load.call_deferred(path, file_name, img)

## Runs on the main thread after [method _load_in_thread]: makes the mip-mapped texture, caches it and emits
## [signal texture_ready]. Logs a warning if the image could not be read.
##
## [param path]: full path of the image (the cache key).
## [param file_name]: the name that was requested.
## [param img]: the loaded image, or null on failure.
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

## The date of the satellite picture to fetch: yesterday in UTC, because today's picture is not complete yet.
##
## Returns: the date as "YYYY-MM-DD".
func _sat_date() -> String:
	var d := Time.get_date_dict_from_unix_time(int(Time.get_unix_time_from_system() - 86400.0))
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]

## The satellite-map part of [method request]. Uses the cache, then today's saved file in the user-data folder,
## otherwise starts the download.
##
## [param file_name]: a name starting with [constant SAT_NAME] (equirectangular, "_north" or "_south").
## Returns: the texture if ready, otherwise null (it arrives through [signal texture_ready]).
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

## Handles the end of the satellite download: records an error in [member satellite_status], or saves the JPEG for
## next time and starts building the textures.
##
## [param result]: the HTTPRequest result code.
## [param code]: the HTTP status code (200 means success).
## [param _h]: the response headers (unused).
## [param body]: the downloaded JPEG bytes.
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

## Stores the satellite image, marks the status OK and builds the textures with [method _build_sat_textures].
##
## [param img]: the equirectangular satellite image.
func _set_sat_image(img: Image) -> void:
	_pending.erase(SAT_NAME)
	_sat_image = img
	satellite_status = "OK (%s)" % _sat_date()
	_build_sat_textures()

## Makes the textures from [member _sat_image]: the equirectangular one now, and the north and south polar ones on
## worker threads with [method _polar_in_thread]. Emits [signal texture_ready] for each as it is done.
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

## Runs on a worker thread: converts the equirectangular satellite image to a polar azimuthal-equidistant picture, the
## layout of the flat polar maps (1024 by 1024, a circle in a square).
##
## [param key]: the cache key to store the result under.
## [param north]: true for the north-pole map, false for the south-pole map.
## The result goes back through [method _polar_done].
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

## Runs on the main thread after [method _polar_in_thread]: makes the texture, caches it and emits
## [signal texture_ready].
##
## [param key]: the cache key.
## [param img]: the finished polar image.
func _polar_done(key: String, img: Image) -> void:
	_pending.erase(key)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	texture_ready.emit(key, tex)
