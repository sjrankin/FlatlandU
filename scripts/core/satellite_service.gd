extends Node
## Satellite positions (autoload "SatelliteService"). Fetches the orbital elements (TLEs) of ten bright,
## easily seen satellites from CelesTrak's "visual" list, caches them, and works out where each one is
## from a two-body orbit with the J2 correction. That is accurate to a few kilometres to a few tens of
## kilometres for days after the element set, which is plenty for a picture of satellites on a map.

signal updated

const URL_FORMAT := "https://celestrak.org/NORAD/elements/gp.php?CATNR=%d&FORMAT=tle"
const CACHE_PATH := "user://satellites.tle"
const MAX_AGE_SECONDS := 12.0 * 3600.0
const EARTH_RADIUS_KM := 6371.0
const EARTH_EQUATORIAL_KM := 6378.137
const MU := 398600.4418      # km^3 / s^2
const J2 := 1.08262668e-3

## NORAD catalogue number and short name of every satellite that can be tracked.
const CATALOG := [
	[25544, "ISS"], [48274, "Tiangong"], [20580, "Hubble"], [27386, "Envisat"], [25994, "Terra"],
	[27424, "Aqua"], [28931, "ALOS"], [39766, "ALOS-2"], [16908, "Ajisai"], [29228, "Resurs-DK1"],
	[43013, "NOAA 20"], [54234, "NOAA 21"], [60133, "GOES East"], [51850, "GOES West"],
	[50463, "Webb"], [100532, "Roman"], [40267, "Himawari-8"], [41836, "Himawari-9"], [54743, "MTG-I1"],
	[64723, "MTG-S1"], [65159, "MetOp-SG A1"], [28912, "Meteosat-9"], [39216, "INSAT-3D"],
]

## Satellites at the Sun-Earth L2 point (1.5 million km from the Earth, opposite the Sun). No orbit data is
## published for them, so they are placed at the anti-solar point.
## Webb (50463) and the Nancy Grace Roman Space Telescope (100532, launched 2026-08-30) are at L2.
const L2_IDS := [50463, 100532]
## Small offsets (degrees) so two L2 satellites do not sit exactly on top of each other on the map.
const L2_OFFSETS := {50463: Vector2(0.0, 0.0), 100532: Vector2(3.0, 8.0)}
const L2_ALTITUDE_KM := 1500000.0

var elements: Dictionary = {}     # NORAD id -> parsed orbital elements
var _raw: Dictionary = {}         # NORAD id -> its three element lines, kept for the cache
var _fetch_queue: Array = []
var _fetch_ok := 0
var _fetching := false
var last_status := "No satellite data yet"
var last_fetch_unix := 0.0
var _request: HTTPRequest

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

func is_enabled() -> bool:
	return Settings.get_bool("show_satellites")

## Which satellites are tracked is stored as a comma-separated list of NORAD ids.
func tracked_ids() -> Array:
	var ids: Array = []
	for part in Settings.get_string("tracked_satellites").split(",", false):
		ids.append(int(part))
	return ids

func is_tracked(id: int) -> bool:
	return tracked_ids().has(id)

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

func refresh_if_stale() -> void:
	if not is_enabled():
		return
	var missing := false
	for entry in CATALOG:
		if not L2_IDS.has(int(entry[0])) and not elements.has(int(entry[0])):
			missing = true
	if missing or Time.get_unix_time_from_system() - last_fetch_unix > MAX_AGE_SECONDS:
		refresh()

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

func _fetch_next() -> void:
	if _fetch_queue.is_empty():
		_finish_fetch()
		return
	var id: int = _fetch_queue.pop_front()
	_request.request(URL_FORMAT % id)

func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		if _parse(body.get_string_from_utf8()) > 0:
			_fetch_ok += 1
	_fetch_next()

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

func _load_cache() -> void:
	if not FileAccess.file_exists(CACHE_PATH):
		return
	if _parse(FileAccess.get_file_as_string(CACHE_PATH)) > 0:
		last_fetch_unix = float(FileAccess.get_modified_time(CACHE_PATH))
		last_status = "Cached (%d satellites)" % elements.size()

## Parse three-line element sets and keep the ones in CATALOG. Returns how many were kept.
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

## Greenwich mean sidereal time in radians.
static func gmst(unix: float) -> float:
	var jd := unix / 86400.0 + 2440587.5
	return deg_to_rad(fposmod(280.46061837 + 360.98564736629 * (jd - 2451545.0), 360.0))

## Altitude as text: "423 km", or "1.5 million km" for far-away satellites.
static func format_altitude(alt_km: float) -> String:
	if alt_km >= 100000.0:
		return "%.1f million km" % (alt_km / 1000000.0)
	return "%d km" % int(round(alt_km))

## Latitude, longitude (degrees) and altitude (km) of satellite `id` at `unix`, or {} if unknown.
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

## Every tracked satellite at `unix`: {id, label, lat, lon, alt_km, next_lat, next_lon} where next_* is the
## position ten seconds later (used to point the satellite along its track).
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
