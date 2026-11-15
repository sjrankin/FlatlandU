class_name SolarLunarMarker
extends RefCounted
## The shiny balls that mark the point of the Earth directly under the sun (yellow) and under the moon (bright blue), as in
## the other versions of Flatland. They are drawn on the globe, the cubic Earth and both kinds of flat map. The setting
## `show_sun_point` and `show_moon_point` turn them on and off.

const SUN_COLOR := Color(1.0, 1.0, 0.0)
const MOON_COLOR := Color(0.3, 0.7, 1.0)
## A marker's radius as a fraction of the globe's radius (and about the same fraction of a flat map's width).
const GLOBE_FRACTION := 0.0495
const MAP_FRACTION := 0.022

## A glowing, glossy ball of radius `radius` (it glows so that it can still be seen on the night side).
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

## Latitude and longitude (degrees) of the point under the sun.
static func sun_point(unix: float) -> Vector2:
	return Vector2(Solar.declination(unix), wrapf(Solar.subsolar_longitude(unix), -180.0, 180.0))

## Latitude and longitude (degrees) of the point under the moon.
static func moon_point(unix: float) -> Vector2:
	var m := Lunar.position(unix)
	return Vector2(float(m["lat"]), float(m["lon"]))

static func sun_enabled() -> bool:
	return Settings.get_bool("show_sun_point")

static func moon_enabled() -> bool:
	return Settings.get_bool("show_moon_point")
