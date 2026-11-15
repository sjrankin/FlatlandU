class_name BuildInfo
extends RefCounted
## Build number and build time of this copy of the app, read from res://data/build_info.json.
## That file is rewritten by the Build Number editor plugin (addons/build_number) every time the
## project is exported, so the build number counts up from 100 and the time is the export time.
## Until the first export (built_unix is 0) the build is 100 and the time is "now", so running
## from the editor still shows something sensible.

## The build record file, rewritten at every export (and editor run) by the Build Number plugin:
## `addons/build_number/build_export.gd`.
const PATH := "res://data/build_info.json"
## English month abbreviations, indexed by month number minus one, for [method short_date].
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

## True once [method _load] has read the file, so it is read only once.
static var _loaded := false
## The build number (counts up from 100 with each build), filled in by [method _load].
static var _build := 100
## When this build was made, as Unix time (UTC). If the file has no time, the time the app started.
static var _unix := 0

## Reads [constant PATH] the first time it is called and stores the build number and time in [member _build] and
## [member _unix]; later calls do nothing. If the file is missing or has no time yet, the build is 100 and the time is
## "now", so running from the editor still shows something sensible.
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

## The build number shown in About and the welcome text.
##
## Returns: the build number (100 or more).
static func build_number() -> int:
	_load()
	return _build

## The build time converted to this computer's local time zone.
##
## Returns: a Dictionary as made by `Time.get_datetime_dict_from_unix_time` (year, month, day, hour, minute, second).
##   Used by [method short_date] and [method timestamp].
static func _local() -> Dictionary:
	_load()
	var bias_minutes := int(Time.get_time_zone_from_system().get("bias", 0))
	return Time.get_datetime_dict_from_unix_time(_unix + bias_minutes * 60)

## The build date for display, for example "11-Nov-2026".
##
## Returns: the text, "DD-MMM-YYYY" in local time.
static func short_date() -> String:
	var d := _local()
	return "%02d-%s-%04d" % [d["day"], MONTHS[int(d["month"]) - 1], d["year"]]

## The build date and time for display, for example "11-Nov-2026 08:20:05".
##
## Returns: the text, in local time. See [method short_date].
static func timestamp() -> String:
	var d := _local()
	return "%s %02d:%02d:%02d" % [short_date(), d["hour"], d["minute"], d["second"]]
