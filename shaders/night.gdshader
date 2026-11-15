// Night overlay for the flat views. Reproduces Flatland's pre-rendered day/night masks
// analytically: mode 0 = north-centered polar, 1 = south-centered polar, 2 = rectangular.

shader_type canvas_item;

// Which map this shades: 0 north-centered polar, 1 south-centered polar, 2 rectangular.
uniform int mode = 0;
// The Sun's declination in radians (set by FlatView `_update_night`).
uniform float sun_declination = 0.0;
// The sub-solar longitude in degrees.
uniform float sun_longitude = 0.0;
// How dark the night side is (the shading's opacity, from the `night_darkness` setting).
uniform float night_alpha = 0.6;

// fragment(): works out, for each pixel, the latitude and longitude it shows (by the map layout in [mode]) and
// the Sun's height above the horizon there, then draws black with an opacity of [night_alpha] where the Sun is
// below the horizon (-0.833 degrees, with a soft edge). Pixels outside the circle of a polar map are clear. This
// reproduces Flatland's pre-rendered day/night masks analytically.
void fragment() {
	float lat;
	float lon_rel;
	float inside = 1.0;
	if (mode == 2) {
		lat = radians(90.0 - UV.y * 180.0);
		lon_rel = radians(UV.x * 360.0 - 180.0 - sun_longitude);
	} else {
		vec2 d = UV * 2.0 - 1.0;
		float r = length(d);
		inside = step(r, 1.0);
		float ang = degrees(atan(-d.y, d.x));
		if (mode == 0) {
			lat = radians(90.0 - r * 180.0);
			lon_rel = radians(ang - 270.0);
		} else {
			lat = radians(r * 180.0 - 90.0);
			lon_rel = radians(90.0 - ang);
		}
	}
	float alt = sin(lat) * sin(sun_declination) + cos(lat) * cos(sun_declination) * cos(lon_rel);
	float night = 1.0 - smoothstep(-0.003, 0.003, alt - sin(radians(-0.833)));
	COLOR = vec4(0.0, 0.0, 0.0, night * night_alpha * inside);
}
