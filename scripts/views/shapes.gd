class_name Shapes
extends RefCounted
## Mesh and material helpers for the city and earthquake shapes (Flatland's ShapeManager).

## Outlined block materials already made, by color and night flag, so each is built once ([method outline_material]).
static var _outline_cache: Dictionary = {}
## Plain materials already made, by color, so each is built once ([method plain]).
static var _plain_cache: Dictionary = {}

## Builds a four-sided pyramid with its base centered at the origin and its apex at +Y (used for pyramid-shaped cities
## and earthquakes).
##
## [param width]: base size along X.
## [param height]: height along Y.
## [param length]: base size along Z.
## Returns: the ArrayMesh, with generated normals.
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

## The color on the opposite side of the color wheel (hue turned by half), used for city stems.
##
## [param c]: the color.
## Returns: the complementary color, with the same saturation and value.
static func complement(c: Color) -> Color:
	return Color.from_hsv(fposmod(c.h + 0.5, 1.0), c.s, c.v)

## An opaque, lit material of one color (no day/night glow). Alpha below 1 makes it transparent. Materials are cached
## by color.
##
## [param color]: the color (with alpha).
## Returns: the StandardMaterial3D.
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

## A box whose every face shows the whole of the outline texture (Godot's BoxMesh spreads one texture over all six faces,
## so only the edges of the whole sheet would get an outline). Used with [method outline_material] for the cities that
## are boxes.
##
## [param size]: the box's size on each axis.
## Returns: the ArrayMesh, centered on the origin.
static func outlined_box(size: Vector3) -> ArrayMesh:
	var h := size * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Each face: its outward normal, then its corners counter-clockwise as seen from outside (the first is the texture's
	# top left).
	var faces := [
		[Vector3.RIGHT, [Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z)]],
		[Vector3.LEFT, [Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z)]],
		[Vector3.UP, [Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z)]],
		[Vector3.DOWN, [Vector3(-h.x, -h.y, h.z), Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z)]],
		[Vector3.BACK, [Vector3(-h.x, h.y, h.z), Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z)]],
		[Vector3.FORWARD, [Vector3(h.x, h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z)]],
	]
	var uvs := [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
	for f in faces:
		var corners: Array = f[1]
		# Godot draws clockwise triangles as front faces, so the corners go in as (0, 2, 1) and (0, 3, 2).
		for tri in [[0, 2, 1], [0, 3, 2]]:
			for i in tri:
				st.set_normal(f[0])
				st.set_uv(uvs[i])
				st.add_vertex(corners[i])
	return st.commit()

## The outlined block look for cities (Flatland's MakeOutlineCubeTexture): the color shows through the transparent
## parts of `BlockTexture2.png` and the outline is drawn over it. The night version also glows a little (never the outline, which stays black), so
## the block can be seen in the dark. Cached.
##
## [param color]: the block's color.
## [param night]: true for the glowing night version.
## Returns: the StandardMaterial3D.
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
	var tex_image := ImageTexture.create_from_image(base)
	m.albedo_texture = tex_image
	m.roughness = 1.0            # matte with no shine, so the black outline stays black instead of reflecting grey
	m.metallic_specular = 0.0
	if night:
		# The glow comes from the same picture, so the black outline stays black (a plain emission color would tint it).
		m.emission_enabled = true
		m.emission = Color.WHITE
		m.emission_texture = tex_image
		m.emission_energy_multiplier = 0.4
	_outline_cache[key] = m
	return m

## The size factor for a shape-scale setting.
##
## [param setting]: the key of a scale setting ("city_scale" or "quake_scale").
## Returns: 0.5 for "Small", 1.5 for "Large", otherwise 1.0.
static func scale_for(setting: String) -> float:
	match Settings.get_string(setting):
		"Small": return 0.5
		"Large": return 1.5
	return 1.0

## Bends flat extruded text around a sphere, so it follows the curvature of the Earth (or of the ring the welcome text
## travels on) instead of sticking out in a straight line. The sphere's center lies at local (0, 0, -radius) of the
## text. Vertices, normals and tangents are all rotated.
##
## [param tm]: the TextMesh holding the text.
## [param radius]: the sphere's radius.
## Returns: a new ArrayMesh with the bent text, or the original TextMesh if it has no geometry.
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
