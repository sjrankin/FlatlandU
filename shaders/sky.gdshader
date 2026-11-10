shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

// The sky sphere, centred on the camera. It is black except for the sun, drawn as a bright
// yellow-orange sphere in its true direction (+Z: the scene is lit from behind the default view).
uniform bool use_sun = true;
uniform float sun_radius_deg = 0.4;
uniform float sun_brightness = 2.1;

varying vec3 world_dir;

void vertex() {
	world_dir = (MODEL_MATRIX * vec4(VERTEX, 0.0)).xyz;
}

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
