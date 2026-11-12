@tool
extends EditorPlugin
## Editor plugin that adds the Android part of FlatlandNativeUI (the Kotlin plugin in
## native/FlatlandNativeUIAndroid) to Android exports. Android plugins need the Gradle build: in the Android
## export preset turn on "Use Gradle Build" (and install the Android build template once).
## The iOS and macOS parts are a GDExtension (FlatlandNativeUI.gdextension) and need nothing here.

var _export_plugin: AndroidExport

func _enter_tree() -> void:
	_export_plugin = AndroidExport.new()
	add_export_plugin(_export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null

class AndroidExport extends EditorExportPlugin:
	func _get_name() -> String:
		return "FlatlandNativeUI"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	## Paths are relative to res://addons/.
	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["FlatlandNativeUI/bin/android/FlatlandNativeUI.aar"])

	## The AAR does not carry its dependencies; Godot's Gradle build fetches these. Keep the versions in step
	## with native/FlatlandNativeUIAndroid/plugin/build.gradle.kts.
	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray([
			"androidx.activity:activity-compose:1.9.3",
			"androidx.compose.ui:ui:1.7.6",
			"androidx.compose.foundation:foundation:1.7.6",
			"androidx.compose.material3:material3:1.3.1",
			"androidx.compose.material:material-icons-extended:1.7.6",
		])
