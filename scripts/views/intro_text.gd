class_name IntroText
extends Node3D
## Start-up banner (as in FlatlandView): the program name, version and copyright as extruded text
## that circles the globe for three full rotations. A click anywhere fades it out over one second.

signal finished

const ROTATIONS := 3
const SECONDS_PER_ROTATION := 6.0 / (0.7 * 0.85 * 0.85)   # 30%, 15%, then another 15% slower than the original 6 s
const CLICK_FADE_SECONDS := 1.0
const AUTO_FADE_SECONDS := 6.0
const TEXT_SCALE := 1.15
## Three full turns, plus the quarter turn from the starting limb to face the viewer.
const TOTAL_TRAVEL := TAU * ROTATIONS + PI / 2.0
const RING_RADIUS := 14.5   # well outside the hour labels (radius 11.5)

var _lines: Array = []   # {y, half_angle, half_height} for each line, used by occludes()
## When false (shown from the Welcome button) the text stays, facing the viewer, until it is dismissed.
var auto_fade := true
var _angle := 0.0   # radians travelled; the banner starts at the right-hand limb and moves left
var _fading := false
var _materials: Array[StandardMaterial3D] = []
var _shadow_materials: Array[StandardMaterial3D] = []
var _ring: Node3D

func _ready() -> void:
	_ring = Node3D.new()
	add_child(_ring)
	var version := str(ProjectSettings.get_setting("application/config/version", "1.0"))
	var lines: Array = [
		["FLATLAND", Color("#e03030"), 1.5, 2.6, true],
		["Version %s, Build %d, %s" % [version, BuildInfo.build_number(), BuildInfo.short_date()], Color("#f2c000"), 1.0, 0.0, false],
		["Copyright © 2019 - 2026 Stuart Rankin", Color("#18b8d0"), 1.0, -2.6, false],
	]
	for line in lines:
		_add_line(line[0], line[1], line[2], line[3], line[4])

func _add_line(text: String, color: Color, size: float, y: float, bold: bool) -> void:
	var tm := TextMesh.new()
	tm.text = text
	# A genuinely heavy face for every line, for legibility; synthetic emboldening makes glyph
	# outlines self-intersect (a broken "N"), so a real heavy face is used instead.
	tm.font = Geo.heavy_font()
	tm.font_size = 96
	tm.pixel_size = 0.0125 * size * TEXT_SCALE
	tm.depth = 0.35 * size * TEXT_SCALE
	tm.curve_step = 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.45
	mat.emission_enabled = true
	mat.emission = color * 0.35
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	_materials.append(mat)
	var mi := MeshInstance3D.new()
	mi.mesh = Shapes.bend_text(tm, RING_RADIUS)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, y, RING_RADIUS)
	_ring.add_child(mi)
	var box := mi.mesh.get_aabb()
	_lines.append({"y": y + box.get_center().y, "half_angle": box.size.x * 0.5 / RING_RADIUS + 0.02, "half_height": box.size.y * 0.5 + 0.1})
	# The shadow comes from a separate shadows-only copy whose material dithers by alpha (alpha hash),
	# so the shadow fades out along with the text instead of staying at full strength.
	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.albedo_color = color
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	_shadow_materials.append(shadow_mat)
	var caster := MeshInstance3D.new()
	caster.mesh = mi.mesh
	caster.material_override = shadow_mat
	caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	caster.position = mi.position
	_ring.add_child(caster)

func _process(delta: float) -> void:
	if _fading:
		return
	if _angle >= TOTAL_TRAVEL:
		return   # parked, facing the viewer, until dismissed
	_angle = minf(_angle + delta * TAU / SECONDS_PER_ROTATION, TOTAL_TRAVEL)
	_ring.rotation.y = PI / 2.0 - _angle
	if _angle >= TOTAL_TRAVEL and auto_fade:
		dismiss(AUTO_FADE_SECONDS)   # now facing the viewer: fade away on its own

## True if the ray (from `origin` along `dir`, in world space) passes through one of the text lines.
func occludes(origin: Vector3, dir: Vector3) -> bool:
	if _fading and _materials[0].albedo_color.a < 0.1:
		return false
	var inv := _ring.global_transform.affine_inverse()
	var o := inv * origin
	var d := (inv.basis * dir).normalized()
	# Intersect the ray with the vertical cylinder the text is wrapped around (radius RING_RADIUS).
	var a := d.x * d.x + d.z * d.z
	if a < 1e-9:
		return false
	var b := 2.0 * (o.x * d.x + o.z * d.z)
	var c := o.x * o.x + o.z * o.z - RING_RADIUS * RING_RADIUS
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return false
	for sign_t: float in [-1.0, 1.0]:
		var t := (-b + sign_t * sqrt(disc)) / (2.0 * a)
		if t <= 0.0:
			continue
		var p := o + d * t
		var ang := atan2(p.x, p.z)
		for line in _lines:
			if absf(p.y - float(line["y"])) < float(line["half_height"]) and absf(ang) < float(line["half_angle"]):
				return true
	return false

## Fade the banner out (1 second when the user clicks), then remove it.
func dismiss(seconds: float = CLICK_FADE_SECONDS) -> void:
	if _fading:
		return
	_fading = true
	var tween := create_tween().set_parallel(true)
	for mat in _materials:
		tween.tween_property(mat, "albedo_color:a", 0.0, seconds)
		tween.tween_property(mat, "emission_energy_multiplier", 0.0, seconds)
	for mat in _shadow_materials:
		tween.tween_property(mat, "albedo_color:a", 0.0, seconds)
	tween.chain().tween_callback(_remove)

func _remove() -> void:
	finished.emit()
	queue_free()
