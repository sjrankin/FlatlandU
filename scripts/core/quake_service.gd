extends Node
## Earthquake retrieval (autoload "QuakeService"). Counterpart of Flatland's RemoteData/USGS.
## Fetches the USGS GeoJSON feed on a timer, keeps the latest list, and reports new quakes.

signal quakes_updated(quakes: Array)
signal new_quake(quake: Dictionary)
## The biggest of the quakes that arrived in the latest update, including the first load (Flatland's
## "New quake" status message).
signal biggest_new_quake(quake: Dictionary)
signal fetch_started
signal fetch_failed(reason: String)

const FEED_URL := "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/4.5_week.geojson"

var quakes: Array = []               # newest first: {id, magnitude, place, time (unix s), lat, lon, depth}
var last_fetch_unix: float = 0.0
var last_status: String = "Not yet retrieved"
var fetch_count: int = 0

var _http: HTTPRequest
var _timer: Timer
var _known: Dictionary = {}
var _first_load := true

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 30.0
	add_child(_http)
	_http.request_completed.connect(_on_completed)
	_timer = Timer.new()
	_timer.one_shot = false
	_timer.wait_time = maxf(15.0, Settings.get_float("quake_fetch_interval"))
	_timer.timeout.connect(refresh)
	add_child(_timer)
	Settings.changed.connect(_on_setting_changed)
	if Settings.get_bool("enable_earthquakes"):
		_timer.start()
		refresh.call_deferred()

func _on_setting_changed(key: String, _v: Variant) -> void:
	if key == "enable_earthquakes":
		if Settings.get_bool("enable_earthquakes"):
			_timer.start()
			refresh()
		else:
			_timer.stop()
			quakes_updated.emit([])
	elif key == "quake_fetch_interval":
		_timer.wait_time = maxf(15.0, Settings.get_float("quake_fetch_interval"))

func refresh() -> void:
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	fetch_started.emit()
	last_status = "Retrieving"
	var err := _http.request(FEED_URL)
	if err != OK:
		last_status = "Request failed (%d)" % err
		fetch_failed.emit(last_status)

func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		last_status = "Failed (result %d, HTTP %d)" % [result, code]
		fetch_failed.emit(last_status)
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary) or not parsed.has("features"):
		last_status = "Bad data"
		fetch_failed.emit(last_status)
		return
	var fresh: Array = []
	for f in parsed["features"]:
		var p: Dictionary = f["properties"]
		var c: Array = f["geometry"]["coordinates"]
		if p.get("mag") == null:
			continue
		fresh.append({"id": str(f["id"]), "magnitude": float(p["mag"]), "place": str(p.get("place", "")),
			"time": float(p["time"]) / 1000.0, "lat": float(c[1]), "lon": float(c[0]),
			"depth": float(c[2]) if c.size() > 2 else 0.0, "url": str(p.get("url", ""))})
	fresh.sort_custom(func(a, b): return a["time"] > b["time"])
	var arrivals: Array = []
	var newcomers: Array = []
	for q in fresh:
		if not _known.has(q["id"]):
			_known[q["id"]] = true
			newcomers.append(q)
			if not _first_load:
				arrivals.append(q)
	_first_load = false
	quakes = fresh
	fetch_count += 1
	last_fetch_unix = Time.get_unix_time_from_system()
	last_status = "OK (%d quakes)" % quakes.size()
	quakes_updated.emit(visible_quakes())
	var shown := visible_quakes()
	var biggest: Dictionary = {}
	for q in newcomers:
		if shown.has(q) and (biggest.is_empty() or q["magnitude"] > biggest["magnitude"]):
			biggest = q
	if not biggest.is_empty():
		biggest_new_quake.emit(biggest)
	for q in arrivals:
		new_quake.emit(q)

## Quakes after the user's filters. If the user has enabled earthquake regions, a quake is shown
## when it lies in a region and meets that region's magnitude and age limits; otherwise the
## global magnitude/age filter applies.
func visible_quakes() -> Array:
	var now := Time.get_unix_time_from_system()
	var regions: Array = []
	for r in CityDB.regions:
		if r.get("enabled", true):
			regions.append(r)
	var out: Array = []
	if regions.is_empty():
		var min_mag := Settings.get_float("quake_min_magnitude")
		var oldest := now - Settings.get_float("quake_max_age_days") * 86400.0
		for q in quakes:
			if q["magnitude"] >= min_mag and q["time"] >= oldest:
				out.append(q)
		return out
	for q in quakes:
		for r in regions:
			if region_matches(r, q, now):
				out.append(q)
				break
	return out

static func region_matches(r: Dictionary, q: Dictionary, now: float) -> bool:
	if q["magnitude"] < float(r.get("min_mag", 0.0)) or q["magnitude"] > float(r.get("max_mag", 10.0)):
		return false
	if q["time"] < now - float(r.get("max_age_days", 7.0)) * 86400.0:
		return false
	var lat1 := float(r["lat1"])
	var lat2 := float(r["lat2"])
	var lon1 := float(r["lon1"])
	var lon2 := float(r["lon2"])
	if q["lat"] > maxf(lat1, lat2) or q["lat"] < minf(lat1, lat2):
		return false
	if lon1 <= lon2:
		return q["lon"] >= lon1 and q["lon"] <= lon2
	return q["lon"] >= lon1 or q["lon"] <= lon2   # crosses the antimeridian

static func magnitude_color(m: float) -> Color:
	if m >= 9.0: return Color("#FF2400")
	if m >= 8.0: return Color("#FF2F92")
	if m >= 7.0: return Color("#FF9300")
	if m >= 6.0: return Color("#FFD478")
	if m >= 5.0: return Color("#FEFB00")
	return Color("#FEFCBF")
