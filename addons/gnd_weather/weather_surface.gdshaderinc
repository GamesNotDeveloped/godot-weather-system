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
// The globals are WeatherServer's, set by the WeatherNode (the plugin registers them). Where the
// weather probes reach (WeatherNode's weather_probe_*), the snow, the wet and their warmth are the
// ground's there: less under a roof, none where a heat source warms it above freezing.

global uniform float gnd_wetness;
global uniform float gnd_air_temperature;
// how deep the snow lies on the average, in metres
global uniform float gnd_snow_depth;
// how wet the lying snow is (0 - 1): soaked by a rain or a thaw, grey slush
global uniform float gnd_snow_wetness;
// the rain falling on the ground (its share of the precipitation), and how full the ground's hollows
// are of standing water (1 to the brim, up to 3 flooding over)
global uniform float gnd_rain;
global uniform float gnd_puddles;

// the weather probes' (WeatherProbes): the open ground's share of the snow (r), the wet (g) and the
// standing water (b) at each, and its temperature (a, °C) - addressed round in the texture - their
// window's corner and size in the world, and whether there are any
global uniform sampler3D gnd_weather_ground : filter_linear, repeat_enable;
global uniform vec3 gnd_weather_probe_origin;
global uniform vec3 gnd_weather_probe_size;
global uniform float gnd_weather_probes_enabled;

// How far world_position is in the probes' window: 1 well in, down to 0 towards its sides, 0 out of
// it or without probes - for blending what the probes tell into the open ground's
float gnd_weather_probe_blend(vec3 world_position) {
	vec3 in_window = (world_position - gnd_weather_probe_origin) / max(gnd_weather_probe_size, vec3(0.001));
	if (gnd_weather_probes_enabled < 0.5 || any(lessThan(in_window, vec3(0.0))) || any(greaterThan(in_window, vec3(1.0)))) {
		return 0.0;
	}
	vec3 from_side = min(in_window, 1.0 - in_window);
	return smoothstep(0.0, 0.08, min(from_side.x, from_side.z)) * smoothstep(0.0, 0.08, from_side.y);
}

// The weather at world_position from the probes, blended between them and into the open ground's
// towards their window's sides: the open ground's share of its snow, its wet and its standing water,
// and the temperature - 1, 1, 1 and the air's out of them or without them
vec4 gnd_weather_local(vec3 world_position) {
	vec4 open_ground = vec4(1.0, 1.0, 1.0, gnd_air_temperature);
	float inside = gnd_weather_probe_blend(world_position);
	if (inside <= 0.0) {
		return open_ground;
	}
	return mix(open_ground, texture(gnd_weather_ground, world_position / gnd_weather_probe_size), inside);
}

// How much of the snow a surface as warm as temperature (°C) - surface_heat warmer than that of its
// own, a material's warm place - keeps of the open ground's: none where it is above freezing while the
// air is not, the edge soft over a degree; the open ground's own thaw is its depth's
float gnd_weather_snow_kept(float temperature, float surface_heat) {
	float warmth = max(temperature + surface_heat, 0.0) - max(gnd_air_temperature, 0.0);
	return 1.0 - smoothstep(0.0, 1.0, warmth);
}

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

// How deep a point lies in the ground's hollows (0 - 1, 1 the deepest): a lumpy surface a few
// metres across with dips a span across in it, where the water gathers. A ground's material can
// sink its surface by it (the demo's does) so the puddles lie in its dips
float gnd_weather_hollows(vec2 world_xz) {
	vec2 p = world_xz * 0.32;
	float hollows = gnd_weather_noise(p) * 0.55;
	p = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 2.07 + 7.3;
	hollows += gnd_weather_noise(p) * 0.3;
	p = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 2.3 + 1.9;
	hollows += gnd_weather_noise(p) * 0.15;
	return hollows;
}

// How much water stands on a surface facing up (0 - 1): first in its deepest hollows, spreading as
// they fill and over them as it floods (gnd_puddles past 1), with a sharp shore, as much as stands
// where it is (local: gnd_weather_local()); puddling - how much of it the surface holds (a paving or
// a platform 1, a soil that soaks it up 0.3 or so, a gravel that lets it through 0)
float gnd_weather_standing_water_at(vec3 world_normal, vec3 world_position, float puddling, vec4 local) {
	float level = clamp(gnd_puddles, 0.0, 3.0) * clamp(puddling, 0.0, 1.0) * local.b;
	if (level <= 0.001) {
		return 0.0;
	}
	float flat_up = smoothstep(0.85, 0.97, normalize(world_normal).y);
	float shore = 1.0 - level * 0.6;
	return flat_up * smoothstep(shore, shore + 0.04, gnd_weather_hollows(world_position.xz));
}

float gnd_weather_standing_water(vec3 world_normal, vec3 world_position, float puddling) {
	return gnd_weather_standing_water_at(world_normal, world_position, puddling, gnd_weather_local(world_position));
}

// How far the standing water is frozen at temperature (°C): ice from half a degree below freezing
float gnd_weather_water_ice(float temperature) {
	return smoothstep(0.5, -1.0, temperature);
}

// The rain's rings on the standing water: the slope (x, z) they give its face. Drops land in cells
// a span or so across, as many of them as hard as it rains, each spreading a ring that fades;
// footprint - how wide a pixel is there (length(fwidth(world_xz)))
vec2 gnd_weather_rain_ripples_at(vec2 world_xz, float footprint) {
	float rain = clamp(gnd_rain, 0.0, 1.0);
	// gone where a pixel is wider than the rings, which sparkled in the distance
	float faded = 1.0 - smoothstep(0.015, 0.06, footprint);
	if (rain <= 0.01 || faded <= 0.0) {
		return vec2(0.0);
	}
	vec2 slope = vec2(0.0);
	for (int layer = 0; layer < 2; layer++) {
		float size = layer == 0 ? 0.33 : 0.21;
		vec2 p = world_xz / size + float(layer) * 17.3;
		vec2 cell = floor(p);
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec2 c = cell + vec2(float(i), float(j));
				if (gnd_weather_hash(c * 1.7 + 4.1) > rain) {
					continue;
				}
				float h = gnd_weather_hash(c + 0.37);
				vec2 centre = c + vec2(gnd_weather_hash(c), gnd_weather_hash(c + 9.1));
				float age = fract(TIME * mix(0.9, 1.4, h) + h * 7.0);
				vec2 d = p - centre;
				float distance_to = length(d);
				float band = distance_to - age * 0.9;
				float envelope = (1.0 - age) * (1.0 - age) * exp(-band * band * 60.0);
				slope += d / max(distance_to, 0.001) * cos(band * 40.0) * envelope;
			}
		}
	}
	return slope * 0.25 * faded;
}

// How much snow lies on a surface (0 - 1): on what faces up, in patches while the cover is thin, as
// much of it as lies there (gnd_weather_local())
float gnd_weather_snow(vec3 world_normal, vec3 world_position) {
	if (gnd_snow_depth <= 0.0001) {
		return 0.0;
	}
	float facing_up = smoothstep(0.25, 0.75, normalize(world_normal).y);
	if (facing_up <= 0.0) {
		return 0.0;
	}
	vec4 local = gnd_weather_local(world_position);
	float depth = gnd_snow_depth * local.r * gnd_weather_snow_kept(local.a, 0.0);
	float cover = clamp(depth * gnd_weather_snow_heaping(world_position.xz) / GND_SNOW_COVER_DEPTH, 0.0, 1.0);
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
	vec4 local = gnd_weather_local(world_position);
	float depth = gnd_snow_depth * local.r * gnd_weather_snow_kept(local.a, 0.0) * gnd_weather_snow_heaping(world_position.xz);
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

// The weather on a surface: the wet, the water standing in its hollows and the snow on it.
// puddling - how much water the surface holds standing (a paving 1, a soil 0.3, a gravel 0)
void gnd_weather_surface_puddled(inout vec3 surface_albedo, inout float surface_roughness, vec3 world_normal, vec3 world_position, float puddling) {
	vec4 local = gnd_weather_local(world_position);
	// wet: darker (the water fills the pores) and glossier
	float wet = clamp(gnd_wetness * local.g, 0.0, 1.0);
	surface_albedo *= mix(1.0, 0.62, wet);
	surface_roughness = mix(surface_roughness, min(surface_roughness, 0.18), wet * 0.85);
	// standing water: a mirror over a darker ground, ice in a frost
	float water = gnd_weather_standing_water_at(world_normal, world_position, puddling, local);
	float ice = gnd_weather_water_ice(local.a);
	surface_albedo *= mix(1.0, mix(0.45, 0.8, ice), water);
	surface_roughness = mix(surface_roughness, mix(0.02, 0.1, ice), water);
	// soaked, it greys to a glistening slush
	float snow = gnd_weather_snow(world_normal, world_position);
	float slush = clamp(gnd_snow_wetness * 0.8, 0.0, 1.0);
	surface_albedo = mix(surface_albedo, mix(GND_SNOW_ALBEDO, GND_SLUSH_ALBEDO, slush), snow);
	surface_roughness = mix(surface_roughness, mix(0.75, 0.3, slush), snow);
}

// Everything the weather does to a surface, each part worked out once and only where it is - for a
// material taking its colour, roughness and normal from it (fragment() only): the wet, the water
// standing in the hollows with its level face ringed by the rain, the snow lying with its heaps in
// the light as near as a pixel is small enough to show them. world_normal - the surface's own
// (world space) in, the weather's out; returns how far the snow or the water covers the surface, for
// its own bumps (its normal map) to go under them. puddling - as for
// gnd_weather_surface_puddled(). snow_share - how much of the snow on the open ground lies on
// the surface: 0 none (a road cleared of it), 1 as much, more where it was heaped up (the banks a
// plough leaves); surface_heat - how much warmer than where it stands the surface is of its own (°C,
// a material's warm place: a chimney, a boiler room's wall, an engine's cover). The snow and the
// wet are as much as lies where it is (gnd_weather_local())
float gnd_weather_apply_heated(inout vec3 surface_albedo, inout float surface_roughness, inout vec3 world_normal,
		vec3 world_position, float puddling, float snow_share, float surface_heat) {
	vec3 normal = normalize(world_normal);
	// before any branch: the derivatives are good only in uniform control flow
	float footprint = length(fwidth(world_position.xz));
	vec3 weather_normal = normal;
	vec4 local = gnd_weather_local(world_position);
	snow_share *= local.r * gnd_weather_snow_kept(local.a, surface_heat);

	float wet = clamp(gnd_wetness * local.g, 0.0, 1.0);
	surface_albedo *= mix(1.0, 0.62, wet);
	surface_roughness = mix(surface_roughness, min(surface_roughness, 0.18), wet * 0.85);

	// the water standing in the hollows: a mirror over a darker ground, its level face ringed by the
	// rain, ice in a frost
	float water = gnd_weather_standing_water_at(normal, world_position, puddling, local);
	if (water > 0.001) {
		float ice = gnd_weather_water_ice(local.a);
		surface_albedo *= mix(1.0, mix(0.45, 0.8, ice), water);
		surface_roughness = mix(surface_roughness, mix(0.02, 0.1, ice), water);
		vec2 ripples = gnd_weather_rain_ripples_at(world_position.xz, footprint) * (1.0 - ice);
		weather_normal = normalize(mix(normal, normalize(vec3(-ripples.x, 1.0, -ripples.y)), water));
	}

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
	return max(snow, water);
}

// gnd_weather_apply_heated() with the surface as warm as where it stands
float gnd_weather_apply_snow_share(inout vec3 surface_albedo, inout float surface_roughness, inout vec3 world_normal,
		vec3 world_position, float puddling, float snow_share) {
	return gnd_weather_apply_heated(surface_albedo, surface_roughness, world_normal, world_position, puddling, snow_share, 0.0);
}

// gnd_weather_apply_snow_share() with as much snow as on the open ground
float gnd_weather_apply(inout vec3 surface_albedo, inout float surface_roughness, inout vec3 world_normal,
		vec3 world_position, float puddling) {
	return gnd_weather_apply_snow_share(surface_albedo, surface_roughness, world_normal, world_position, puddling, 1.0);
}

void gnd_weather_surface(inout vec3 surface_albedo, inout float surface_roughness, vec3 world_normal, vec3 world_position) {
	gnd_weather_surface_puddled(surface_albedo, surface_roughness, world_normal, world_position, 0.5);
}
