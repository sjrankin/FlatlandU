class_name SatelliteModel
extends RefCounted
## The 3D satellite used on the globe and the flat maps: a pill-shaped body with two solar panels, and a small
## label (name and altitude) beside it. The pill lies along +X (the direction of travel), the panels along Z.

## Returns {"holder": Node3D, "label": Label3D, "km": -1, "name": String}. The caller adds `holder` to a scene.
static func build(short_name: String) -> Dictionary:
	var holder := Node3D.new()
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color("#e4e4ea")
	body_mat.metallic = 0.6
	body_mat.roughness = 0.35
	body_mat.emission_enabled = true
	body_mat.emission = Color("#40404a")
	var panel_mat := StandardMaterial3D.new()
	panel_mat.albedo_color = Color("#1d4fb5")
	panel_mat.metallic = 0.5
	panel_mat.roughness = 0.3
	panel_mat.emission_enabled = true
	panel_mat.emission = Color("#0b2766")
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.14
	capsule.height = 0.95
	body.mesh = capsule
	body.rotation.z = PI / 2.0         # the pill lies along the direction of travel (+X)
	body.material_override = body_mat
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	holder.add_child(body)
	for side in [-1.0, 1.0]:
		var panel := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.34, 0.018, 0.85)
		panel.mesh = box
		panel.position = Vector3(0.0, 0.0, 0.62 * side)
		panel.material_override = panel_mat
		panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		holder.add_child(panel)
	var label := Label3D.new()
	label.text = short_name
	label.font = Geo.label_font(700)
	label.font_size = 44
	label.pixel_size = 0.010
	label.outline_size = 12
	label.outline_modulate = Color.BLACK
	label.modulate = Color("#fff2b0")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.shaded = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.position = Vector3(0.8, 0.45, 0.0)
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(label)
	return {"holder": holder, "label": label, "km": -1, "name": short_name}
