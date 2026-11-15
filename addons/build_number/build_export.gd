@tool
extends EditorExportPlugin
## Runs at the start of every export: adds one to the build number in res://data/build_info.json,
## stamps the current time, and puts that file into the exported package.
##
## "Export All" runs one export per platform in quick succession; those count as a single build,
## so an export that starts within GROUP_SECONDS of the previous build's stamp reuses its number
## (the time is still refreshed).

## The build record file, `res://data/build_info.json`, read at run time by BuildInfo.
const PATH := "res://data/build_info.json"
## The first build number (100).
const FIRST_BUILD := 100
## Exports that start within this many seconds of the previous stamp count as the same build ("Export All" runs one
## export per platform in quick succession).
const GROUP_SECONDS := 120

## The export plugin's name, as the editor lists it.
##
## Returns: "BuildNumber".
func _get_name() -> String:
	return "BuildNumber"

## Runs at the start of every export: stamps the build and puts the file into the exported package.
##
## [param _features]: the export's feature tags (unused).
## [param _is_debug]: whether it is a debug export (unused).
## [param _path]: the output path (unused).
## [param _flags]: the export flags (unused).
func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	var text := stamp()
	add_file(PATH, text.to_utf8_buffer(), false)

## Adds one to the build number (unless this is part of the same Export All, or the project has never been built) and
## writes it with the current time to [constant PATH]. Also called by the plugin whenever the project is run from the
## editor.
##
## Returns: the file's text, which [method _export_begin] adds to the package.
static func stamp() -> String:
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
	print("Build number: ", build)
	return text
