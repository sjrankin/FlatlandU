extends Node
## Satellite positions (autoload "SatelliteService"). Fetches the orbital elements (TLEs) of ten bright,
## easily seen satellites from CelesTrak's "visual" list, caches them, and works out where each one is
## from a two-body orbit with the J2 correction. That is accurate to a few kilometres to a few tens of
## kilometres for days after the element set, which is plenty for a picture of satellites on a map.

## Emitted when a fresh set of satellite elements has been downloaded and saved.
signal updated

## CelesTrak URL for one satellite's element set (TLE). The `%d` is the NORAD catalogue number.
const URL_FORMAT := "https://celestrak.org/NORAD/elements/gp.php?CATNR=%d&FORMAT=tle"
## File where the downloaded element sets are kept, so satellites show at once next time and offline.
const CACHE_PATH := "user://satellites.tle"
## How old the saved elements may get (12 hours) before [method refresh_if_stale] downloads new ones.
const MAX_AGE_SECONDS := 12.0 * 3600.0
## Mean Earth radius in km, used to turn a distance from the center into an altitude.
const EARTH_RADIUS_KM := 6371.0
## Equatorial Earth radius in km, used by the J2 correction in [method position_of].
const EARTH_EQUATORIAL_KM := 6378.137
## Earth's gravitational parameter, in km^3 per second squared; gives an orbit's size from its speed.
const MU := 398600.4418
## The Earth's oblateness coefficient; makes the orbit's plane and perigee slowly turn (the "J2 correction").
const J2 := 1.08262668e-3

## Every satellite that can be tracked: [NORAD catalogue number, short name]. Which ones are drawn is the
## `tracked_satellites` setting (see [method tracked_ids]).
const CATALOG := [
	[25544, "ISS"], [48274, "Tiangong"], [20580, "Hubble"], [27386, "Envisat"], [25994, "Terra"],
	[27424, "Aqua"], [28931, "ALOS"], [39766, "ALOS-2"], [16908, "Ajisai"], [29228, "Resurs-DK1"],
	[43013, "NOAA 20"], [54234, "NOAA 21"], [60133, "GOES East"], [51850, "GOES West"],
	[50463, "Webb"], [100532, "Roman"], [40267, "Himawari-8"], [41836, "Himawari-9"], [54743, "MTG-I1"],
	[64723, "MTG-S1"], [65159, "MetOp-SG A1"], [28912, "Meteosat-9"], [39216, "INSAT-3D"],
]

## Satellites at the Sun-Earth L2 point (1.5 million km from the Earth, opposite the Sun): Webb (50463) and the Nancy
## Grace Roman Space Telescope (100532, launched 2026-08-30). No orbit data is published for them, so
## [method position_of] places them at the anti-solar point.
const L2_IDS := [50463, 100532]
## Small offsets (latitude, longitude in degrees) per L2 satellite so two of them do not sit exactly on top of each
## other on the map.
const L2_OFFSETS := {50463: Vector2(0.0, 0.0), 100532: Vector2(3.0, 8.0)}
## Altitude given to L2 satellites, in km.
const L2_ALTITUDE_KM := 1500000.0

## Parsed orbital elements by NORAD id: "epoch" (Unix s), "inc", "raan", "argp", "ma" (radians), "ecc", "n" (rad/s),
## "a" (km), plus "id" and "label". Filled by [method _parse].
var elements: Dictionary = {}
## Each satellite's three TLE lines by NORAD id, kept so they can be written to [constant CACHE_PATH].
var _raw: Dictionary = {}
## NORAD ids still to download in the current refresh; one is requested at a time.
var _fetch_queue: Array = []
## How many downloads in the current refresh gave usable data.
var _fetch_ok := 0
## True while a refresh is running, so another is not started.
var _fetching := false
## Text about the latest fetch for the Live Data dialog.
var last_status := "No satellite data yet"
## When the elements were last downloaded (Unix seconds); for a cache load, the file's modified time.
var last_fetch_unix := 0.0
## The HTTPRequest node that downloads the element sets.
var _request: HTTPRequest

## Creates the HTTP request, loads the saved elements, and starts watching the `show_satellites` setting so turning
## satellites on fetches fresh data if the saved ones are stale.
func _ready() -> void:
	_request = HTTPRequest.new()
	_request.timeout = 30.0
	_request.request_completed.connect(_on_completed)
	add_child(_request)
	_load_cache()
	Settings.changed.connect(func(key: String, _v: Variant) -> void:
		if key == "show_satellites":
			refresh_if_stale())
	refresh_if_stale()

## Whether satellites are switched on.
##
## Returns: the `show_satellites` setting.
func is_enabled() -> bool:
	return Settings.get_bool("show_satellites")

## The NORAD ids of the satellites the user chose to show (the `tracked_satellites` setting is a comma-separated
## list).
##
## Returns: an Array of ints.
func tracked_ids() -> Array:
	var ids: Array = []
	for part in Settings.get_string("tracked_satellites").split(",", false):
		ids.append(int(part))
	return ids

## Whether one satellite is chosen.
##
## [param id]: NORAD id.
## Returns: true if it is in [method tracked_ids].
func is_tracked(id: int) -> bool:
	return tracked_ids().has(id)

## Chooses or un-chooses a satellite and saves the setting, keeping [constant CATALOG] order so the stored text is
## stable.
##
## [param id]: NORAD id.
## [param on]: true to track it, false to stop.
func set_tracked(id: int, on: bool) -> void:
	var ids := tracked_ids()
	if on and not ids.has(id):
		ids.append(id)
	elif not on:
		ids.erase(id)
	# Keep the catalogue order so the stored value is stable.
	var ordered: PackedStringArray = []
	for entry in CATALOG:
		if ids.has(int(entry[0])):
			ordered.append(str(entry[0]))
	Settings.set_value("tracked_satellites", ",".join(ordered))

## Downloads new elements if satellites are on and either some catalogue entry has no elements or the data is older
## than [constant MAX_AGE_SECONDS]. Does nothing if satellites are off. See [method refresh].
func refresh_if_stale() -> void:
	if not is_enabled():
		return
	var missing := false
	for entry in CATALOG:
		if not L2_IDS.has(int(entry[0])) and not elements.has(int(entry[0])):
			missing = true
	if missing or Time.get_unix_time_from_system() - last_fetch_unix > MAX_AGE_SECONDS:
		refresh()

## Starts downloading the element set of every catalogue satellite (except the L2 ones, which need none), one request
## after another. Does nothing if a refresh is already running. Progress goes through [method _fetch_next],
## [method _on_completed] and [method _finish_fetch].
func refresh() -> void:
	if _fetching:
		return
	_fetching = true
	_fetch_ok = 0
	_fetch_queue = []
	for entry in CATALOG:
		if not L2_IDS.has(int(entry[0])):
			_fetch_queue.append(int(entry[0]))
	last_status = "Fetching satellite data…"
	_fetch_next()

## Requests the next queued satellite, or finishes with [method _finish_fetch] when the queue is empty.
func _fetch_next() -> void:
	if _fetch_queue.is_empty():
		_finish_fetch()
		return
	var id: int = _fetch_queue.pop_front()
	_request.request(URL_FORMAT % id)

## Handles one finished download: counts it if the text parsed ([method _parse]), then goes on to the next
## ([method _fetch_next]).
##
## [param result]: HTTPRequest result code.
## [param code]: HTTP status (200 is success).
## [param _headers]: response headers (unused).
## [param body]: the downloaded TLE text.
func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		if _parse(body.get_string_from_utf8()) > 0:
			_fetch_ok += 1
	_fetch_next()

## Ends a refresh: if nothing was received it records the failure; otherwise it notes the time, writes all element
## lines to [constant CACHE_PATH], and emits [signal updated].
func _finish_fetch() -> void:
	_fetching = false
	if _fetch_ok == 0:
		last_status = "Could not fetch satellite data"
		return
	last_fetch_unix = Time.get_unix_time_from_system()
	var f := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if f != null:
		for id in _raw.keys():
			f.store_string(str(_raw[id]))
	last_status = "OK (%d satellites)" % elements.size()
	updated.emit()

## Loads the saved element sets (if the file exists) at start-up, setting [member last_fetch_unix] from the file's
## age.
func _load_cache() -> void:
	if not FileAccess.file_exists(CACHE_PATH):
		return
	if _parse(FileAccess.get_file_as_string(CACHE_PATH)) > 0:
		last_fetch_unix = float(FileAccess.get_modified_time(CACHE_PATH))
		last_status = "Cached (%d satellites)" % elements.size()

## Parses three-line element sets (name line, line 1, line 2) and keeps those in [constant CATALOG], adding them to
## [member elements] and [member _raw].
##
## [param text]: one or more TLE sets, as text.
## Returns: how many satellites were kept. See [method _parse_elements].
func _parse(text: String) -> int:
	var wanted := {}
	for entry in CATALOG:
		wanted[int(entry[0])] = str(entry[1])
	var lines := text.split("\n", false)
	var found := 0
	var i := 0
	while i + 2 < lines.size():
		var l1 := lines[i + 1]
		var l2 := lines[i + 2]
		if l1.begins_with("1 ") and l2.begins_with("2 "):
			var cat := int(l1.substr(2, 5))
			if wanted.has(cat):
				var el := _parse_elements(l1, l2)
				if not el.is_empty():
					el["id"] = cat
					el["label"] = wanted[cat]
					elements[cat] = el
					_raw[cat] = "%s\n%s\n%s\n" % [lines[i], l1, l2]
					found += 1
			i += 3
		else:
			i += 1
	return found

## Decodes one satellite's two TLE lines into orbital elements.
##
## [param l1]: TLE line 1 (epoch).
## [param l2]: TLE line 2 (inclination, node, eccentricity, argument of perigee, mean anomaly, mean motion).
## Returns: a Dictionary of elements ("epoch", "inc", "raan", "ecc", "argp", "ma", "n", "a"), or an empty one if the
##   lines are too short or the motion is not positive.
func _parse_elements(l1: String, l2: String) -> Dictionary:
	if l1.length() < 32 or l2.length() < 63:
		return {}
	var yy := int(l1.substr(18, 2))
	var year := 2000 + yy if yy < 57 else 1900 + yy
	var day := float(l1.substr(20, 12))
	var jan1 := Time.get_unix_time_from_datetime_dict({"year": year, "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0})
	var n_rev_day := float(l2.substr(52, 11))
	if n_rev_day <= 0.0:
		return {}
	var n := n_rev_day * TAU / 86400.0
	return {
		"epoch": float(jan1) + (day - 1.0) * 86400.0,
		"inc": deg_to_rad(float(l2.substr(8, 8))),
		"raan": deg_to_rad(float(l2.substr(17, 8))),
		"ecc": float("0." + l2.substr(26, 7).strip_edges()),
		"argp": deg_to_rad(float(l2.substr(34, 8))),
		"ma": deg_to_rad(float(l2.substr(43, 8))),
		"n": n,                                   # rad / s
		"a": pow(MU / (n * n), 1.0 / 3.0),        # km
	}

## Greenwich mean sidereal time: how far the Earth has turned relative to the stars, needed to turn an orbit's
## inertial position into a longitude.
##
## [param unix]: Unix time in seconds (UTC).
## Returns: the angle in radians.
static func gmst(unix: float) -> float:
	var jd := unix / 86400.0 + 2440587.5
	return deg_to_rad(fposmod(280.46061837 + 360.98564736629 * (jd - 2451545.0), 360.0))

## Writes an altitude for a satellite label.
##
## [param alt_km]: altitude in km.
## Returns: text like "423 km", or "1.5 million km" for far-away satellites.
static func format_altitude(alt_km: float) -> String:
	if alt_km >= 100000.0:
		return "%.1f million km" % (alt_km / 1000000.0)
	return "%d km" % int(round(alt_km))

## Where a satellite is at a moment, from a two-body orbit with the J2 correction (good to a few km up to a few tens
## of km for days after the element set). L2 satellites are placed opposite the Sun instead.
##
## [param id]: NORAD id.
## [param unix]: Unix time in seconds (UTC).
## Returns: a Dictionary {"lat", "lon" (degrees), "alt_km"}, or an empty one if the satellite is unknown.
func position_of(id: int, unix: float) -> Dictionary:
	if L2_IDS.has(id):
		var offset: Vector2 = L2_OFFSETS.get(id, Vector2.ZERO)
		return {"lat": clampf(-Solar.declination(unix) + offset.x, -90.0, 90.0),
			"lon": wrapf(Solar.subsolar_longitude(unix) + 180.0 + offset.y, -180.0, 180.0), "alt_km": L2_ALTITUDE_KM}
	if not elements.has(id):
		return {}
	var el: Dictionary = elements[id]
	var dt := unix - float(el["epoch"])
	var e: float = el["ecc"]
	var a: float = el["a"]
	var inc: float = el["inc"]
	var n: float = el["n"]
	var p := a * (1.0 - e * e)
	var j2f := 1.5 * J2 * pow(EARTH_EQUATORIAL_KM / p, 2.0) * n
	var raan: float = el["raan"] - j2f * cos(inc) * dt
	var argp: float = el["argp"] + 0.5 * j2f * (5.0 * cos(inc) * cos(inc) - 1.0) * dt
	var m := fposmod(float(el["ma"]) + n * dt, TAU)
	var ecc_anomaly := m
	for _i in range(8):
		ecc_anomaly -= (ecc_anomaly - e * sin(ecc_anomaly) - m) / (1.0 - e * cos(ecc_anomaly))
	var nu := 2.0 * atan2(sqrt(1.0 + e) * sin(ecc_anomaly * 0.5), sqrt(1.0 - e) * cos(ecc_anomaly * 0.5))
	var r := a * (1.0 - e * cos(ecc_anomaly))
	var u := argp + nu
	var x := r * (cos(raan) * cos(u) - sin(raan) * cos(inc) * sin(u))
	var y := r * (sin(raan) * cos(u) + cos(raan) * cos(inc) * sin(u))
	var z := r * sin(inc) * sin(u)
	var th := gmst(unix)
	var xe := x * cos(th) + y * sin(th)
	var ye := -x * sin(th) + y * cos(th)
	return {
		"lat": rad_to_deg(asin(clampf(z / r, -1.0, 1.0))),
		"lon": rad_to_deg(atan2(ye, xe)),
		"alt_km": r - EARTH_RADIUS_KM,
	}

## Every tracked satellite's position at a moment, for drawing.
##
## [param unix]: Unix time in seconds (UTC).
## Returns: an Array of Dictionaries {id, label, lat, lon, alt_km, next_lat, next_lon}. next_lat and next_lon are the
##   position 10 seconds later, with the longitude continued past +-180 rather than wrapped, so the heading computed
##   from the pair stays right when a satellite crosses the date line. Used by GlobeView `_update_satellites` and
##   FlatView.
func positions(unix: float) -> Array:
	var out: Array = []
	var tracked := tracked_ids()
	for entry in CATALOG:
		var id := int(entry[0])
		if not tracked.has(id):
			continue
		var here := position_of(id, unix)
		if here.is_empty():
			continue
		var ahead := position_of(id, unix + 10.0)
		out.append({
			"id": id, "label": str(entry[1]), "lat": here["lat"], "lon": here["lon"], "alt_km": here["alt_km"],
			# Longitude continued past +-180 rather than wrapped, so the pair never straddles the map edge and the
			# heading computed from it stays right while a satellite crosses the date line.
			"next_lat": ahead["lat"], "next_lon": float(here["lon"]) + wrapf(float(ahead["lon"]) - float(here["lon"]), -180.0, 180.0),
		})
	return out
