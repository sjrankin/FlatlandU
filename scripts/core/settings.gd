extends Node
## Persistent settings (autoload "Settings"). Mirrors Flatland's Settings/SettingKeys idiom:
## every setting has a key and a default, and listeners are told when a value changes.

## Emitted after a setting's value changes (not for [method override]).
##
## [param key]: the setting's key (a key of [constant DEFAULTS]).
## [param value]: the new value.
## Views and services connect to this to update themselves; see GlobeView `_on_setting_changed` and PowerManager
## `_ready`.
signal changed(key: String, value: Variant)

## Where settings are saved: the app's user-data folder (survives updates).
const PATH := "user://settings.cfg"
## The section name used inside the settings file (a Godot ConfigFile).
const SECTION := "flatland"

## Value of the `view_type` setting for the polar map centered on the north pole (same raw value as Flatland's
## ViewTypes).
const VIEW_FLAT_NORTH := "FlatNorthCenter"
## `view_type` value for the polar map centered on the south pole.
const VIEW_FLAT_SOUTH := "FlatSouthCenter"
## `view_type` value for the 3D globe (the default view).
const VIEW_GLOBE := "3DGlobe"
## `view_type` value for the 3D cubic Earth.
const VIEW_CUBIC := "Cubic"
## `view_type` value for the rectangular (equirectangular) map.
const VIEW_RECT := "Rectangular"
## The value of a sound setting (such as `quake_sound`) that means "No Sound": nothing is played.
const NO_SOUND := ""

## `hour_type` value: no hour labels.
const HOURS_NONE := "NoHours"
## `hour_type` value: labels show the solar hour (00:00 to 23:00) of each meridian relative to the Sun.
const HOURS_SOLAR := "RelativeToSolar"
## `hour_type` value: labels count hours before and after solar noon (-12 to +11). The default.
const HOURS_NOON := "RelativeToNoon"
## `hour_type` value: labels count hours from the home location, which is labeled "Home".
const HOURS_LOCATION := "RelativeToLocation"
## `hour_type` value: labels show the wall-clock time at each meridian; they change every minute (see GlobeView
## `_renew_next_hour`).
const HOURS_WALL := "WallClock"

## How dark the night side of the flat maps is, by the `night_darkness` setting: the opacity (0 to 1) of the shading.
## Same names as Flatland's NightDarknesses.
const NIGHT_ALPHA := {"VeryLight": 0.25, "Light": 0.4, "Dark": 0.6, "VeryDark": 0.75}

## Every setting and its default value. A key must appear here to exist: [method get_value] falls back to it, and
## [method _ready] loads only keys listed here from the settings file. The keys are grouped roughly as: view and map,
## hours and time label, cities and places, Sun/Moon/stars, grid lines, earthquakes, satellites, home location,
## performance (see PowerManager), folders and colors.
const DEFAULTS := {
	"view_type": VIEW_GLOBE,  # which view is shown (a VIEW_ constant)
	"map_type": "NOAA-21 VIIRS (live)",  # name of the map picture used (see MapCatalog); the default is the live NOAA-21 satellite map
	"show_night": true,  # shade the night side on the flat maps
	"night_darkness": "Dark",  # how dark that shading is (a key of NIGHT_ALPHA)
	"hour_type": HOURS_NOON,  # the hour label style (an HOURS_ constant)
	"time_label": "UTC",  # clock at the top: None, UTC or Local
	"time_label_seconds": true,  # show seconds in the clock
	"show_status_bar": true,  # show the message bar at the bottom
	"show_cities": true,  # draw cities
	"city_filter": "Rank",  # which cities: All, Capitals or Rank
	"city_rank": 100,  # with the Rank filter, how many of the top cities to show
	"show_city_names": true,  # write city names next to the markers
	"show_heritage_sites": false,  # draw World Heritage sites
	"show_user_pois": false,  # draw the user's own saved places
	"show_sun": true,  # draw the Sun
	"show_moon": true,  # draw the Moon in the 3D views
	"show_grid": true,  # draw the latitude/longitude grid
	"show_equator": true,  # draw the equator
	"show_polar_circles": true,  # draw the Arctic and Antarctic circles
	"show_tropics": true,  # draw the tropics of Cancer and Capricorn
	"show_noon_meridians": true,  # draw the noon and midnight meridians
	"show_minor_grid": true,  # draw the finer grid lines
	"show_moon_light": true,  # light the night side faintly, as moonlight (3D)
	"show_sun_point": true,  # draw a ball on the Earth under the Sun
	"show_moon_point": true,  # draw a ball on the Earth under the Moon
	"show_stars": true,  # draw the star field in the 3D views
	"attract_mode": false,  # spin the globe by itself
	"world_locked": false,  # ignore mouse/touch camera control
	"enable_earthquakes": true,  # fetch and show earthquakes
	"quake_min_magnitude": 4.0,  # smallest magnitude shown
	"quake_max_age_days": 7,  # oldest quake shown, in days
	"quake_fetch_interval": 60.0,  # seconds between earthquake feed requests (at least 15)
	"quake_shape": "Animated Arrow",  # 3D shape used for a quake
	"quake_scale": "Normal",  # size of those shapes
	"quake_highlight_new": true,  # mark new quakes
	"quake_indicator": "Radiating Rings",  # how new quakes are marked (see PowerManager.quakes_animate)
	"quake_recent_hours": 24,  # how long a quake counts as new, in hours
	"quake_group": false,  # group nearby earthquakes on the map: only the largest of a group is drawn
	"quake_group_km": 100,  # how close (km) earthquakes must be to one another to be grouped
	"city_shape": "Uniform Flush Spheres",  # 3D shape used for a city
	"city_scale": "Normal",  # size of those shapes
	"enable_sounds": true,  # play sounds
	"quake_sound": "Chime.mp3",  # sound file played for a new quake (NO_SOUND for none)
	"home_latitude": 51.4779,  # latitude of the home location
	"home_longitude": 0.0,  # longitude of the home location
	"home_name": "Greenwich",  # name of the home location
	"mouse_tracking": true,  # show what is under the mouse in the status bar
	"show_debug_grid": false,  # show the debugging grid of values
	"show_intro": true,  # show the welcome text at start-up
	"show_fps": true,  # show the frame rate at the top right
	"frame_rate": "Auto",  # frame rate cap: Auto, 30, 60 or 120 (see PowerManager)
	"follow_low_power": true,  # lower the frame rate in Low Power Mode or when hot
	"draw_on_demand": true,  # phones: draw only a few times a second when nothing is touched or moving
	"keep_screen_on": false,  # stop the phone auto-locking while Flatland is in front
	"graphics_quality": "Auto",  # Auto, High, Medium or Low (see PowerManager)
	"show_satellites": false,  # draw satellites
	"tracked_satellites": "25544,48274,20580,27386,25994,27424,28931,39766,16908,29228",  # comma-separated NORAD ids of the satellites to draw (see SatelliteService)
	"show_shadows": true,  # shadows under the flat map city markers
	"show_shadows_3d": true,  # 3D shadows (labels, cities, earthquakes)
	"show_regions": true,  # draw earthquake regions
	"label_font": "",  # name of the font for labels; empty means the default (see Geo.label_font)
	"snapshot_dir": "",  # folder of the last saved snapshot; the Save dialog opens here
	"video_dir": "",  # folder of the last saved video
	"color_grid": "#808080",  # grid line color
	"color_hours": "#b5381a",  # hour label color in 3D
	"color_hours_2d": "#f4a460",  # hour label color on the flat maps
	"color_background": "#000000",  # background color
	"color_city_2d": "#c6f01c",  # city marker color on the flat maps
	"color_city_capital": "#ffff00",  # capital cities
	"color_city_africa": "#0000ff",  # cities in Africa
	"color_city_asia": "#996633",  # cities in Asia
	"color_city_europe": "#ff00ff",  # cities in Europe
	"color_city_north_america": "#00ff00",  # cities in North America
	"color_city_south_america": "#00ffff",  # cities in South America
	"debug_time_tick": 0,  # debugger time-step setting
}

## The current value of every setting (starts as a copy of [constant DEFAULTS], then the saved file is applied).
## Changed by [method set_value] and written by [method _save].
var _values: Dictionary = {}
## Values that apply to this run only (set by command-line development flags through [method override]); [method get_value] prefers them and they are never saved.
var _overrides: Dictionary = {}

## Loads the saved settings: starts from [constant DEFAULTS] and applies whatever the settings file holds for known
## keys. Runs when the autoload enters the tree, before any view is built.
func _ready() -> void:
	_values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for key in DEFAULTS.keys():
			if cfg.has_section_key(SECTION, key):
				_values[key] = cfg.get_value(SECTION, key)

## Reads a setting.
##
## [param key]: the setting's key.
## Returns: the run-only override if there is one, otherwise the saved value, otherwise the default. The typed readers
##   [method get_bool], [method get_float], [method get_string] and [method get_color] convert this.
func get_value(key: String) -> Variant:
	if _overrides.has(key):
		return _overrides[key]
	return _values.get(key, DEFAULTS.get(key))

## Reads a setting as a bool.
##
## [param key]: the setting's key.
## Returns: the value converted with `bool()`.
func get_bool(key: String) -> bool:
	return bool(get_value(key))

## Reads a setting as a float.
##
## [param key]: the setting's key.
## Returns: the value converted with `float()`.
func get_float(key: String) -> float:
	return float(get_value(key))

## Reads a setting as a color (settings hold colors as "#rrggbb" text).
##
## [param key]: the setting's key.
## Returns: the Color.
func get_color(key: String) -> Color:
	return Color(str(get_value(key)))

## Reads a setting as text.
##
## [param key]: the setting's key.
## Returns: the value converted with `str()`.
func get_string(key: String) -> String:
	return str(get_value(key))

## Changes a setting, tells listeners and saves it. Nothing happens if the value is the same (unless a run-only
## override was being replaced). A real change always removes any command-line override for that key.
##
## [param key]: the setting's key.
## [param value]: the new value.
## Emits [signal changed] and calls [method _save].
func set_value(key: String, value: Variant) -> void:
	var had_override := _overrides.has(key)
	_overrides.erase(key)   # a real change replaces any command-line override
	if _values.get(key) == value and not had_override:
		return
	_values[key] = value
	changed.emit(key, value)
	_save()

## Sets a value for this run only, for the command-line development flags (`--view=`, `--set=`...). It is not saved
## and no change signal is sent, so call it before the views are built.
##
## [param key]: the setting's key.
## [param value]: the value to use.
func override(key: String, value: Variant) -> void:
	_overrides[key] = value

## Puts every setting back to its default (the "Reset" in Preferences), emitting [signal changed] for each one that
## differs.
func reset_all() -> void:
	for key in DEFAULTS.keys():
		set_value(key, DEFAULTS[key])

## Writes all settings to [constant PATH]. Called by [method set_value] after every change.
func _save() -> void:
	var cfg := ConfigFile.new()
	for key in _values.keys():
		cfg.set_value(SECTION, key, _values[key])
	cfg.save(PATH)
