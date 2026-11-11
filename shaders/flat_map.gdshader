// The flat map (north-centered, south-centered or rectangular) drawn by the 2D flat view, shown on a plane in
// 3D so it can be tilted and turned like the globe. It is shown exactly as drawn, except where the 3D objects
// on it (cities, earthquakes, satellites, hour labels) throw a shadow: the light is at the sun, so shadows
// point away from the sun's position.

shader_type spatial;
render_mode cull_disabled, ambient_light_disabled, specular_disabled;

uniform sampler2D map_tex : source_color, filter_linear, repeat_disable;
uniform float shadow_floor = 0.5;

void fragment() {
	ALBEDO = texture(map_tex, UV).rgb;
	ROUGHNESS = 1.0;
}

void light() {
	DIFFUSE_LIGHT += vec3(mix(shadow_floor, 1.0, ATTENUATION));
}
