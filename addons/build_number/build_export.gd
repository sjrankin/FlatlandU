@tool
extends EditorExportPlugin
## Runs at the start of every export: adds one to the build number in res://data/build_info.json,
## stamps the current time, and puts that file into the exported package.
##
## "Export All" runs one export per platform in quick succession; those count as a single build,
## so an export that starts within GROUP_SECONDS of the previous build's stamp reuses its number
## (the time is still refreshed).

const PATH := "res://data/build_info.json"
const FIRST_BUILD := 100
const GROUP_SECONDS := 120

func _get_name() -> String:
	return "BuildNumber"

func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	var build := FIRST_BUILD
	var last_unix := 0
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary:
		build = int(parsed.get("build", FIRST_BUILD))
		last_unix = int(parsed.get("built_unix", 0))
	var now := int(Time.get_unix_time_from_system())
	# built_unix 0 means the project has never been built: that first build is number 100 itself.
	if last_unix > 0 and now - last_unix > GROUP_SECONDS:
		build += 1
	var text := JSON.stringify({"build": build, "built_unix": now})
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(text + "\n")
		f.close()
	add_file(PATH, text.to_utf8_buffer(), false)
	print("Build number: ", build)
