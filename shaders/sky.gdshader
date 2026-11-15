// The sky sphere, centred on the camera. It is black except for the sun, drawn as a bright
// yellow-orange sphere in its true direction (+Z: the scene is lit from behind the default view).

shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

// Whether to draw the Sun (the `show_sun` setting).
uniform bool use_sun = true;
// The Sun's apparent radius in degrees.
uniform float sun_radius_deg = 0.4;
// Brightness of the Sun's disk and glow.
uniform float sun_brightness = 2.1;

// The direction of this point of the sky sphere from its center, in world space (set in vertex()).
varying vec3 world_dir;

// vertex(): turns the sphere vertex into a world-space direction for [world_dir].
void vertex() {
	world_dir = (MODEL_MATRIX * vec4(VERTEX, 0.0)).xyz;
}

// fragment(): black sky, except the Sun in its true direction (+Z): a bright disk (a little more orange toward
// the rim so it looks like a sphere) with a soft glow round it.
void fragment() {
	vec3 col = vec3(0.0);
	if (use_sun) {
		vec3 d = normalize(world_dir);
		float ang = degrees(acos(clamp(d.z, -1.0, 1.0)));
		float disk = 1.0 - smoothstep(sun_radius_deg * 0.92, sun_radius_deg, ang);
		float glow = exp(-pow(max(ang - sun_radius_deg, 0.0) / (sun_radius_deg * 0.9), 1.2)) * 0.37 * sun_brightness;
		// Slightly darker, more orange toward the rim so the disk reads as a sphere.
		float rim = clamp(ang / sun_radius_deg, 0.0, 1.0);
		vec3 sun_col = mix(vec3(1.0, 0.86, 0.3), vec3(1.0, 0.5, 0.08), rim * rim);
		col = mix(sun_col * glow * (1.0 - disk), sun_col * sun_brightness, disk);
	}
	ALBEDO = col;
}
