// The flat map (north-centered, south-centered or rectangular) drawn by the 2D flat view, shown on a plane in
// 3D so it can be tilted and turned like the globe. It is shown exactly as drawn, except where the 3D objects
// on it (cities, earthquakes, satellites, hour labels) throw a shadow: the light is at the sun, so shadows
// point away from the sun's position.

shader_type spatial;
render_mode cull_disabled, ambient_light_disabled, specular_disabled;

// The picture of the 2D map, drawn off screen by FlatView and used as this plane's texture.
uniform sampler2D map_tex : source_color, filter_linear, repeat_disable;
// How bright a shadowed part of the map is, as a fraction (0.5 is half brightness).
uniform float shadow_floor = 0.5;

// fragment(): shows the map picture exactly as drawn (fully rough, so no highlights).
void fragment() {
	ALBEDO = texture(map_tex, UV).rgb;
	ROUGHNESS = 1.0;
}

// light(): the only lighting the map gets: full brightness in the light, [shadow_floor] where a 3D object (city,
// quake, satellite, hour label) throws a shadow. The light sits at the Sun, so shadows point away from it.
void light() {
	DIFFUSE_LIGHT += vec3(mix(shadow_floor, 1.0, ATTENUATION));
}
