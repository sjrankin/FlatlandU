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

## Border colors for earthquake shapes: black normally, white from magnitude 7 up. (White contrasts with the orange,
## pink and red fills used from magnitude 7, which a red border would not.)
const QUAKE_BORDER := Color.BLACK
const QUAKE_BORDER_STRONG := Color.WHITE
## Magnitude from which [constant QUAKE_BORDER_STRONG] is used.
const QUAKE_BORDER_STRONG_MAGNITUDE := 7.0
## How wide the border lines along a shape's sharp edges are at most, in screen pixels.
const QUAKE_BORDER_PIXELS := 10.0

## Edge line materials already made, by color ([method quake_edge_material]).
static var _edge_cache: Dictionary = {}
## Edge meshes of magnitude texts already made, by key ([method add_text_border]).
static var _text_edge_cache: Dictionary = {}

## The border color for an earthquake of a magnitude: [constant QUAKE_BORDER], or [constant QUAKE_BORDER_STRONG] from
## magnitude 7.
##
## [param magnitude]: the quake's magnitude.
## Returns: the color.
static func quake_border_color(magnitude: float) -> Color:
	return QUAKE_BORDER_STRONG if magnitude >= QUAKE_BORDER_STRONG_MAGNITUDE else QUAKE_BORDER

## Edges whose faces meet at more than this angle (degrees) count as sharp edges of a shape and
## get a border line ([method crease_edges]).
const CREASE_ANGLE := 35.0

## Builds the sharp edges of a mesh as thin quads for the shader of [method quake_edge_material]: every edge where the
## two faces meet at more than [constant CREASE_ANGLE] degrees, and every edge with only one face. Each edge becomes four
## vertices: VERTEX is an end of the edge, NORMAL holds the other end, and UV is (side, 0) with side -1 or 1.
##
## [param mesh]: a mesh with one triangle surface.
## [param skip_bottom]: true to leave out the edges that lie in the mesh's lowest plane (a stem standing on another
##   part has no border where it meets it).
## [param cut_out]: a box (in mesh space) whose inside gets no border lines, for the part another part stands on (the
##   piece of the arrow head's edge under the stem); an AABB with no size cuts nothing.
## Returns: the ArrayMesh, or null if the mesh has no sharp edges (a sphere).
static func crease_edges(mesh: Mesh, skip_bottom: bool = false, cut_out: AABB = AABB()) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index = arrays[Mesh.ARRAY_INDEX]
	var tri_count: int = (index.size() if index != null else verts.size()) / 3
	var faces: Array[Vector3] = []
	var edges := {}      # quantized edge key -> [a, b, [face indices]]
	for t in tri_count:
		var ids: Array[int] = []
		for k in 3:
			ids.append(index[t * 3 + k] if index != null else t * 3 + k)
		var a := verts[ids[0]]
		var b := verts[ids[1]]
		var c := verts[ids[2]]
		faces.append((b - a).cross(c - a).normalized())
		for k in 3:
			var p := verts[ids[k]]
			var q := verts[ids[(k + 1) % 3]]
			var pk := Vector3i((p * 10000.0).round())
			var qk := Vector3i((q * 10000.0).round())
			if pk == qk:
				continue      # a degenerate edge (the tip of a cone)
			var key := [pk, qk] if (pk.x < qk.x or (pk.x == qk.x and (pk.y < qk.y or (pk.y == qk.y and pk.z < qk.z)))) else [qk, pk]
			var k2 := str(key)
			if not edges.has(k2):
				edges[k2] = [p, q, []]
			(edges[k2][2] as Array).append(t)
	var limit := cos(deg_to_rad(CREASE_ANGLE))
	var low := mesh.get_aabb().position.y
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var out_uv := PackedVector2Array()
	var out_i := PackedInt32Array()
	for k2 in edges:
		var e: Array = edges[k2]
		var fs: Array = e[2]
		var sharp := fs.size() == 1
		if fs.size() >= 2:
			sharp = faces[fs[0]].dot(faces[fs[1]]) < limit
		if not sharp:
			continue
		if skip_bottom and absf((e[0] as Vector3).y - low) < 0.0001 and absf((e[1] as Vector3).y - low) < 0.0001:
			continue
		for seg in _outside_box(e[0], e[1], cut_out):
			var base := out_v.size()
			var ends: Array[Vector3] = [seg[0], seg[1]]
			for end in 2:
				for side in [-1.0, 1.0]:
					out_v.append(ends[end])
					out_n.append(ends[1 - end])
					out_uv.append(Vector2(side, 0.0))
			out_i.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))
	if out_v.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = out_v
	arr[Mesh.ARRAY_NORMAL] = out_n
	arr[Mesh.ARRAY_TEX_UV] = out_uv
	arr[Mesh.ARRAY_INDEX] = out_i
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return result

## The parts of a line segment that lie outside a box.
##
## [param a]: one end of the segment.
## [param b]: the other end.
## [param box]: the box; with no volume nothing is cut.
## Returns: an array of [start, end] pairs: the whole segment, none, or one or two pieces.
static func _outside_box(a: Vector3, b: Vector3, box: AABB) -> Array:
	if not box.has_volume():
		return [[a, b]]
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	var lo := box.position
	var hi := box.end
	for axis in 3:
		if absf(d[axis]) < 0.000001:
			if a[axis] < lo[axis] or a[axis] > hi[axis]:
				return [[a, b]]      # parallel to this slab and outside it: never inside the box
		else:
			var u := (lo[axis] - a[axis]) / d[axis]
			var v := (hi[axis] - a[axis]) / d[axis]
			t0 = maxf(t0, minf(u, v))
			t1 = minf(t1, maxf(u, v))
	if t0 >= t1:
		return [[a, b]]
	var pieces := []
	if t0 > 0.001:
		pieces.append([a, a + d * t0])
	if t1 < 0.999:
		pieces.append([a + d * t1, b])
	return pieces

## The material for the border lines along a shape's sharp edges (see [method crease_edges]): each edge is a line of
## fixed width on the screen, nudged toward the camera by a small fraction of the shape's size so it shows on the shape's
## surface but is hidden behind the shape where the edge is on the far side. Cached by color.
##
## [param magnitude]: the quake's magnitude, which picks the color.
## Returns: the ShaderMaterial.
static func quake_edge_material(magnitude: float) -> ShaderMaterial:
	var color := quake_border_color(magnitude)
	var key := color.to_html()
	if _edge_cache.has(key):
		return _edge_cache[key]
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, skip_vertex_transform;
uniform vec4 border_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float width_px = 3.0;
instance uniform float shape_radius = 1.0;
// Below this apparent size (in pixels) of the shape's bounding sphere no lines are drawn; set per instance.
instance uniform float hide_below_px = 0.0;
void vertex() {
	vec3 p = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 q = (MODELVIEW_MATRIX * vec4(NORMAL, 1.0)).xyz;
	vec2 scale = abs(vec2(PROJECTION_MATRIX[0][0], PROJECTION_MATRIX[1][1]));
	float scl = length(MODELVIEW_MATRIX[0].xyz);
	float depth = max(-(MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).z, 0.01);
	float shape_px = shape_radius * scl / depth * scale.y * VIEWPORT_SIZE.y * 0.5;
	// Lines thinner than about a pixel would flicker and look jagged, so they are kept at 1.2 px; and for small text, whose
	// strokes are no wider than the line would be, there are no lines at all (hide_below_px).
	float w = max(min(width_px, shape_px * 0.12) * 0.8, 1.2);
	if (shape_px < hide_below_px) {
		w = 0.0;
	}
	// Where the two ends are on the screen, in pixels.
	vec2 sp = p.xy / max(-p.z, 0.01) * scale * VIEWPORT_SIZE * 0.5;
	vec2 sq = q.xy / max(-q.z, 0.01) * scale * VIEWPORT_SIZE * 0.5;
	vec2 dir = sq - sp;
	dir = length(dir) > 0.0001 ? normalize(dir) : vec2(1.0, 0.0);
	// Half a width to either side of the edge (and no further than its ends).
	vec2 off_px = vec2(-dir.y, dir.x) * UV.x * w * 0.5;
	vec2 off_ndc = off_px * 2.0 / VIEWPORT_SIZE;
	p.xy += off_ndc * (-p.z) / scale;
	// Nudge the line toward the camera so that the faces beside the edge do not hide it: by a fraction of the shape's
	// size, and by more where a width of line covers a lot of depth (faces seen at a slant).
	float w_world = w * max(-p.z, 0.01) / (scale.y * VIEWPORT_SIZE.y * 0.5);
	p.z += min(max(shape_radius * scl * 0.03, w_world * 3.5), shape_radius * scl * 0.12);
	VERTEX = p;
}
void fragment() {
	ALBEDO = border_color.rgb;
}
"""
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("border_color", color)
	m.set_shader_parameter("width_px", QUAKE_BORDER_PIXELS)
	_edge_cache[key] = m
	return m

## Gives one part of an earthquake shape its border (only if the `quake_outlines` setting is on): lines along the sharp edges of its mesh (see [method crease_edges]),
## as a child of the mesh instance so they follow its transform, animation and scale. Smooth shapes (a sphere) have no
## sharp edges and get none.
##
## [param mi]: the mesh instance (with its mesh set).
## [param magnitude]: the quake's magnitude, which picks the border color.
## [param stands_on_part]: true for a part that stands on another part of the shape (an arrow's stem), which gets no
##   border along its base.
## [param cut_out]: for a part that another part stands on, the box in this mesh's space where the other part stands
##   (see [method crease_edges]).
static func add_quake_border(mi: MeshInstance3D, magnitude: float, stands_on_part: bool = false, cut_out: AABB = AABB()) -> void:
	if not Settings.get_bool("quake_outlines"):
		return
	var edge_mesh := crease_edges(mi.mesh, stands_on_part, cut_out)
	if edge_mesh == null:
		return
	var lines := MeshInstance3D.new()
	lines.mesh = edge_mesh
	lines.material_override = quake_edge_material(magnitude)
	lines.set_instance_shader_parameter("shape_radius", mi.mesh.get_aabb().size.length() * 0.5)
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_child(lines)

## Below this on-screen size (pixels, about 0.6 of the height of the letters) magnitude text has no border lines: from far
## away they would be thinner than a pixel and look jagged.
const TEXT_BORDER_MIN_PX := 24.0

## Border lines for earthquake magnitude text (only if the `quake_outlines` setting is on): the sharp edges of the extruded letters (their outlines), made like those of a
## shape ([method add_quake_border]). The line width follows the height of the letters, so it stays in proportion to
## their strokes. Edge meshes are cached by `key`, because the same text (same magnitude) is built many times.
##
## [param mi]: the text's mesh instance (with its mesh set).
## [param magnitude]: the quake's magnitude, which picks the border color.
## [param height]: the height of the letters, in the mesh's units.
## [param key]: identifies the text mesh: the same key must mean the same geometry.
static func add_text_border(mi: MeshInstance3D, magnitude: float, height: float, key: String) -> void:
	if not Settings.get_bool("quake_outlines"):
		return
	if not _text_edge_cache.has(key):
		_text_edge_cache[key] = crease_edges(mi.mesh)
	var edge_mesh: ArrayMesh = _text_edge_cache[key]
	if edge_mesh == null:
		return
	var lines := MeshInstance3D.new()
	lines.mesh = edge_mesh
	lines.material_override = quake_edge_material(magnitude)
	lines.set_instance_shader_parameter("shape_radius", height * 0.6)
	lines.set_instance_shader_parameter("hide_below_px", TEXT_BORDER_MIN_PX)
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_child(lines)

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
