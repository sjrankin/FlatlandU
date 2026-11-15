extends Node
## Map catalog (autoload "MapCatalog"): the counterpart of Flatland's MapList/MapItem.
## A small set of maps is embedded in the app (res://Assets/BuiltIn) so it always works; the
## rest are loaded from res://Maps when present. Live NASA GIBS satellite maps are downloaded on demand: NOAA-21 (with
## NOAA-20 as a fallback), a merged GOES-West / GOES-East / Meteosat MTG / Himawari weather-satellite map, and a blend of the two.
## Images are loaded on a worker thread, turned into mip-mapped textures and cached.

## Emitted when a map image that was requested with [method request] has finished loading (or, for the live satellite
## map, converting).
##
## [param file_name]: the name that was requested.
## [param texture]: the finished, mip-mapped texture.
signal texture_ready(file_name: String, texture: Texture2D)

## Emitted while the live satellite picture is downloaded, so the status box can tell the user what is happening.
##
## [param text]: the message to show.
## [param done]: false for "downloading" (the message stays until replaced), true for the final message (finished, or
## failed); the status box then replaces the downloading message with this one.
signal satellite_progress(text: String, done: bool)

## Folder of the optional, larger map images (loaded on demand on a worker thread).
const MAPS_DIR := "res://Maps/"
## Folder of the few maps embedded in the app so it always has something to show; these load instantly.
const BUILTIN_DIR := "res://Assets/BuiltIn/"
## Pseudo file name for the live NASA GIBS satellite map. The polar versions append "_north" or "_south". [method request]
## recognizes it by this prefix.
const SAT_NAME := "@satellite"
## Pseudo file name for the weather-satellite-only map (GOES-West, GOES-East, Meteosat MTG and Himawari merged; black where none of
## them sees). The polar versions append "_north" or "_south".
const WX_NAME := "@weather"
## Pseudo file name for the blended map: the weather satellites faded into the NOAA-21 map. Polar versions as above.
const BLEND_NAME := "@blend"
## URL template for the live map: NASA GIBS (VIIRS true color, whole world, 4096 by 2048 JPEG). VIIRS scans a wider
## swath than the older MODIS sensors (Terra and Aqua, which are being retired and are not used as imagery sources),
## so a day's picture has no black gaps between orbits. The first `%s` is the GIBS layer (see [constant SAT_SOURCES]),
## the second the date, see [method _sat_date].
const GIBS := "https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi?SERVICE=WMS&REQUEST=GetMap&VERSION=1.1.1" \
	+ "&LAYERS=%s&SRS=EPSG:4326&BBOX=-180,-90,180,90" \
	+ "&WIDTH=4096&HEIGHT=2048&FORMAT=image/jpeg&TIME=%s"
## The imagery sources in the order they are tried: [short name, GIBS layer]. NOAA-21 is preferred; NOAA-20 (a near-twin
## in almost the same orbit) is used when NOAA-21's picture is missing, empty or fails to download. Suomi NPP is not
## listed because it is also being retired.
const SAT_SOURCES := [
	["NOAA-21", "VIIRS_NOAA21_CorrectedReflectance_TrueColor"],
	["NOAA-20", "VIIRS_NOAA20_CorrectedReflectance_TrueColor"],
]
## URL template for a weather picture from NASA GIBS: the whole world, 4096 by 2048 JPEG, the newest one GIBS has (no
## TIME given). The `%s` is the GIBS layer.
const WX_GIBS_URL := "https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi?SERVICE=WMS&REQUEST=GetMap&VERSION=1.1.1" \
	+ "&LAYERS=%s&SRS=EPSG:4326&BBOX=-180,-90,180,90&WIDTH=4096&HEIGHT=2048&FORMAT=image/jpeg"
## URL template for a weather picture from EUMETSAT's EUMETView service (no account needed): the whole world, 4096 by
## 2048 JPEG. WMS 1.3.0 lists the box as south,west,north,east. The `%s` is the layer and `{time}` is replaced by
## [method _wx_time_param]. The time is always given because the server's default picture is cached and can be stale. A
## picture takes 2 to 15 seconds to come back, slower than GIBS.
const WX_EUMETVIEW_URL := "https://view.eumetsat.int/geoserver/wms?service=WMS&version=1.3.0&request=GetMap" \
	+ "&layers=%s&styles=&crs=EPSG:4326&bbox=-90,-180,90,180&width=4096&height=2048&format=image/jpeg&time={time}"
## The weather-satellite sources: [short name, layer, URL template, whether an almost black picture means the download
## failed]. The short names are also the keys [WeatherComposer] expects. GOES-West, GOES-East and MTG use GeoColor (true
## color by day, infrared by night). GIBS has no GeoColor layer for Himawari, so its visible-light band is used
## (grayscale, and black on its night side; a black Himawari picture is therefore normal when it is night over all of
## its disk). The "Himawari IR" picture (infrared, colour-coded by cloud-top temperature) fills in that night side. Meteosat-9 over the Indian Ocean is not used. Longitudes of
## the satellites are in `shaders/weather_composite.gdshader`.
const WX_SOURCES := [
	["GOES-West", "GOES-West_ABI_GeoColor", WX_GIBS_URL, true],
	["GOES-East", "GOES-East_ABI_GeoColor", WX_GIBS_URL, true],
	["MTG", "mtg_fd:rgb_geocolour", WX_EUMETVIEW_URL, true],
	["Himawari", "Himawari_AHI_Band3_Red_Visible_1km", WX_GIBS_URL, false],
	["Himawari IR", "Himawari_AHI_Band13_Clean_Infrared", WX_GIBS_URL, true],
]
## The satellites, as counted in the status text. "Himawari IR" is not one of them: it is a second picture from
## Himawari, used on its night side (see [constant WX_SOURCES]).
const WX_SATELLITES := ["GOES-West", "GOES-East", "MTG", "Himawari"]
## How old (seconds) the EUMETView picture asked for is: the newest pictures are published about half an hour late, so
## asking for "now" would give an empty picture. The server uses the nearest picture it has.
const WX_EUMETVIEW_LAG := 2400
## How many times a failed weather download is tried again. The NASA and EUMETSAT services sit in front of tile servers
## that fail now and then (an error message or an empty picture), and a second try usually works. A retry of an
## EUMETView picture asks for a picture one hour earlier per try, in case the newest one is missing.
const WX_RETRIES := 4
## Seconds to wait before the first retry; each further retry waits this much longer again (2, 4, 6 ... seconds), so a
## struggling server has time to recover.
const WX_RETRY_DELAY := 2.0
## Seconds before a weather map that is missing a satellite is fetched again when it is asked for. Long enough that a
## view which asks for the map each time a texture arrives cannot start a loop of downloads.
const WX_INCOMPLETE_RETRY := 120.0
## A weather picture counts as empty when fewer than this fraction of the sampled pixels are lit.
const WX_BLANK_FRACTION := 0.02
## Weather pictures are saved and reused for this many seconds (the satellites send a new picture every 10 to 15
## minutes; GIBS lags by about half an hour).
const WX_SLOT_SECONDS := 1800
## A downloaded weather picture smaller than this many bytes is an error message, not a picture.
const WX_MIN_BYTES := 5000
## The weather compositor, see [WeatherComposer].
const WeatherComposerScript := preload("res://scripts/core/weather_composer.gd")
## A downloaded picture smaller than this many bytes is treated as "no data yet" (a day not yet processed comes back as
## a nearly empty JPEG of about 10 KB, against about 2 MB for a real one), and the next source is tried.
const SAT_MIN_BYTES := 200000

## The maps that can be chosen: Dictionaries with "id", "name", "globe", "north", "south" (file names for the 3D globe
## and the two polar maps), "light" (a brightness factor) and "sea" (an optional sea mask). Built from
## `res://data/maps.json` by [method _ready], keeping only maps whose picture exists, plus the live satellite map.
var maps: Array = []
## Text describing the live satellite map ("Not retrieved", "Downloading...", "OK (source, date)", "Failed (reason)"); shown
## in the Live Data dialog.
var satellite_status := "Not retrieved"
## Finished textures by file path (or by satellite key), so each image is loaded once.
var _cache: Dictionary = {}
## Keys of images being loaded or converted right now, so the same request is not started twice.
var _pending: Dictionary = {}
## The downloaded equirectangular satellite image, kept to make the two polar versions; null until it arrives.
var _sat_image: Image
## Index into [constant SAT_SOURCES] of the source being downloaded now.
var _sat_try := 0
## Short name of the source the current [member _sat_image] came from ("NOAA-21" or "NOAA-20").
var _sat_source := ""
## The HTTPRequest node used to download the satellite image.
var _http: HTTPRequest
## Text describing the weather-satellite maps ("Not retrieved", "Downloading...", "OK (2 of 3 satellites, 13:35 UTC)",
## "Failed (...)"); shown in the Live Data dialog.
var weather_status := "Not retrieved"
## The weather pictures of the current half hour, satellite name to [Image]; filled by [method _wx_start] and emptied
## once the maps have been composed (the saved files make a second request cheap).
var _wx_images: Dictionary = {}
## One HTTPRequest node per entry of [constant WX_SOURCES], so the three pictures download at the same time.
var _wx_http: Array[HTTPRequest] = []
## How many weather downloads are still running.
var _wx_remaining := 0
## True while the weather pictures are being fetched (downloaded or read from the saved files).
var _wx_downloading := false
## True when [member _wx_images] holds the finished set for the current half hour.
var _wx_loaded := false
## How many times each weather download (by index into [constant WX_SOURCES]) has been tried again.
var _wx_tries: Array[int] = []
## Why a weather satellite's picture is missing: satellite name to a short reason ("HTTP 503", "empty picture", ...).
var _wx_errors: Dictionary = {}
## The weather map keys ([constant WX_NAME], [constant BLEND_NAME]) that were requested and are not finished yet.
var _wx_wanted: Dictionary = {}
## The weather map keys being composed right now.
var _wx_composing: Dictionary = {}
## For each weather map key that has textures, the half-hour slot ([method _wx_slot]) its pictures came from, so an old
## map is renewed when asked for again later.
var _live_slot: Dictionary = {}
## For a weather map that is missing a satellite: the Unix time after which asking for it again fetches it again.
var _live_retry_at: Dictionary = {}
## The compositor node.
var _wx_composer: Node

## Builds [member maps] from `res://data/maps.json` (filling in missing polar files from the globe file and skipping
## maps whose files are absent), adds the live satellite maps and creates the HTTP request nodes and the weather compositor.
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
	maps.append({"id": "SatelliteNOAA21", "name": "NOAA-21 VIIRS (live)", "globe": SAT_NAME,
		"north": SAT_NAME + "_north", "south": SAT_NAME + "_south", "light": 1.0, "sea": ""})
	maps.append({"id": "SatelliteWeather", "name": "Weather satellites (live)", "globe": WX_NAME,
		"north": WX_NAME + "_north", "south": WX_NAME + "_south", "light": 1.0, "sea": ""})
	maps.append({"id": "SatelliteBlend", "name": "NOAA-21 + weather satellites (live)", "globe": BLEND_NAME,
		"north": BLEND_NAME + "_north", "south": BLEND_NAME + "_south", "light": 1.0, "sea": ""})
	_wx_composer = WeatherComposerScript.new()
	add_child(_wx_composer)
	for i in range(WX_SOURCES.size()):
		var h := HTTPRequest.new()
		h.timeout = 90.0
		add_child(h)
		h.request_completed.connect(_on_wx_downloaded.bind(i))
		_wx_http.append(h)
	_http = HTTPRequest.new()
	_http.timeout = 90.0
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
## [param file_name]: the image's file name (or a [constant SAT_NAME], [constant WX_NAME] or [constant BLEND_NAME] name).
## Returns: the texture if it is ready, otherwise null, and then [signal texture_ready] fires when it arrives. See
##   [method _request_satellite], [method _request_weather], [method _load_in_thread].
func request(file_name: String) -> Texture2D:
	if file_name.begins_with(SAT_NAME):
		return _request_satellite(file_name)
	if file_name.begins_with(WX_NAME) or file_name.begins_with(BLEND_NAME):
		return _request_weather(file_name)
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

# MARK: - Live satellite map (NASA GIBS, NOAA-21 VIIRS true color, yesterday's UTC date)

## The date of the satellite picture to fetch: yesterday in UTC, because today's picture is not complete yet.
##
## Returns: the date as "YYYY-MM-DD".
func _sat_date() -> String:
	var d := Time.get_date_dict_from_unix_time(int(Time.get_unix_time_from_system() - 86400.0))
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]

## The satellite-map part of [method request]. Uses the cache, then today's saved file (from any source, preferred
## source first) in the user-data folder, otherwise starts the download with the first source.
##
## [param file_name]: a name starting with [constant SAT_NAME] (equirectangular, "_north" or "_south").
## Returns: the texture if ready, otherwise null (it arrives through [signal texture_ready]).
func _request_satellite(file_name: String) -> Texture2D:
	if _cache.has(file_name):
		return _cache[file_name]
	if _sat_image != null:
		_build_live_textures(SAT_NAME, _sat_image)
		return _cache.get(file_name)
	if _pending.has(SAT_NAME):
		return null
	_pending[SAT_NAME] = true
	for src: Array in SAT_SOURCES:
		var cached := _sat_cache_path(str(src[0]))
		if FileAccess.file_exists(cached):
			_sat_source = str(src[0])
			_set_sat_image(Image.load_from_file(cached))
			return _cache.get(file_name)
	_sat_try = 0
	_download_satellite()
	return null

## The saved-file path for one source's picture of the current date.
##
## [param source]: the source's short name from [constant SAT_SOURCES].
## Returns: the `user://` path.
func _sat_cache_path(source: String) -> String:
	return "user://satellite_4096_%s_%s.jpg" % [source, _sat_date()]

## Starts the download from the source at [member _sat_try] and announces it through [signal satellite_progress].
func _download_satellite() -> void:
	var src: Array = SAT_SOURCES[_sat_try]
	satellite_status = "Downloading %s…" % src[0]
	var text := "Downloading the %s satellite image (4096 x 2048)…" % src[0]
	if _sat_try > 0:
		text = "%s image not available; %s" % [SAT_SOURCES[_sat_try - 1][0], text.substr(0, 1).to_lower() + text.substr(1)]
	satellite_progress.emit(text, false)
	_http.request(GIBS % [src[1], _sat_date()])

## Called when the current source did not give a usable picture: starts the next source, or gives up.
##
## [param reason]: what went wrong with the current source (for the status text).
func _satellite_failed(reason: String) -> void:
	if _sat_try + 1 < SAT_SOURCES.size():
		_sat_try += 1
		_download_satellite()
		return
	_pending.erase(SAT_NAME)
	satellite_status = "Failed (%s)" % reason
	satellite_progress.emit("Satellite image download failed (%s)." % reason, true)
	_wx_try_compose()

## Handles the end of a satellite download: tries the next source if this one failed or came back empty, otherwise
## saves the JPEG for next time and starts building the textures.
##
## [param result]: the HTTPRequest result code.
## [param code]: the HTTP status code (200 means success).
## [param _h]: the response headers (unused).
## [param body]: the downloaded JPEG bytes.
func _on_sat_downloaded(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	var name_: String = SAT_SOURCES[_sat_try][0]
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_satellite_failed("%s, HTTP %d" % [name_, code])
		return
	if body.size() < SAT_MIN_BYTES:
		_satellite_failed("%s, no data yet" % name_)
		return
	var img := Image.new()
	if img.load_jpg_from_buffer(body) != OK:
		_satellite_failed("%s, bad image" % name_)
		return
	var f := FileAccess.open(_sat_cache_path(name_), FileAccess.WRITE)
	if f != null:
		f.store_buffer(body)
		f.close()
	_sat_source = name_
	_set_sat_image(img, true)

## Stores the satellite image, marks the status OK and builds the textures with [method _build_live_textures].
##
## [param img]: the equirectangular satellite image.
## [param announce]: true after a fresh download, which emits [signal satellite_progress] with the "map switched"
## message once the globe/flat texture has been handed out; false when the picture came from today's saved file.
func _set_sat_image(img: Image, announce := false) -> void:
	_pending.erase(SAT_NAME)
	_sat_image = img
	satellite_status = "OK (%s, %s)" % [_sat_source, _sat_date()]
	_build_live_textures(SAT_NAME, _sat_image)
	_wx_try_compose()
	if announce:
		satellite_progress.emit("%s satellite image (%s) downloaded; map switched to the %s view." % [_sat_source, _sat_date(), _sat_source], true)

## Makes the textures of a live map from its equirectangular picture: the equirectangular one now, and the north and
## south polar ones on worker threads with [method _polar_in_thread]. Emits [signal texture_ready] for each as it is
## done.
##
## [param base]: the map's pseudo file name ([constant SAT_NAME], [constant WX_NAME] or [constant BLEND_NAME]); the
## polar keys append "_north" and "_south".
## [param img]: the equirectangular picture.
func _build_live_textures(base: String, img: Image) -> void:
	if not _cache.has(base):
		var eq := img.duplicate() as Image
		eq.generate_mipmaps()
		var tex := ImageTexture.create_from_image(eq)
		_cache[base] = tex
		texture_ready.emit(base, tex)
	for hemi: String in ["_north", "_south"]:
		var key := base + hemi
		if not _cache.has(key) and not _pending.has(key):
			_pending[key] = true
			WorkerThreadPool.add_task(_polar_in_thread.bind(key, hemi == "_north", img))

## Runs on a worker thread: converts the equirectangular satellite image to a polar azimuthal-equidistant picture, the
## layout of the flat polar maps (1024 by 1024, a circle in a square).
##
## [param key]: the cache key to store the result under.
## [param north]: true for the north-pole map, false for the south-pole map.
## [param src]: the equirectangular picture to convert.
## The result goes back through [method _polar_done].
func _polar_in_thread(key: String, north: bool, src: Image) -> void:
	var n := 1024
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

# MARK: - Live weather-satellite maps (GOES-West, GOES-East, Meteosat MTG, Himawari)

## The current half-hour slot, used to name saved weather pictures and to tell when a weather map has gone stale.
##
## Returns: the Unix time divided by [constant WX_SLOT_SECONDS], rounded down.
func _wx_slot() -> int:
	return int(Time.get_unix_time_from_system() / WX_SLOT_SECONDS)

## The saved-file path of one satellite's picture for one slot.
##
## [param source]: the satellite's short name from [constant WX_SOURCES].
## [param slot]: the slot number from [method _wx_slot].
## Returns: the `user://` path.
func _wx_cache_path(source: String, slot: int) -> String:
	return "user://weather_%s_%d.jpg" % [source, slot]

## The weather-map part of [method request] (the weather-only map and the blended map).
##
## [param file_name]: a name starting with [constant WX_NAME] or [constant BLEND_NAME] (equirectangular, "_north" or
## "_south").
## Returns: the texture if ready, otherwise null (it arrives through [signal texture_ready]). A map from an earlier
## half hour, or one that is missing a satellite (after [constant WX_INCOMPLETE_RETRY]), is dropped and fetched again.
func _request_weather(file_name: String) -> Texture2D:
	var base := WX_NAME if file_name.begins_with(WX_NAME) else BLEND_NAME
	if _live_slot.has(base):
		var retry_due: bool = _live_retry_at.has(base) and Time.get_unix_time_from_system() >= _live_retry_at[base]
		if _live_slot[base] == _wx_slot() and not retry_due:
			return _cache.get(file_name)
		# The pictures are older than half an hour, or a satellite was missing: forget this map and fetch it again.
		_live_slot.erase(base)
		_live_retry_at.erase(base)
		for suffix: String in ["", "_north", "_south"]:
			_cache.erase(base + suffix)
	if _cache.has(file_name):
		return _cache[file_name]
	if _wx_wanted.has(base) or _pending.has(file_name):
		return null
	_wx_wanted[base] = true
	if base == BLEND_NAME:
		# The blended map also needs the NOAA-21 picture; start it if it is not here yet.
		_request_satellite(SAT_NAME)
	_wx_start()
	return null

## Gets the weather pictures: from the saved files of this half hour where they exist, otherwise downloading
## them (all at once). Old saved weather pictures are deleted. When all are in, [method _wx_try_compose] runs.
func _wx_start() -> void:
	if _wx_loaded:
		_wx_try_compose()
		return
	if _wx_downloading:
		return
	_wx_downloading = true
	_wx_images.clear()
	_wx_errors.clear()
	_wx_tries.clear()
	_wx_tries.resize(WX_SOURCES.size())
	_wx_tries.fill(0)
	var slot := _wx_slot()
	for fname in DirAccess.get_files_at("user://"):
		if fname.begins_with("weather_") and not fname.ends_with("_%d.jpg" % slot):
			DirAccess.remove_absolute("user://" + fname)
	var to_download: Array[int] = []
	for i in range(WX_SOURCES.size()):
		var source: String = WX_SOURCES[i][0]
		var path := _wx_cache_path(source, slot)
		var img: Image = null
		if FileAccess.file_exists(path):
			img = Image.load_from_file(path)
		if img != null:
			_wx_images[source] = img
		else:
			to_download.append(i)
	_wx_remaining = to_download.size()
	if to_download.is_empty():
		_wx_downloads_finished()
		return
	weather_status = "Downloading…"
	var names: Array = []
	for src: Array in WX_SOURCES:
		names.append(src[0])
	satellite_progress.emit("Downloading weather satellite images (%s)…" % ", ".join(names), false)
	for i in to_download:
		_wx_request(i)

## Starts (or repeats) the download of one weather picture.
##
## [param index]: the entry of [constant WX_SOURCES] to fetch.
func _wx_request(index: int) -> void:
	var src: Array = WX_SOURCES[index]
	var url: String = (src[2] as String) % src[1]
	url = url.replace("{time}", _wx_time_param(_wx_tries[index]))
	_wx_http[index].request(url)

## The `time` value for an EUMETView request.
##
## [param tries]: how many times this download has already been retried; each retry goes one hour further back, in case
## the newest picture is missing on the server.
## Returns: an ISO 8601 UTC time ([constant WX_EUMETVIEW_LAG] seconds ago, rounded down to the 10-minute scan times,
## minus an hour per retry), like "2026-11-15T14:20:00Z".
func _wx_time_param(tries: int) -> String:
	var t := int(Time.get_unix_time_from_system()) - WX_EUMETVIEW_LAG - tries * 3600
	t -= t % 600
	return Time.get_datetime_string_from_unix_time(t) + "Z"

## Whether a weather picture has (almost) nothing in it: samples a grid of pixels and checks that fewer than
## [constant WX_BLANK_FRACTION] of them are lit.
##
## [param img]: the decoded picture.
## Returns: true if it is empty.
func _wx_is_blank(img: Image) -> bool:
	var lit := 0
	var total := 0
	for y in range(0, img.get_height(), 32):
		for x in range(0, img.get_width(), 32):
			var c := img.get_pixel(x, y)
			total += 1
			if maxf(c.r, maxf(c.g, c.b)) > 0.03:
				lit += 1
	return total == 0 or float(lit) / float(total) < WX_BLANK_FRACTION

## Handles the end of one weather download: keeps and saves the picture if it is good; otherwise tries once more (see
## [constant WX_RETRIES], after a growing pause from [constant WX_RETRY_DELAY]) and then records the reason in [member _wx_errors]. When the last download is in, goes on to
## [method _wx_downloads_finished].
##
## [param result]: the HTTPRequest result code.
## [param code]: the HTTP status code (200 means success).
## [param _h]: the response headers (unused).
## [param body]: the downloaded JPEG bytes.
## [param index]: which entry of [constant WX_SOURCES] this was (bound when the signal was connected).
func _on_wx_downloaded(result: int, code: int, _h: PackedStringArray, body: PackedByteArray, index: int) -> void:
	var source: String = WX_SOURCES[index][0]
	var reason := ""
	var img := Image.new()
	if result != HTTPRequest.RESULT_SUCCESS:
		reason = "no answer" if result == HTTPRequest.RESULT_TIMEOUT else "network error %d" % result
	elif code != 200:
		reason = "HTTP %d" % code
	elif body.size() < WX_MIN_BYTES or img.load_jpg_from_buffer(body) != OK:
		# A service that cannot draw the picture answers with an XML error report instead.
		reason = "server error" if body.slice(0, 5).get_string_from_utf8() == "<?xml" else "not a picture"
	elif WX_SOURCES[index][3] and _wx_is_blank(img):
		reason = "empty picture"
	if reason == "":
		_wx_images[source] = img
		var f := FileAccess.open(_wx_cache_path(source, _wx_slot()), FileAccess.WRITE)
		if f != null:
			f.store_buffer(body)
			f.close()
	elif _wx_tries[index] < WX_RETRIES:
		_wx_tries[index] += 1
		push_warning("Weather picture %s failed (%s); trying again." % [source, reason])
		await get_tree().create_timer(WX_RETRY_DELAY * _wx_tries[index]).timeout
		_wx_request(index)
		return
	else:
		_wx_errors[source] = reason
		push_warning("Weather picture %s failed (%s)." % [source, reason])
	_wx_remaining -= 1
	if _wx_remaining <= 0:
		_wx_downloads_finished()

## Called when every weather picture has been fetched or has failed: marks the set as loaded and composes the maps.
func _wx_downloads_finished() -> void:
	_wx_downloading = false
	_wx_loaded = true
	_wx_try_compose()

## Starts composing every requested weather map whose ingredients are ready: the weather pictures, and for the blended
## map also the NOAA-21 picture (or its failure). Called whenever one of those arrives.
func _wx_try_compose() -> void:
	if not _wx_loaded:
		return
	for base: String in _wx_wanted.keys():
		if _wx_composing.has(base):
			continue
		if base == BLEND_NAME and _pending.has(SAT_NAME):
			continue
		_wx_composing[base] = true
		_wx_compose(base)

## Composes one weather map with [WeatherComposer] and makes its textures. A coroutine (the GPU draws the picture).
## Once no requested map is waiting any more, the downloaded pictures are released (they stay on disk).
##
## [param base]: [constant WX_NAME] (weather satellites only) or [constant BLEND_NAME] (faded into the NOAA-21 map).
func _wx_compose(base: String) -> void:
	var blend := base == BLEND_NAME
	var count := 0
	var missing: Array = []
	for sat: String in WX_SATELLITES:
		if _wx_images.has(sat) or (sat == "Himawari" and _wx_images.has("Himawari IR")):
			count += 1
		else:
			missing.append(sat)
	if not _wx_images.has("Himawari IR") and not missing.has("Himawari"):
		missing.append("Himawari IR")
	var img: Image = null
	if count > 0 or blend:
		img = await _wx_composer.compose(_wx_images, _sat_image if blend else null, blend)
	_wx_composing.erase(base)
	_wx_wanted.erase(base)
	if _wx_wanted.is_empty():
		_wx_images.clear()
		_wx_loaded = false
	if img == null:
		weather_status = "Failed (no pictures)"
		satellite_progress.emit("Weather satellite images could not be downloaded.", true)
		return
	_live_slot[base] = _wx_slot()
	# A map that is missing a satellite may be fetched again after a couple of minutes (see [method _request_weather]);
	# the saved pictures of the satellites that worked are reused.
	if missing.is_empty():
		_live_retry_at.erase(base)
	else:
		_live_retry_at[base] = Time.get_unix_time_from_system() + WX_INCOMPLETE_RETRY
	var now := Time.get_datetime_dict_from_system(true)
	var when := "%02d:%02d UTC" % [now["hour"], now["minute"]]
	weather_status = "OK (%d of %d satellites, %s)" % [count, WX_SATELLITES.size(), when]
	_build_live_textures(base, img)
	# Kept short: on a desktop the status bar clips a message that is wider than the window.
	var text := "%s map ready (%d of %d satellites, %s); map switched." \
		% ["NOAA-21 + weather" if blend else "Weather satellite", count, WX_SATELLITES.size(), when]
	if not missing.is_empty():
		# The problem goes first: on a desktop the status bar clips a message that is wider than the window.
		var parts: Array = []
		for m: String in missing:
			parts.append("%s (%s)" % [m, _wx_errors.get(m, "no picture")])
		text = "Weather map: %s unavailable. %d of %d satellites shown." % [", ".join(parts), count, WX_SATELLITES.size()]
		weather_status += "; missing " + ", ".join(parts)
	satellite_progress.emit(text, true)
