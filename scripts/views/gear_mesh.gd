extends RefCounted
## Builds the 3D mesh of one spur gear: a flat toothed wheel, lying in the XZ plane, centered on the origin, with its
## thickness along Y. Used by [GearTrain] for the back of the polar maps.
##
## Tooth sizes follow the usual gear proportions from the module (the pitch diameter divided by the tooth count), so
## gears of the same module mesh with one another.

## Builds a gear.
##
## [param teeth]: the number of teeth (at least 6).
## [param module]: the gear's module, in world units; the pitch radius is module * teeth / 2.
## [param thickness]: the gear's thickness along Y, in world units.
## Returns: the ArrayMesh (one surface, flat-shaded; draw it with a double-sided material).
static func build(teeth: int, module: float, thickness: float) -> ArrayMesh:
	var pitch_r := module * teeth * 0.5
	var tip_r := pitch_r + module
	var root_r := pitch_r - 1.25 * module
	var step := TAU / teeth
	# The outline, counter-clockwise seen from above: each tooth is a trapezoid on the root circle.
	var outline: Array[Vector2] = []
	for i in teeth:
		var a := i * step
		outline.append(_polar(root_r, a - 0.33 * step))
		outline.append(_polar(tip_r, a - 0.17 * step))
		outline.append(_polar(tip_r, a + 0.17 * step))
		outline.append(_polar(root_r, a + 0.33 * step))
	var half := thickness * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := outline.size()
	for k in n:
		var p := outline[k]
		var q := outline[(k + 1) % n]
		var top_p := Vector3(p.x, half, p.y)
		var top_q := Vector3(q.x, half, q.y)
		var bot_p := Vector3(p.x, -half, p.y)
		var bot_q := Vector3(q.x, -half, q.y)
		# Top face: a fan from the center (the outline is star-shaped round it).
		_tri(st, Vector3(0.0, half, 0.0), top_q, top_p)
		# Bottom face.
		_tri(st, Vector3(0.0, -half, 0.0), bot_p, bot_q)
		# Side wall.
		_tri(st, top_p, top_q, bot_q)
		_tri(st, top_p, bot_q, bot_p)
	st.generate_normals()
	return st.commit()

## The 2D point at a distance and angle, in the gear's XZ plane (angles count counter-clockwise seen from above, so a
## gear rotated by an angle about Y turns by that angle).
##
## [param r]: distance from the center.
## [param a]: angle in radians.
## Returns: Vector2(x, z).
static func _polar(r: float, a: float) -> Vector2:
	return Vector2(r * cos(a), -r * sin(a))

## Adds one triangle.
##
## [param st]: the SurfaceTool.
## [param a]: first corner.
## [param b]: second corner.
## [param c]: third corner.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
