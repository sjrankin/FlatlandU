@tool
extends EditorPlugin
## Editor plugin that adds the Android part of FlatlandNativeUI (the Kotlin plugin in
## native/FlatlandNativeUIAndroid) to Android exports. Android plugins need the Gradle build: in the Android
## export preset turn on "Use Gradle Build" (and install the Android build template once).
## The iOS and macOS parts are a GDExtension (FlatlandNativeUI.gdextension) and need nothing here.

## The export plugin object that adds the Android library to Android exports.
var _export_plugin: AndroidExport

## Creates and registers the Android export plugin ([class AndroidExport]).
func _enter_tree() -> void:
	_export_plugin = AndroidExport.new()
	add_export_plugin(_export_plugin)

## Unregisters the export plugin.
func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null

## The export plugin: for Android exports only it adds the FlatlandNativeUI library and its dependencies to the Gradle
## build.
class AndroidExport extends EditorExportPlugin:
	## The export plugin's name, as the editor lists it.
	##
	## Returns: "FlatlandNativeUI".
	func _get_name() -> String:
		return "FlatlandNativeUI"

	## Limits this plugin to Android exports.
	##
	## [param platform]: the export platform.
	## Returns: true only for Android.
	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	## The Android library to include. Paths are relative to res://addons/.
	##
	## [param _platform]: the platform (unused).
	## [param _debug]: whether it is a debug export (unused).
	## Returns: the path of the AAR built from native/FlatlandNativeUIAndroid.
	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["FlatlandNativeUI/bin/android/FlatlandNativeUI.aar"])

	## The libraries the AAR needs. The AAR does not carry its dependencies, so Godot's Gradle build fetches these. Keep
	## the versions in step with native/FlatlandNativeUIAndroid/plugin/build.gradle.kts.
	##
	## [param _platform]: the platform (unused).
	## [param _debug]: whether it is a debug export (unused).
	## Returns: Gradle dependency strings.
	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray([
			"androidx.activity:activity-compose:1.9.3",
			"androidx.compose.ui:ui:1.7.6",
			"androidx.compose.foundation:foundation:1.7.6",
			"androidx.compose.material3:material3:1.3.1",
			"androidx.compose.material:material-icons-extended:1.7.6",
		])
