shader_type spatial;

// The demo's surfaces under the weather: a colour with a little variation, and
// weather_surface.gdshaderinc's snow and wet on top

#include "res://addons/gnd_weather/weather_surface.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.4, 0.38, 0.34);
uniform float variation : hint_range(0.0, 1.0) = 0.2;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.85;
// the snow heaped up on it: for a dense mesh only (the ground); a box's top face, raised alone, would
// part from its sides
uniform bool snow_heaps = false;
// how much of the rain stands on it (a paving 1, a gravel none): in its hollows, the puddles
uniform float puddling : hint_range(0.0, 1.0) = 0.5;
// the ground sunk in its hollows so the puddles lie in its dips (m, on a dense mesh only), and a
// basin under a pond: its centre and radii on the ground (x, z), how deep - none at 0
uniform float hollow_depth = 0.0;
uniform vec2 basin_centre = vec2(0.0);
uniform vec2 basin_radii = vec2(0.0);
uniform float basin_depth = 0.0;

// where it is in the world, for the weather (not INV_VIEW_MATRIX * VERTEX in fragment(), which a
// double precision build gets kilometres wrong far from the world's origin)
varying vec3 weather_position;

// how far the ground is sunk at a point (m): in its hollows, and in the basin
float ground_sink(vec2 world_xz) {
	float sink = hollow_depth * (gnd_weather_hollows(world_xz) - 0.5);
	if (basin_radii.x > 0.0 && basin_radii.y > 0.0) {
		// its shore wandering in and out, not an ellipse's
		vec2 off = world_xz - basin_centre;
		float r = length(off / basin_radii) * mix(0.8, 1.2, gnd_weather_noise(world_xz * 0.7 + 3.1));
		sink += basin_depth * (1.0 - smoothstep(0.35, 0.9, r));
	}
	return sink;
}

// the ground sunk in its hollows and the basin, and the snow heaped up on what faces up (on a dense
// mesh: the ground)
void vertex() {
	vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	if (hollow_depth > 0.0 || basin_depth > 0.0) {
		float e = 0.2;
		float sink = ground_sink(world_position.xz);
		vec3 sunk_normal = normalize(vec3(
			(ground_sink(world_position.xz + vec2(e, 0.0)) - ground_sink(world_position.xz - vec2(e, 0.0))) / (2.0 * e), 1.0,
			(ground_sink(world_position.xz + vec2(0.0, e)) - ground_sink(world_position.xz - vec2(0.0, e))) / (2.0 * e)));
		VERTEX += inverse(mat3(MODEL_MATRIX)) * vec3(0.0, -sink, 0.0);
		NORMAL = normalize(inverse(mat3(MODEL_MATRIX)) * sunk_normal);
		world_position.y -= sink;
		world_normal = sunk_normal;
	}
	if (snow_heaps) {
		VERTEX += inverse(mat3(MODEL_MATRIX)) * vec3(0.0, gnd_weather_snow_depth(world_normal, world_position), 0.0);
	}
	weather_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 world_position = weather_position;
	vec3 albedo = base_color * (1.0 - variation * 0.5 + variation * gnd_weather_noise(world_position.xz * 1.7));
	float roughness = roughness_value;
	// the snow and the wet, their faces in the light (the heaps' slopes too)
	vec3 weather_normal = mat3(INV_VIEW_MATRIX) * NORMAL;
	gnd_weather_apply(albedo, roughness, weather_normal, world_position, puddling);
	NORMAL = normalize(mat3(VIEW_MATRIX) * weather_normal);
	ALBEDO = albedo;
	ROUGHNESS = roughness;
}
