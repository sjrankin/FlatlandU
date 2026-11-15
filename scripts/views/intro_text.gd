class_name IntroText
extends Node3D
## Start-up banner (as in FlatlandView): the program name, version and copyright as extruded text
## that circles the globe for three full rotations. A click anywhere fades it out over one second.

## Emitted when the banner has faded out and is about to remove itself.
signal finished

## How many full turns the banner makes round the globe.
const ROTATIONS := 3
## Seconds for one turn (slower than the original 6 s by 30%, then 15%, then another 15%).
const SECONDS_PER_ROTATION := 6.0 / (0.7 * 0.85 * 0.85)
## Fade-out time when the user dismisses the banner.
const CLICK_FADE_SECONDS := 1.0
## Fade-out time when the banner has finished its turns and goes away on its own.
const AUTO_FADE_SECONDS := 6.0
## Overall size factor for the text.
const TEXT_SCALE := 1.15
## The angle the banner travels in all: three full turns plus the quarter turn from the starting limb to face the
## viewer.
const TOTAL_TRAVEL := TAU * ROTATIONS + PI / 2.0
## Radius of the ring the text sits on, well outside the hour labels (radius 11.5).
const RING_RADIUS := 14.5

## One entry per line of text, {y, half_angle, half_height}, describing where it is on the ring, so [method occludes]
## can tell if a ray passes through it.
var _lines: Array = []
## When true the banner fades away on its own after its turns; when false (shown from the Welcome button) it stays,
## facing the viewer, until dismissed.
var auto_fade := true
## Radians travelled so far; the banner starts at the right-hand limb and moves left.
var _angle := 0.0
## True once [method dismiss] has started the fade.
var _fading := false
## The text materials (one per line), faded together by [method dismiss].
var _materials: Array[StandardMaterial3D] = []
## The materials of the shadow-only copies of the text (they dither by alpha so shadows fade with the text).
var _shadow_materials: Array[StandardMaterial3D] = []
## The node the lines are children of; it is turned to move the banner round the globe.
var _ring: Node3D

## Creates the three lines: FLATLAND (large, red), version/build/date (gold) and the copyright (cyan), with
## [method _add_line].
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

## Builds one line of extruded text bent round the ring, plus a shadows-only copy whose material dithers by alpha so
## the shadow fades with the text.
##
## [param text]: the words.
## [param color]: the text color.
## [param size]: size factor (1.0 normal).
## [param y]: height of the line on the ring.
## [param bold]: unused; every line uses the heavy font (synthetic emboldening breaks glyph outlines).
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

## Moves the banner round the globe until it reaches its final position facing the viewer, then (if
## [member auto_fade]) starts the fade.
##
## [param delta]: seconds since the last frame.
func _process(delta: float) -> void:
	if _fading:
		return
	if _angle >= TOTAL_TRAVEL:
		return   # parked, facing the viewer, until dismissed
	_angle = minf(_angle + delta * TAU / SECONDS_PER_ROTATION, TOTAL_TRAVEL)
	_ring.rotation.y = PI / 2.0 - _angle
	if _angle >= TOTAL_TRAVEL and auto_fade:
		dismiss(AUTO_FADE_SECONDS)   # now facing the viewer: fade away on its own

## Whether a ray passes through one of the lines of text. Used so mouse hover and clicks do not reach the globe
## through the text. It intersects the ray with the cylinder the text is wrapped on and tests each line's angle and
## height.
##
## [param origin]: ray start, in world space.
## [param dir]: ray direction, in world space.
## Returns: true if the ray hits text (false once the text is nearly faded).
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

## Fades the banner out (text, glow and shadow), then removes it with [method _remove]. Does nothing if already
## fading.
##
## [param seconds]: fade time (default [constant CLICK_FADE_SECONDS]).
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

## Emits [signal finished] and frees the banner.
func _remove() -> void:
	finished.emit()
	queue_free()
