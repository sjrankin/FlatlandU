@tool
extends EditorPlugin
## Registers the export plugin that updates the build number and build time (see build_export.gd).

## The export plugin that stamps the build number into exported packages (see build_export.gd).
var _export_plugin: EditorExportPlugin

## Creates the export plugin and registers it with the editor.
func _enter_tree() -> void:
	_export_plugin = preload("res://addons/build_number/build_export.gd").new()
	add_export_plugin(_export_plugin)

## Called by the editor each time the project is about to be run: that is a build too, so it gets a new number and
## time ([method BuildExport.stamp]).
##
## Returns: true, so the run goes ahead.
func _build() -> bool:
	preload("res://addons/build_number/build_export.gd").stamp()
	return true

## Unregisters the export plugin when the plugin is turned off or the editor closes.
func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null
