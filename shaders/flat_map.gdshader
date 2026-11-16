// The flat map (north-centered, south-centered or rectangular) drawn by the 2D flat view, shown on a plane in
// 3D so it can be tilted and turned like the globe. It is shown exactly as drawn, except where the 3D objects
// on it (cities, earthquakes, satellites, hour labels) throw a shadow: the light is at the sun, so shadows
// point away from the sun's position.

shader_type spatial;
render_mode cull_disabled, ambient_light_disabled, specular_disabled;

// The picture of the 2D map, drawn off screen by FlatView and used as this plane's texture.
uniform sampler2D map_tex : source_color, filter_linear, repeat_disable;
// True for the polar maps: their reverse is a dark plate (with gears on it, drawn by the stage). False for the
// rectangular map, whose reverse is the picture itself seen from behind, a mirror image.
uniform bool plate_back = true;
// The radius of the round plate on the reverse of a polar map, as a fraction of the picture's width.
uniform float plate_radius = 0.39;
// How bright a shadowed part of the map is, as a fraction (0.5 is half brightness).
uniform float shadow_floor = 0.5;

// fragment(): shows the map picture exactly as drawn (fully rough, so no highlights); the reverse of a polar map is a round plate.
void fragment() {
	ALBEDO = texture(map_tex, UV).rgb;
	if (plate_back && !FRONT_FACING) {
		// The reverse of a polar map is round, like the map: a dark metal disc with a slightly lighter rim.
		float r = length(UV - vec2(0.5));
		if (r > plate_radius) {
			discard;
		}
		ALBEDO = mix(vec3(0.07, 0.075, 0.09), vec3(0.22, 0.23, 0.27), smoothstep(plate_radius - 0.012, plate_radius - 0.002, r));
	}
	ROUGHNESS = 1.0;
}

// light(): the only lighting the map gets: full brightness in the light, [shadow_floor] where a 3D object (city,
// quake, satellite, hour label) throws a shadow. The light sits at the Sun, so shadows point away from it.
void light() {
	DIFFUSE_LIGHT += vec3(mix(shadow_floor, 1.0, ATTENUATION));
}
