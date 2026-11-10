shader_type canvas_item;

// Night overlay for the flat views. Reproduces Flatland's pre-rendered day/night masks
// analytically: mode 0 = north-centered polar, 1 = south-centered polar, 2 = rectangular.
uniform int mode = 0;
uniform float sun_declination = 0.0;   // radians
uniform float sun_longitude = 0.0;     // degrees (sub-solar longitude)
uniform float night_alpha = 0.6;

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
