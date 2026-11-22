extends Node
## Earthquake retrieval (autoload "QuakeService"). Counterpart of Flatland's RemoteData/USGS.
## Fetches the USGS GeoJSON feed on a timer, keeps the latest list, and reports new quakes.

## Emitted after every successful fetch, and with an empty list when earthquakes are switched off.
##
## [param quakes]: the quakes to show, as from [method visible_quakes].
signal quakes_updated(quakes: Array)
## Emitted for each quake that is new since the last fetch (never on the first load). Used for the new-quake sound.
##
## [param quake]: the quake Dictionary.
signal new_quake(quake: Dictionary)
## Emitted once per fetch with the biggest of the quakes that arrived that time, including the first load (it becomes
## Flatland's "New quake" status message).
##
## [param quake]: the quake Dictionary.
signal biggest_new_quake(quake: Dictionary)
## Emitted when a request to the USGS feed begins (the Live Data dialog shows it).
signal fetch_started
## Emitted when a request fails or the data is unusable.
##
## [param reason]: a short description, also kept in [member last_status].
signal fetch_failed(reason: String)

## The USGS GeoJSON summary feed: magnitude 4.5 and above for the past week.
const FEED_URL := "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/4.5_week.geojson"

## All quakes from the latest fetch, newest first. Each is a Dictionary: "id", "magnitude", "place", "time" (Unix
## seconds), "lat", "lon", "depth" (km) and "url". The user's filters are applied by [method visible_quakes].
var quakes: Array = []
## When the last successful fetch finished (Unix seconds); 0 before the first.
var last_fetch_unix: float = 0.0
## Text about the latest fetch for the Live Data dialog ("Retrieving", "OK (n quakes)", an error...).
var last_status: String = "Not yet retrieved"
## How many fetches have succeeded this run.
var fetch_count: int = 0

## The HTTPRequest node that downloads the feed.
var _http: HTTPRequest
## Repeating timer that calls [method refresh]; its interval is the "quake_fetch_interval" setting (at least 15 s).
var _timer: Timer
## Ids of quakes already seen, so only real newcomers are announced ([signal new_quake]).
var _known: Dictionary = {}
## True until the first fetch has been processed; the first load announces the biggest quake but no individual new
## ones.
var _first_load := true

## Creates the HTTP request and the timer, listens for setting changes and, if earthquakes are enabled, starts
## fetching.
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

## Reacts to settings: turning earthquakes on starts the timer and fetches; turning them off stops it and sends an
## empty list; changing the interval updates the timer.
##
## [param key]: the setting's key.
## [param _v]: the new value (unused).
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

## Fetches the feed now (the timer also calls this). Does nothing if a request is already running. Emits
## [signal fetch_started]; the result arrives in [method _on_completed].
func refresh() -> void:
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	fetch_started.emit()
	last_status = "Retrieving"
	var err := _http.request(FEED_URL)
	if err != OK:
		last_status = "Request failed (%d)" % err
		fetch_failed.emit(last_status)

## Handles a finished request: checks it, parses the GeoJSON into [member quakes] (newest first), works out which
## quakes are new, updates the status and emits [signal quakes_updated], [signal biggest_new_quake] and
## [signal new_quake].
##
## [param result]: the HTTPRequest result code.
## [param code]: the HTTP status (200 is success).
## [param _headers]: response headers (unused).
## [param body]: the downloaded JSON bytes.
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
		# USGS publishes e.g. 4.98 but displays it as M5.0; round the same way so the filters and colors agree with it.
		fresh.append({"id": str(f["id"]), "magnitude": snappedf(float(p["mag"]), 0.1), "place": str(p.get("place", "")),
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

## The quakes to show after the user's filters. If earthquake regions are enabled, a quake is shown when it lies in
## one and meets that region's limits ([method region_matches]); otherwise the global minimum magnitude and maximum
## age apply.
##
## Returns: an Array of quake Dictionaries (a subset of [member quakes]).
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

## The quakes to draw on the maps: [method visible_quakes], or, when "Group nearby earthquakes" (`quake_group`) is on, one
## quake per group. Quakes are grouped by size: going from the largest magnitude down, a quake within the grouping
## distance (`quake_group_km`) of a larger quake already chosen joins that quake's group, and any other quake starts a
## group of its own. So the largest quake of a group is always the one shown, for as long as it is shown at all (once it
## ages out of [method visible_quakes], the next largest one of the group takes its place).
##
## Each returned quake is a copy of the shown quake with two more keys: "group_count" (how many quakes the group has,
## 1 for a quake on its own) and "group_newest" (the time of the group's most recent quake, so a group with a new quake
## in it counts as new; see [method is_new]).
##
## Returns: an Array of quake Dictionaries (a subset of [member quakes], copied).
func map_quakes() -> Array:
	var shown := visible_quakes()
	if not Settings.get_bool("quake_group"):
		return shown
	var by_size := shown.duplicate()
	by_size.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["magnitude"] != b["magnitude"]:
			return a["magnitude"] > b["magnitude"]
		return a["time"] > b["time"])
	var limit_km := Settings.get_float("quake_group_km")
	var groups: Array = []
	for q in by_size:
		var home: Dictionary = {}
		for g in groups:
			if distance_km(g["lat"], g["lon"], q["lat"], q["lon"]) <= limit_km:
				home = g
				break
		if home.is_empty():
			var rep: Dictionary = q.duplicate()
			rep["group_count"] = 1
			rep["group_newest"] = q["time"]
			groups.append(rep)
		else:
			home["group_count"] += 1
			home["group_newest"] = maxf(home["group_newest"], q["time"])
	return groups

## The distance between two places on the Earth's surface.
##
## [param lat1]: first latitude in degrees.
## [param lon1]: first longitude in degrees.
## [param lat2]: second latitude.
## [param lon2]: second longitude.
## Returns: kilometres along the surface (the great-circle distance, with the Earth a sphere of radius 6371 km).
static func distance_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
	var p1 := deg_to_rad(lat1)
	var p2 := deg_to_rad(lat2)
	var dp := p2 - p1
	var dl := deg_to_rad(lon2 - lon1)
	var a := sin(dp * 0.5) * sin(dp * 0.5) + cos(p1) * cos(p2) * sin(dl * 0.5) * sin(dl * 0.5)
	return 2.0 * 6371.0 * asin(minf(1.0, sqrt(a)))

## Whether an earthquake is "new": the "Highlight new earthquakes" setting is on and the quake happened within the
## "New means within" time (`quake_recent_hours`). The map's new-quake indicators and the earthquake list's New marker
## both use this. A grouped quake (from [method map_quakes]) is new if any quake in its group is.
##
## [param q]: the quake Dictionary.
## [param now]: the current Unix time in seconds (default: now).
## Returns: true if the quake is new.
func is_new(q: Dictionary, now: float = Time.get_unix_time_from_system()) -> bool:
	var when: float = maxf(float(q["time"]), float(q.get("group_newest", q["time"])))
	return Settings.get_bool("quake_highlight_new") and now - when <= Settings.get_float("quake_recent_hours") * 3600.0

## How long ago a quake happened, as short text: "12 min", "3 h 12 m", "2 d 4 h".
##
## [param q]: the quake Dictionary.
## [param now]: the current Unix time in seconds (default: now).
## Returns: the text.
func age_text(q: Dictionary, now: float = Time.get_unix_time_from_system()) -> String:
	var minutes := maxi(0, int((now - float(q["time"])) / 60.0))
	if minutes < 60:
		return "%d min" % minutes
	var hours := minutes / 60
	if hours < 24:
		return "%d h %d m" % [hours, minutes % 60]
	return "%d d %d h" % [hours / 24, hours % 24]

## Whether a quake falls inside an earthquake region and within its magnitude and age limits. A region whose first
## longitude is greater than its second crosses the antimeridian (180 degrees).
##
## [param r]: the region Dictionary ("lat1", "lat2", "lon1", "lon2", "min_mag", "max_mag", "max_age_days").
## [param q]: the quake Dictionary.
## [param now]: the current Unix time, for the age limit.
## Returns: true if it matches.
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

## The color for a quake of a given size, from pale yellow for small ones to red for the largest.
##
## [param m]: the magnitude.
## Returns: the Color (9 and up red, 8 pink, 7 orange, 6 light orange, 5 yellow, below 5 pale yellow).
static func magnitude_color(m: float) -> Color:
	if m >= 9.0: return Color("#FF2400")
	if m >= 8.0: return Color("#FF2F92")
	if m >= 7.0: return Color("#FF9300")
	if m >= 6.0: return Color("#FFD478")
	if m >= 5.0: return Color("#FEFB00")
	return Color("#FEFCBF")
