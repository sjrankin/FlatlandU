@tool
extends EditorPlugin
## Registers the export plugin that updates the build number and build time (see build_export.gd).

var _export_plugin: EditorExportPlugin

func _enter_tree() -> void:
	_export_plugin = preload("res://addons/build_number/build_export.gd").new()
	add_export_plugin(_export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null
