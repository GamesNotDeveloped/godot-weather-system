shader_type spatial;

// The demo's trees: weather_lit's look, bent by the weather's wind where each part of them stands -
// its gusts sweeping through the wood and its eddies - the more the higher above the ground

#define GND_WIND_GLOBALS
#include "res://addons/gnd_weather/weather_wind.gdshaderinc"
#include "res://addons/gnd_weather/weather_surface.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.14, 0.26, 0.11);
uniform float variation : hint_range(0.0, 1.0) = 0.4;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;
// how far a metre a second of wind bends the tree a metre above the ground
uniform float bend = 0.012;

// where it is in the world, for the weather (weather_lit.gdshader)
varying vec3 weather_position;

void vertex() {
	vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wind = gnd_wind_at(world_position);
	float height = max(world_position.y, 0.0);
	// leaning with the wind, and shivering in it
	float shiver = sin(TIME * 3.1 + world_position.x * 1.7 + world_position.z * 1.3) * 0.15;
	vec3 lean = wind * bend * height * height * 0.25 * (1.0 + shiver) * max(gnd_wind_strength, 0.0) * 0.25;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * lean;
	weather_position = world_position + lean;
}

void fragment() {
	vec3 world_position = weather_position;
	vec3 world_normal = mat3(INV_VIEW_MATRIX) * NORMAL;
	vec3 albedo = base_color * (1.0 - variation * 0.5 + variation * gnd_weather_noise(world_position.xz * 1.7));
	float roughness = roughness_value;
	gnd_weather_surface(albedo, roughness, world_normal, world_position);
	ALBEDO = albedo;
	ROUGHNESS = roughness;
}
