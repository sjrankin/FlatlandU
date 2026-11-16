extends Node3D
## A train of ten meshing gears in motion, for the back of the polar maps. The gears lie flat in the XZ plane and are
## meant to be seen from below. Each gear turns at the speed its tooth count asks for, in the opposite direction to the
## gear it meshes with, with its teeth in the gaps of its neighbour's.
##
## The animation runs only while the train is visible in the scene tree ([method _on_visibility_changed] switches the
## processing), so it costs nothing when the back is not showing.

## The gears: [tooth count, index of the gear it meshes with (-1 for the first), direction from that gear to this one in
## degrees (counter-clockwise seen from above, 0 = +X)].
const LAYOUT := [
	[22, -1, 0.0],
	[16, 0, 258.5],
	[18, 1, 189.2],
	[16, 1, 262.1],
	[22, 1, 338.6],
	[18, 4, 55.3],
	[14, 0, 183.7],
	[16, 2, 139.8],
	[26, 0, 68.8],
	[26, 6, 96.4],
]
## The module (tooth size) before the train is scaled to fit its space.
const MODULE := 1.0
## Thickness of every gear, in world units, before scaling.
const THICKNESS := 0.7
## The first gear's turning speed, in radians a second (counter-clockwise seen from above).
const SPEED := 0.35
## The rendering layer the gears are on, so only the light under the map (which uses the same layer) shines on them.
const LIGHT_LAYER := 2

## The gear scripts' mesh builder.
const GearMeshScript := preload("res://scripts/views/gear_mesh.gd")

## One entry per gear: {"node": the Node3D that turns, "teeth", "parent", "alpha" (radians)}.
var _gears: Array[Dictionary] = []
## Seconds of animation so far; the first gear's angle is this times [constant SPEED].
var _time := 0.0

## Builds the gears, laid out as [constant LAYOUT] says and scaled so the whole train fits in a circle (the round back of
## a polar map).
##
## [param radius]: the radius of the circle the train must fit in, in world units.
func build(radius: float) -> void:
	var materials := [_metal(Color("#c9a24a")), _metal(Color("#9aa3ad")), _metal(Color("#b87333"))]
	var positions: Array[Vector3] = []
	var tip_radius: Array[float] = []
	for i in LAYOUT.size():
		var entry: Array = LAYOUT[i]
		var teeth: int = entry[0]
		var parent: int = entry[1]
		var alpha := deg_to_rad(float(entry[2]))
		var pos := Vector3.ZERO
		if parent >= 0:
			var gap := MODULE * (float(LAYOUT[parent][0]) + teeth) * 0.5
			pos = positions[parent] + Vector3(cos(alpha), 0.0, -sin(alpha)) * gap
		positions.append(pos)
		tip_radius.append(MODULE * (teeth * 0.5 + 1.0))
	# The smallest circle round the train: start at the average position and nudge the center towards the gear that
	# sticks out furthest until none does.
	var middle := Vector2.ZERO
	for pos in positions:
		middle += Vector2(pos.x, pos.z) / positions.size()
	var span := 0.0
	for _step in 400:
		var worst := 0
		span = 0.0
		for i in positions.size():
			var reach := Vector2(positions[i].x, positions[i].z).distance_to(middle) + tip_radius[i]
			if reach > span:
				span = reach
				worst = i
		var toward := Vector2(positions[worst].x, positions[worst].z) - middle
		middle += toward.normalized() * 0.05
	for i in LAYOUT.size():
		var teeth: int = LAYOUT[i][0]
		var holder := Node3D.new()
		holder.position = positions[i] - Vector3(middle.x, 0.0, middle.y)
		var mi := MeshInstance3D.new()
		mi.mesh = GearMeshScript.build(teeth, MODULE, THICKNESS)
		mi.material_override = materials[i % materials.size()]
		mi.layers = LIGHT_LAYER
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
		var hub := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = MODULE * teeth * 0.12
		hm.bottom_radius = hm.top_radius
		hm.height = THICKNESS * 1.5
		hub.mesh = hm
		hub.material_override = materials[(i + 1) % materials.size()]
		hub.layers = LIGHT_LAYER
		hub.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(hub)
		add_child(holder)
		_gears.append({"node": holder, "teeth": teeth, "parent": LAYOUT[i][1], "alpha": deg_to_rad(float(LAYOUT[i][2]))})
	scale = Vector3.ONE * (radius / span)
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()

## Starts or stops the animation: it runs only while the train is visible in the scene tree.
func _on_visibility_changed() -> void:
	set_process(is_visible_in_tree())

## Turns the gears: the first at [constant SPEED], each other one so its teeth fit into its neighbour's gaps.
##
## [param delta]: seconds since the last frame.
func _process(delta: float) -> void:
	_time += delta
	var angles: Array[float] = []
	for i in _gears.size():
		var g: Dictionary = _gears[i]
		var theta: float
		if int(g["parent"]) < 0:
			theta = _time * SPEED
		else:
			var p: Dictionary = _gears[int(g["parent"])]
			var alpha: float = g["alpha"]
			var ratio := float(p["teeth"]) / float(g["teeth"])
			theta = alpha + PI + PI / float(g["teeth"]) - ratio * (angles[int(g["parent"])] - alpha)
		angles.append(theta)
		(g["node"] as Node3D).rotation.y = theta

## A shiny metal material for the gears (double-sided, because the mesh's winding is not important).
##
## [param color]: the metal's color.
## Returns: the StandardMaterial3D.
func _metal(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = 0.5
	m.roughness = 0.45
	m.emission_enabled = true          # a glow of its own, so every face is bright whichever way it is lit
	m.emission = color * 0.35
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
