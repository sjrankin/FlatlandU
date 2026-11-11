class_name BuildInfo
extends RefCounted
## Build number and build time of this copy of the app, read from res://data/build_info.json.
## That file is rewritten by the Build Number editor plugin (addons/build_number) every time the
## project is exported, so the build number counts up from 100 and the time is the export time.
## Until the first export (built_unix is 0) the build is 100 and the time is "now", so running
## from the editor still shows something sensible.

const PATH := "res://data/build_info.json"
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

static var _loaded := false
static var _build := 100
static var _unix := 0

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary:
		_build = int(parsed.get("build", 100))
		_unix = int(parsed.get("built_unix", 0))
	if _unix <= 0:
		_unix = int(Time.get_unix_time_from_system())

static func build_number() -> int:
	_load()
	return _build

## Build time as a local-time date/time dictionary.
static func _local() -> Dictionary:
	_load()
	var bias_minutes := int(Time.get_time_zone_from_system().get("bias", 0))
	return Time.get_datetime_dict_from_unix_time(_unix + bias_minutes * 60)

## Build date as DD-MMM-YYYY, for example 11-Nov-2026.
static func short_date() -> String:
	var d := _local()
	return "%02d-%s-%04d" % [d["day"], MONTHS[int(d["month"]) - 1], d["year"]]

## Build date and time, for example 11-Nov-2026 08:20:05.
static func timestamp() -> String:
	var d := _local()
	return "%s %02d:%02d:%02d" % [short_date(), d["hour"], d["minute"], d["second"]]
