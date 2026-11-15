class_name SolarLunarMarker
extends RefCounted
## The shiny balls that mark the point of the Earth directly under the sun (yellow) and under the moon (bright blue), as in
## the other versions of Flatland. They are drawn on the globe, the cubic Earth and both kinds of flat map. The setting
## `show_sun_point` and `show_moon_point` turn them on and off.

## Color of the ball under the sun (yellow).
const SUN_COLOR := Color(1.0, 1.0, 0.0)
## Color of the ball under the moon (bright blue).
const MOON_COLOR := Color(0.3, 0.7, 1.0)
## A ball's radius as a fraction of the globe's radius (about 5 percent).
const GLOBE_FRACTION := 0.0495
## A ball's radius as a fraction of a flat map's width (about 2.2 percent).
const MAP_FRACTION := 0.022

## Makes one glossy ball. It glows a little so it can still be seen on the night side, and casts no shadow.
##
## [param color]: [constant SUN_COLOR] or [constant MOON_COLOR].
## [param radius]: the ball's radius in scene units.
## Returns: the MeshInstance3D; the caller adds it to a scene and positions it.
static func build(color: Color, radius: float) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 32
	mesh.rings = 16
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.8
	mat.roughness = 0.2
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.5
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

## The point of the Earth directly under the Sun.
##
## [param unix]: Unix time in seconds (UTC).
## Returns: Vector2(latitude, longitude) in degrees, from [method Solar.declination] and
##   [method Solar.subsolar_longitude].
static func sun_point(unix: float) -> Vector2:
	return Vector2(Solar.declination(unix), wrapf(Solar.subsolar_longitude(unix), -180.0, 180.0))

## The point of the Earth directly under the Moon.
##
## [param unix]: Unix time in seconds (UTC).
## Returns: Vector2(latitude, longitude) in degrees, from [method Lunar.position].
static func moon_point(unix: float) -> Vector2:
	var m := Lunar.position(unix)
	return Vector2(float(m["lat"]), float(m["lon"]))

## Whether the Sun ball is switched on.
##
## Returns: the `show_sun_point` setting.
static func sun_enabled() -> bool:
	return Settings.get_bool("show_sun_point")

## Whether the Moon ball is switched on.
##
## Returns: the `show_moon_point` setting.
static func moon_enabled() -> bool:
	return Settings.get_bool("show_moon_point")
