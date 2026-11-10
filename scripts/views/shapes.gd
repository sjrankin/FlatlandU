class_name Shapes
extends RefCounted
## Mesh and material helpers for the city and earthquake shapes (Flatland's ShapeManager).

static var _outline_cache: Dictionary = {}
static var _plain_cache: Dictionary = {}

## Four-sided pyramid with its base centered at the origin and its apex at +Y.
static func pyramid_mesh(width: float, height: float, length: float) -> ArrayMesh:
	var hw := width * 0.5
	var hl := length * 0.5
	var a := Vector3(-hw, 0, -hl)
	var b := Vector3(hw, 0, -hl)
	var c := Vector3(hw, 0, hl)
	var d := Vector3(-hw, 0, hl)
	var apex := Vector3(0, height, 0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tri in [[a, c, b], [a, d, c], [a, b, apex], [b, c, apex], [c, d, apex], [d, a, apex]]:
		for v in tri:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()

## Complementary hue, used for city stems.
static func complement(c: Color) -> Color:
	return Color.from_hsv(fposmod(c.h + 0.5, 1.0), c.s, c.v)

## Opaque lit material (no day/night glow), cached by color and alpha.
static func plain(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _plain_cache.has(key):
		return _plain_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.4
	m.metallic_specular = 0.6
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_plain_cache[key] = m
	return m

## The outlined block texture tinted with a color (Flatland's MakeOutlineCubeTexture): the color shows
## through the transparent parts of BlockTexture2 and the outline is drawn over it.
static func outline_material(color: Color, night: bool = false) -> StandardMaterial3D:
	var key := "%s|%s" % [color.to_html(), night]
	if _outline_cache.has(key):
		return _outline_cache[key]
	var tex: Texture2D = load("res://Assets/Textures/BlockTexture2.png")
	var src := tex.get_image()
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	var base := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	base.fill(color)
	base.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), Vector2i.ZERO)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(base)
	m.roughness = 0.5
	m.metallic_specular = 0.6
	if night:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 0.4
	_outline_cache[key] = m
	return m

static func scale_for(setting: String) -> float:
	match Settings.get_string(setting):
		"Small": return 0.5
		"Large": return 1.5
	return 1.0

## Bend flat extruded text around a sphere of `radius` whose center lies at local (0, 0, -radius), so
## the text follows the curvature of the Earth instead of sticking out in a straight line.
static func bend_text(tm: TextMesh, radius: float) -> Mesh:
	var arrays := tm.get_mesh_arrays()
	if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
		return tm
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return tm
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tans: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	for i in range(verts.size()):
		var v := verts[i]
		var th := v.x / radius
		var st := sin(th)
		var ct := cos(th)
		var rr := radius + v.z
		verts[i] = Vector3(st * rr, v.y, ct * rr - radius)
		if i < norms.size():
			var n := norms[i]
			norms[i] = Vector3(n.x * ct + n.z * st, n.y, -n.x * st + n.z * ct)
		if tans.size() >= (i + 1) * 4:
			var tx := tans[i * 4]
			var tz := tans[i * 4 + 2]
			tans[i * 4] = tx * ct + tz * st
			tans[i * 4 + 2] = -tx * st + tz * ct
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	if tans.size() > 0:
		arrays[Mesh.ARRAY_TANGENT] = tans
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out
