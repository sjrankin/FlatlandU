@tool
extends EditorPlugin
## Registers the export plugin that updates the build number and build time (see build_export.gd).

var _export_plugin: EditorExportPlugin

func _enter_tree() -> void:
	_export_plugin = preload("res://addons/build_number/build_export.gd").new()
	add_export_plugin(_export_plugin)

## Called by the editor each time the project is about to be run: that is a build too, so it gets a new number and time.
func _build() -> bool:
	preload("res://addons/build_number/build_export.gd").stamp()
	return true

func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null
