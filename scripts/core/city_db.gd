extends Node
## City, heritage-site and POI data (autoload "CityDB"); exported from Flatland's MappableS.db.

var cities: Array = []
var additional_cities: Array = []
var heritage_sites: Array = []
var pois: Array = []                  # built-in points of interest
var user_pois: Array = []             # user-defined locations (user://user_locations.json)
var regions: Array = []               # earthquake regions (user://regions.json)
var last_clicked := Vector2.ZERO      # lat, lon of the most recent "what's here" click

signal user_data_changed

const USER_POI_PATH := "user://user_locations.json"
const REGION_PATH := "user://regions.json"

func _ready() -> void:
	cities = _load("cities.json")
	additional_cities = _load("additional_cities.json")
	heritage_sites = _load("heritage_sites.json")
	pois = _load("poi.json")
	user_pois = _load_user(USER_POI_PATH)
	regions = _load_user(REGION_PATH)

func _load_user(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Array else []

func _save_user(path: String, data: Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()

func save_user_pois() -> void:
	_save_user(USER_POI_PATH, user_pois)
	user_data_changed.emit()

func save_regions() -> void:
	_save_user(REGION_PATH, regions)
	user_data_changed.emit()

func all_pois() -> Array:
	return pois + user_pois

func _load(file: String) -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + file))
	return parsed if parsed is Array else []

static func _population(c: Dictionary) -> int:
	return maxi(int(c.get("Population", 0)), int(c.get("MetropolitanPopulation", 0)))

## Cities according to the user's filter: all, capitals only, or the N largest by population
## (Flatland's "by rank" filter; the default).
func filtered_cities() -> Array:
	var filter := Settings.get_string("city_filter")
	var all := cities + additional_cities
	match filter:
		"All":
			return all
		"Capitals":
			return all.filter(func(c): return int(c["IsCapital"]) == 1)
	var sorted := all.duplicate()
	sorted.sort_custom(func(a, b): return _population(a) > _population(b))
	return sorted.slice(0, int(Settings.get_float("city_rank")))

func find_nearest(lat: float, lon: float, max_km: float = 400.0) -> Dictionary:
	var best := {}
	var best_d := max_km
	for c in cities + additional_cities:
		var d := Geo.great_circle_km(Vector2(lat, lon), Vector2(c["Latitude"], c["Longitude"]))
		if d < best_d:
			best_d = d
			best = c
	return best
