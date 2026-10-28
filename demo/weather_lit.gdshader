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
// how much of the rain would stand on it (a paving 1, a gravel none), for a weather that draws it
uniform float puddling : hint_range(0.0, 1.0) = 0.5;

// where it is in the world, for the weather (not INV_VIEW_MATRIX * VERTEX in fragment(), which a
// double precision build gets kilometres wrong far from the world's origin)
varying vec3 weather_position;

// the snow heaped up on what faces up (on a dense mesh: the ground)
void vertex() {
	vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
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
