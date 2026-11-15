extends Node
## City, heritage-site and POI data (autoload "CityDB"); exported from Flatland's MappableS.db.

## The main city list, loaded from `res://data/cities.json` (exported from Flatland's MappableS.db). Each entry is a
## Dictionary with keys such as "Name", "Country", "Continent", "Latitude", "Longitude", "Population",
## "MetropolitanPopulation" and "IsCapital".
var cities: Array = []
## Extra cities (`additional_cities.json`), in the same form as [member cities]; always searched with them.
var additional_cities: Array = []
## World Heritage sites (`heritage_sites.json`), drawn when the `show_heritage_sites` setting is on.
var heritage_sites: Array = []
## The built-in points of interest (`poi.json`).
var pois: Array = []
## The user's own saved locations, kept in [constant USER_POI_PATH]. Edited by the My Locations dialog, which then
## calls [method save_user_pois].
var user_pois: Array = []
## The user's earthquake regions, kept in [constant REGION_PATH]. Edited by the Earthquake Regions dialog, which then
## calls [method save_regions].
var regions: Array = []
## Latitude and longitude of the most recent "What's Here" click, kept so dialogs (for example adding a location) can
## start from it.
var last_clicked := Vector2.ZERO

## Emitted after the user's locations or regions are saved, so views can redraw them. See [method save_user_pois] and
## [method save_regions].
signal user_data_changed

## File holding the user's own locations (JSON array) in the app's user-data folder.
const USER_POI_PATH := "user://user_locations.json"
## File holding the user's earthquake regions (JSON array) in the app's user-data folder.
const REGION_PATH := "user://regions.json"

## Loads all the data files when the autoload starts: the built-in lists with [method _load] and the user's lists with
## [method _load_user].
func _ready() -> void:
	cities = _load("cities.json")
	additional_cities = _load("additional_cities.json")
	heritage_sites = _load("heritage_sites.json")
	pois = _load("poi.json")
	user_pois = _load_user(USER_POI_PATH)
	regions = _load_user(REGION_PATH)

## Reads one of the user's JSON files.
##
## [param path]: a `user://` file path.
## Returns: the array stored there, or an empty array if the file is missing or not an array.
func _load_user(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Array else []

## Writes a user list to a JSON file (tab-indented).
##
## [param path]: a `user://` file path.
## [param data]: the array to store.
## Does nothing if the file cannot be opened.
func _save_user(path: String, data: Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()

## Saves [member user_pois] to disk and emits [signal user_data_changed]. Call it after changing the list.
func save_user_pois() -> void:
	_save_user(USER_POI_PATH, user_pois)
	user_data_changed.emit()

## Saves [member regions] to disk and emits [signal user_data_changed]. Call it after changing the list.
func save_regions() -> void:
	_save_user(REGION_PATH, regions)
	user_data_changed.emit()

## Every place of interest to draw: the built-in ones followed by the user's.
##
## Returns: a new Array ([member pois] plus [member user_pois]).
func all_pois() -> Array:
	return pois + user_pois

## Reads one of the built-in data files from `res://data/`.
##
## [param file]: the file name, for example "cities.json".
## Returns: the array stored there, or an empty array if it is missing or not an array.
func _load(file: String) -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + file))
	return parsed if parsed is Array else []

## A city's size for ranking: the larger of its own and its metropolitan-area population.
##
## [param c]: a city Dictionary.
## Returns: the population (0 if neither is recorded).
static func _population(c: Dictionary) -> int:
	return maxi(int(c.get("Population", 0)), int(c.get("MetropolitanPopulation", 0)))

## The cities to draw, according to the `city_filter` setting: "All", "Capitals" only, or (the default "Rank") the N
## largest by population, with N from the `city_rank` setting.
##
## Returns: an Array of city Dictionaries. Uses [member cities] and [member additional_cities] and
##   [method _population].
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

## Finds the city closest to a point on the Earth. Used by the What's Here popup.
##
## [param lat]: latitude in degrees.
## [param lon]: longitude in degrees.
## [param max_km]: ignore cities farther than this (default 400 km).
## Returns: the nearest city Dictionary, or an empty Dictionary if none is within range. Distances come from
##   [method Geo.great_circle_km].
func find_nearest(lat: float, lon: float, max_km: float = 400.0) -> Dictionary:
	var best := {}
	var best_d := max_km
	for c in cities + additional_cities:
		var d := Geo.great_circle_km(Vector2(lat, lon), Vector2(c["Latitude"], c["Longitude"]))
		if d < best_d:
			best_d = d
			best = c
	return best
