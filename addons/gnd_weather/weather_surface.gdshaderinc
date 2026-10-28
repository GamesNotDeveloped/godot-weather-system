// The weather on a material's surface: snow lying on what faces up, and the wet darkening and
// smoothing everything. For spatial shaders of the scene's own materials (terrain, buildings,
// vehicles), which the weather does not touch by itself:
//
//   #include "res://addons/gnd_weather/weather_surface.gdshaderinc"
//   varying vec3 world_position;
//   void vertex() {
//       // not INV_VIEW_MATRIX * VERTEX in fragment(): a double precision build keeps the view's
//       // origin there its own way, kilometres off far from the world's origin
//       world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
//   }
//   void fragment() {
//       vec3 albedo = ...;
//       float roughness = ...;
//       vec3 world_normal = mat3(INV_VIEW_MATRIX) * NORMAL;
//       gnd_weather_surface(albedo, roughness, world_normal, world_position);
//       ALBEDO = albedo;
//       ROUGHNESS = roughness;
//   }
//
// The globals are WeatherServer's, set by the WeatherNode (the plugin registers them).

global uniform float gnd_wetness;
global uniform float gnd_air_temperature;
// how deep the snow lies on the average, in metres
global uniform float gnd_snow_depth;
// how wet the lying snow is (0 - 1): soaked by a rain or a thaw, grey slush
global uniform float gnd_snow_wetness;

// the depth at which the snow covers the ground (WeatherServer.SNOW_COVER_DEPTH)
const float GND_SNOW_COVER_DEPTH = 0.03;

const vec3 GND_SNOW_ALBEDO = vec3(0.86, 0.88, 0.92);
const vec3 GND_SLUSH_ALBEDO = vec3(0.5, 0.53, 0.55);

float gnd_weather_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// value noise, 0 - 1
float gnd_weather_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(gnd_weather_hash(i), gnd_weather_hash(i + vec2(1.0, 0.0)), u.x),
		mix(gnd_weather_hash(i + vec2(0.0, 1.0)), gnd_weather_hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

// How much deeper than the average the snow lies at a point of the ground (0 - 2 or so): in heaps a
// metre or two across
float gnd_weather_snow_heaping(vec2 p) {
	float heaps = gnd_weather_noise(p * 0.8) * 0.6 + gnd_weather_noise(p * 2.1 + 5.3) * 0.4;
	return mix(0.65, 1.35, heaps) * mix(0.75, 1.25, gnd_weather_noise(p * 0.11 + 11.7));
}

// How much of a surface facing up as much the snow of `cover` (0 - 1) covers: the first snow dusts
// everything evenly, the ground showing through, and lies thicker in patches that grow and run
// together into a full cover - thin, it was a few white blots on bare ground
float gnd_weather_snow_patches(vec2 world_xz, float cover) {
	// three octaves, turned against each other so the value noise's grid does not show
	vec2 p = world_xz * 0.45;
	float patches = gnd_weather_noise(p) * 0.55;
	p = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 2.03 + 17.1;
	patches += gnd_weather_noise(p) * 0.3;
	p = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 2.01 + 3.7;
	patches += gnd_weather_noise(p) * 0.15;
	float dusting = smoothstep(0.0, 0.35, cover) * mix(0.45, 0.65, patches);
	float lying = smoothstep(1.0 - cover * 1.4, 1.0 - cover * 1.4 + 0.35, patches);
	return max(dusting, lying);
}

// How much snow lies on a surface (0 - 1): on what faces up, in patches while the cover is thin
float gnd_weather_snow(vec3 world_normal, vec3 world_position) {
	if (gnd_snow_depth <= 0.0001) {
		return 0.0;
	}
	float facing_up = smoothstep(0.25, 0.75, normalize(world_normal).y);
	if (facing_up <= 0.0) {
		return 0.0;
	}
	float cover = clamp(gnd_snow_depth * gnd_weather_snow_heaping(world_position.xz) / GND_SNOW_COVER_DEPTH, 0.0, 1.0);
	if (cover <= 0.001) {
		return 0.0;
	}
	return facing_up * gnd_weather_snow_patches(world_position.xz, cover);
}

// The deepest a surface is raised by the snow, in metres, however deep it lies (#define it before
// including this to change it): a deeper snow would bury what the scene does not bury - a kerb,
// a step's edge
#ifndef GND_SNOW_MAX_DEPTH
#define GND_SNOW_MAX_DEPTH 1.0
#endif

// How deep the snow lies at a point of a surface facing up, in metres: as deep as it lies on the
// average, heaped up here. For vertex(), to raise the surface by:
//   vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
//   vec3 world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
//   float depth = gnd_weather_snow_depth(world_normal, world_position);
//   VERTEX += inverse(mat3(MODEL_MATRIX)) * vec3(0.0, depth, 0.0);
// It moves vertices, so it shows on a dense mesh (a terrain) and not on a box of eight corners.
float gnd_weather_snow_depth(vec3 world_normal, vec3 world_position) {
	if (gnd_snow_depth <= 0.0001) {
		return 0.0;
	}
	float facing_up = smoothstep(0.5, 0.9, normalize(world_normal).y);
	float depth = gnd_snow_depth * gnd_weather_snow_heaping(world_position.xz);
	return facing_up * min(depth, GND_SNOW_MAX_DEPTH);
}

// The surface's normal turned by the heaps the snow lies in (world space), where there is snow
vec3 gnd_weather_snow_normal(vec3 world_normal, vec3 world_position) {
	float e = 0.15;
	float here = gnd_weather_snow_depth(world_normal, world_position);
	if (here <= 0.0001) {
		return world_normal;
	}
	float dx = gnd_weather_snow_depth(world_normal, world_position + vec3(e, 0.0, 0.0)) - here;
	float dz = gnd_weather_snow_depth(world_normal, world_position + vec3(0.0, 0.0, e)) - here;
	return normalize(world_normal - vec3(dx, 0.0, dz) / e);
}

// The weather on a surface: the wet and the snow on it. puddling - how much water the surface would
// hold standing (a paving 1, a soil 0.3, a gravel 0), for a weather that draws it
void gnd_weather_surface_puddled(inout vec3 surface_albedo, inout float surface_roughness, vec3 world_normal, vec3 world_position, float puddling) {
	// wet: darker (the water fills the pores) and glossier
	float wet = clamp(gnd_wetness, 0.0, 1.0);
	surface_albedo *= mix(1.0, 0.62, wet);
	surface_roughness = mix(surface_roughness, min(surface_roughness, 0.18), wet * 0.85);
	// soaked, it greys to a glistening slush
	float snow = gnd_weather_snow(world_normal, world_position);
	float slush = clamp(gnd_snow_wetness * 0.8, 0.0, 1.0);
	surface_albedo = mix(surface_albedo, mix(GND_SNOW_ALBEDO, GND_SLUSH_ALBEDO, slush), snow);
	surface_roughness = mix(surface_roughness, mix(0.75, 0.3, slush), snow);
}

// Everything the weather does to a surface, each part worked out once and only where it is - for a
// material taking its colour, roughness and normal from it (fragment() only): the wet, the snow
// lying with its heaps in the light as near as a pixel is small enough to show them. world_normal -
// the surface's own (world space) in, the weather's out; returns how far the snow covers the surface,
// for its own bumps (its normal map) to go under it. puddling - as for
// gnd_weather_surface_puddled(). snow_share - how much of the snow on the open ground lies on
// the surface: 0 none (a road cleared of it), 1 as much, more where it was heaped up (the banks a
// plough leaves); the wet is the open ground's
float gnd_weather_apply_snow_share(inout vec3 surface_albedo, inout float surface_roughness, inout vec3 world_normal,
		vec3 world_position, float puddling, float snow_share) {
	vec3 normal = normalize(world_normal);
	// before any branch: the derivatives are good only in uniform control flow
	float footprint = length(fwidth(world_position.xz));
	vec3 weather_normal = normal;

	float wet = clamp(gnd_wetness, 0.0, 1.0);
	surface_albedo *= mix(1.0, 0.62, wet);
	surface_roughness = mix(surface_roughness, min(surface_roughness, 0.18), wet * 0.85);

	float snow = 0.0;
	float facing_up = smoothstep(0.25, 0.75, normal.y);
	if (gnd_snow_depth > 0.0001 && snow_share > 0.0 && facing_up > 0.0) {
		float depth = gnd_snow_depth * snow_share;
		float heaping = gnd_weather_snow_heaping(world_position.xz);
		float cover = clamp(depth * heaping / GND_SNOW_COVER_DEPTH, 0.0, 1.0);
		if (cover > 0.001) {
			snow = facing_up * gnd_weather_snow_patches(world_position.xz, cover);
		}
		if (snow > 0.001) {
			float slush = clamp(gnd_snow_wetness * 0.8, 0.0, 1.0);
			surface_albedo = mix(surface_albedo, mix(GND_SNOW_ALBEDO, GND_SLUSH_ALBEDO, slush), snow);
			surface_roughness = mix(surface_roughness, mix(0.75, 0.3, slush), snow);
			// the heaps in the light, near enough to show
			float near = 1.0 - smoothstep(0.1, 0.4, footprint);
			if (near > 0.0) {
				float e = 0.15;
				float heap_depth = smoothstep(0.5, 0.9, normal.y) * min(depth, GND_SNOW_MAX_DEPTH);
				float dx = (gnd_weather_snow_heaping(world_position.xz + vec2(e, 0.0)) - heaping) * heap_depth;
				float dz = (gnd_weather_snow_heaping(world_position.xz + vec2(0.0, e)) - heaping) * heap_depth;
				vec3 snow_normal = normalize(normal - vec3(dx, 0.0, dz) * (near / e));
				weather_normal = normalize(mix(weather_normal, snow_normal, snow));
			}
		}
	}
	world_normal = weather_normal;
	return snow;
}

// gnd_weather_apply_snow_share() with as much snow as on the open ground
float gnd_weather_apply(inout vec3 surface_albedo, inout float surface_roughness, inout vec3 world_normal,
		vec3 world_position, float puddling) {
	return gnd_weather_apply_snow_share(surface_albedo, surface_roughness, world_normal, world_position, puddling, 1.0);
}

void gnd_weather_surface(inout vec3 surface_albedo, inout float surface_roughness, vec3 world_normal, vec3 world_position) {
	gnd_weather_surface_puddled(surface_albedo, surface_roughness, world_normal, world_position, 0.5);
}
