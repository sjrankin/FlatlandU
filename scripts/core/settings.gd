extends Node
## Persistent settings (autoload "Settings"). Mirrors Flatland's Settings/SettingKeys idiom:
## every setting has a key and a default, and listeners are told when a value changes.

signal changed(key: String, value: Variant)

const PATH := "user://settings.cfg"
const SECTION := "flatland"

## View types, same raw values as Flatland's ViewTypes enum.
const VIEW_FLAT_NORTH := "FlatNorthCenter"
const VIEW_FLAT_SOUTH := "FlatSouthCenter"
const VIEW_GLOBE := "3DGlobe"
const VIEW_CUBIC := "Cubic"
const VIEW_RECT := "Rectangular"

## Hour label types, same raw values as Flatland's HourValueTypes enum.
const HOURS_NONE := "NoHours"
const HOURS_SOLAR := "RelativeToSolar"
const HOURS_NOON := "RelativeToNoon"
const HOURS_LOCATION := "RelativeToLocation"
const HOURS_WALL := "WallClock"

## Night darkness alpha levels (Flatland's NightDarknesses).
const NIGHT_ALPHA := {"VeryLight": 0.25, "Light": 0.4, "Dark": 0.6, "VeryDark": 0.75}

const DEFAULTS := {
	"view_type": VIEW_GLOBE,
	"map_type": "Simple",
	"show_night": true,
	"night_darkness": "Dark",
	"hour_type": HOURS_NOON,
	"time_label": "UTC",          # None, UTC, Local
	"time_label_seconds": true,
	"show_status_bar": true,
	"show_cities": true,
	"city_filter": "Rank",        # All, Capitals, Rank
	"city_rank": 100,
	"show_city_names": true,
	"show_heritage_sites": false,
	"show_user_pois": false,
	"show_sun": true,
	"show_grid": true,
	"show_equator": true,
	"show_polar_circles": true,
	"show_tropics": true,
	"show_noon_meridians": true,
	"show_minor_grid": true,
	"show_moon_light": true,
	"show_stars": true,
	"attract_mode": false,
	"world_locked": false,
	"enable_earthquakes": true,
	"quake_min_magnitude": 4.0,
	"quake_max_age_days": 7,
	"quake_fetch_interval": 60.0,
	"quake_shape": "Animated Arrow",
	"quake_scale": "Normal",
	"quake_highlight_new": true,
	"quake_indicator": "Radiating Rings",
	"quake_recent_hours": 24,
	"city_shape": "Uniform Flush Spheres",
	"city_scale": "Normal",
	"enable_sounds": true,
	"quake_sound": "Chime.mp3",
	"home_latitude": 51.4779,
	"home_longitude": 0.0,
	"home_name": "Greenwich",
	"mouse_tracking": true,
	"show_debug_grid": false,
	"show_intro": true,
	"show_fps": true,
	"show_satellites": false,
	"tracked_satellites": "25544,48274,20580,27386,25994,27424,28931,39766,16908,29228",
	"show_shadows": true,
	"show_shadows_3d": true,
	"show_regions": true,
	"label_font": "",
	"color_grid": "#808080",
	"color_hours": "#b5381a",
	"color_hours_2d": "#f4a460",
	"color_background": "#000000",
	"color_city_2d": "#c6f01c",
	"color_city_capital": "#ffff00",
	"color_city_africa": "#0000ff",
	"color_city_asia": "#996633",
	"color_city_europe": "#ff00ff",
	"color_city_north_america": "#00ff00",
	"color_city_south_america": "#00ffff",
	"debug_time_tick": 0,
}

var _values: Dictionary = {}
var _overrides: Dictionary = {}   # this run only (command-line development flags); never saved

func _ready() -> void:
	_values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for key in DEFAULTS.keys():
			if cfg.has_section_key(SECTION, key):
				_values[key] = cfg.get_value(SECTION, key)

func get_value(key: String) -> Variant:
	if _overrides.has(key):
		return _overrides[key]
	return _values.get(key, DEFAULTS.get(key))

func get_bool(key: String) -> bool:
	return bool(get_value(key))

func get_float(key: String) -> float:
	return float(get_value(key))

func get_color(key: String) -> Color:
	return Color(str(get_value(key)))

func get_string(key: String) -> String:
	return str(get_value(key))

func set_value(key: String, value: Variant) -> void:
	var had_override := _overrides.has(key)
	_overrides.erase(key)   # a real change replaces any command-line override
	if _values.get(key) == value and not had_override:
		return
	_values[key] = value
	changed.emit(key, value)
	_save()

## Set a value for this run only (used by command-line development options).
func override(key: String, value: Variant) -> void:
	_overrides[key] = value

func reset_all() -> void:
	for key in DEFAULTS.keys():
		set_value(key, DEFAULTS[key])

func _save() -> void:
	var cfg := ConfigFile.new()
	for key in _values.keys():
		cfg.set_value(SECTION, key, _values[key])
	cfg.save(PATH)
