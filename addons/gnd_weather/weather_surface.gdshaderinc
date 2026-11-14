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
// ground's there: less under a roof - a volume's, or the scene's own geometry (the shelter map), as
// little as reached it while it gathered - none where a heat source warms it above freezing. The rain
// falling now rings the water only where the shelter map lets it reach (precipitation_shelter.gdshaderinc).

#include "res://addons/gnd_weather/precipitation_shelter.gdshaderinc"

global uniform float gnd_wetness;
global uniform float gnd_air_temperature;
// the ground's surface's temperature (°C): the air's, come after over hours (WeatherSimpleGround) -
// its water freezes by it
global uniform float gnd_ground_temperature;
// how deep the snow lies on the average, in metres
global uniform float gnd_snow_depth;
// how wet the lying snow is (0 - 1): soaked by a rain or a thaw, grey slush
global uniform float gnd_snow_wetness;
// the rain falling on the ground (its share of the precipitation), and how full the ground's hollows
// are of standing water (1 to the brim, up to 3 flooding over)
global uniform float gnd_rain;
// the snow falling (its share of the precipitation, 0 - 1): its flakes melting on the water
global uniform float gnd_snowfall;
// the wind (weather_wind.gdshaderinc's): its wavelets on the water
#ifndef GND_WIND_SPEED_DECLARED
#define GND_WIND_SPEED_DECLARED
global uniform vec2 gnd_wind_direction;
global uniform float gnd_wind_speed;
#endif
global uniform float gnd_puddles;

// the weather probes' (WeatherProbes): the open ground's share of the snow (r), the wet (g) and the
// standing water (b) at each, and its temperature (a, °C) - addressed round in the texture - their
// window's corner and size in the world, and whether there are any
global uniform sampler3D gnd_weather_ground : filter_linear, repeat_enable;
global uniform vec3 gnd_weather_probe_origin;
global uniform vec3 gnd_weather_probe_size;
global uniform float gnd_weather_probes_enabled;
// which of the weather there is on the surfaces - the wet, the snow lying, the water standing, the rain
// falling - and whether any of it lies there (WeatherServer.WET_EXISTS_GLOBAL and the rest): without
// one nothing of it is worked out, without any a surface stays its own
global uniform bool gnd_weather_wet_exists;
global uniform bool gnd_weather_snow_exists;
global uniform bool gnd_weather_puddles_exist;
global uniform bool gnd_weather_rain_exists;
global uniform bool gnd_weather_surfaces_active;
// where the wet's sheen and the standing water fade out, in metres off the camera (x - y), and where
// the camera is (WeatherNode.water_reflections_fade_start, _end)
global uniform vec2 gnd_weather_reflections_fade;
global uniform vec3 gnd_weather_camera_position;

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

// How much deeper than the average the snow heaps up at the most (gnd_weather_snow_heaping()'s)
const float GND_SNOW_HEAPING_MAX = 1.7;

// How far above a surface the precipitation falling now still lands on it, for the shelter map (m): the
// snow that may lie on it, as deep as it heaps, is never its roof - a ground whose snow lifts it (a
// material pushing its vertices up by gnd_weather_snow_depth()) is in the map with that snow
float gnd_weather_surface_shelter_bias() {
	return PRECIPITATION_SHELTER_SURFACE_BIAS + max(gnd_snow_depth, 0.0) * GND_SNOW_HEAPING_MAX;
}

// How much of a probe's cell, from its top, a surface blends into the cell above (of its height): a
// slope crossing the cells has no step
const float GND_WEATHER_PROBE_BLEND = 0.2;

// Where world_position's weather is in the probes' textures: a probe holds the weather of what lies in
// its cell (WeatherProbes), so a surface reads the cell it is in - blended between two cells, a
// platform's top took the one under it, which the platform itself shelters - and across, blended
// between the probes
vec3 gnd_weather_probe_coordinate(vec3 world_position) {
	float cell = gnd_weather_probe_size.y / float(max(textureSize(gnd_weather_ground, 0).y, 1));
	float height = world_position.y / cell;
	float above = smoothstep(1.0 - GND_WEATHER_PROBE_BLEND, 1.0, fract(height));
	return vec3(world_position.x, (floor(height) + 0.5 + above) * cell, world_position.z) / gnd_weather_probe_size;
}

// The weather at world_position from the probes, blended between them and into the open ground's
// towards their window's sides: the open ground's share of its snow, its wet and its standing water,
// and the surface's temperature - 1, 1, 1 and the open ground's out of them or without them
vec4 gnd_weather_local(vec3 world_position) {
	vec4 open_ground = vec4(1.0, 1.0, 1.0, gnd_ground_temperature);
	float inside = gnd_weather_probe_blend(world_position);
	if (inside <= 0.0) {
		return open_ground;
	}
	return mix(open_ground, texture(gnd_weather_ground, gnd_weather_probe_coordinate(world_position)), inside);
}

// How much of the snow a surface as warm as temperature (°C) - surface_heat warmer than that of its
// own, a material's warm place - keeps of the open ground's: none where it is above freezing while the
// open ground is not, the edge soft over a degree; the open ground's own thaw is its depth's
float gnd_weather_snow_kept(float temperature, float surface_heat) {
	float warmth = max(temperature + surface_heat, 0.0) - max(gnd_ground_temperature, 0.0);
	return 1.0 - smoothstep(0.0, 1.0, warmth);
}

// the depth at which the snow covers the ground (WeatherServer.SNOW_COVER_DEPTH)
const float GND_SNOW_COVER_DEPTH = 0.03;

const vec3 GND_SNOW_ALBEDO = vec3(0.86, 0.88, 0.92);
const vec3 GND_SLUSH_ALBEDO = vec3(0.5, 0.53, 0.55);

// How near world_position is for the wet's and the standing water's reflections to show (1 - 0): all
// of them up to gnd_weather_reflections_fade.x metres off the camera, none from .y. Beyond, the wet is
// as rough (0.7) as the screen space reflections skip, and no water stands: the wet scenery reflected
// everywhere cost them every pixel of the screen, the far puddles the sun's glare
float gnd_weather_reflections_near(vec3 world_position) {
	float off = distance(world_position, gnd_weather_camera_position);
	return 1.0 - smoothstep(gnd_weather_reflections_fade.x, max(gnd_weather_reflections_fade.y, gnd_weather_reflections_fade.x + 0.1), off);
}

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

// How flat a surface is for water to stand on it (0 - 1) by its normal's y: all of it up to some
// 3 degrees, none past some 10 - it runs off a steeper slope
float gnd_weather_flat(float normal_y) {
	return smoothstep(0.985, 0.9986, normal_y);
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
	if (!gnd_weather_puddles_exist) {
		return 0.0;
	}
	float level = clamp(gnd_puddles, 0.0, 3.0) * clamp(puddling, 0.0, 1.0) * local.b;
	if (level <= 0.001) {
		return 0.0;
	}
	float flat_up = gnd_weather_flat(normalize(world_normal).y);
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

// The rings on the standing water where the drops land: the slope (x, z) they give its face. They land
// in cells a span or so across times size, as many of them as rate (0 - 1), each spreading a ring that
// fades, as high as strength; footprint - how wide a pixel is there (length(fwidth(world_xz)))
vec2 gnd_weather_rings_at(vec2 world_xz, float footprint, float rate, float size, float strength) {
	// gone where a pixel is wider than the rings, which sparkled in the distance
	float faded = 1.0 - smoothstep(0.015 * size, 0.06 * size, footprint);
	if (rate <= 0.0 || faded <= 0.0) {
		return vec2(0.0);
	}
	vec2 slope = vec2(0.0);
	for (int layer = 0; layer < 2; layer++) {
		float cell_size = (layer == 0 ? 0.33 : 0.21) * size;
		vec2 p = world_xz / cell_size + float(layer) * 17.3;
		// the four cells nearest the point: a ring is under a cell wide when it is still to be seen
		vec2 cell = floor(p - 0.5);
		for (int j = 0; j <= 1; j++) {
			for (int i = 0; i <= 1; i++) {
				vec2 c = cell + vec2(float(i), float(j));
				if (gnd_weather_hash(c * 1.7 + 4.1) > rate) {
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
	return slope * 0.25 * strength * faded;
}

// The rain's rings on the standing water: the slope (x, z) they give its face; footprint - how wide a
// pixel is there (length(fwidth(world_xz)))
vec2 gnd_weather_rain_ripples_at(vec2 world_xz, float footprint) {
	if (!gnd_weather_rain_exists) {
		return vec2(0.0);
	}
	return gnd_weather_rings_at(world_xz, footprint, clamp(gnd_rain, 0.0, 1.0), 1.0, 1.0);
}

// The snow's flakes landing on the unfrozen water: each rests on it a moment, flat, as it fell -
// a clump and its six arms - and softens into the water - its arms first, then its edge blurring
// and its white fading - and is gone in
// GND_FLAKE_MELT_SECONDS. A flake may land in a cell GND_FLAKE_CELL across once a melt, in as many of the
// cells as GND_FLAKE_RATE of the snow falling; the flakes GND_FLAKE_RADIUS across
const float GND_FLAKE_CELL = 0.08;
const float GND_FLAKE_RADIUS = 0.016;
const float GND_FLAKE_MELT_SECONDS = 1.6;
const float GND_FLAKE_RATE = 0.35;

// A flat flake as it fell (precipitation_snow's), how much of it covers q (its own coordinates, its
// radius 1): a clump of crystals, each a soft lump, softening as it melts (age 0 - 1), and its six
// arms, the first to go; seed - its own shape and turn
float gnd_weather_flake_shape(vec2 q, float seed, float age) {
	float clump = 0.0;
	for (int k = 0; k < 4; k++) {
		float hk = seed * 17.3 + float(k) * 3.17;
		vec2 lump = vec2(fract(sin(hk) * 4375.85), fract(sin(hk * 1.7) * 2317.13)) - 0.5;
		float lump_radius = mix(0.25, 0.5, fract(sin(hk * 2.3) * 9131.7)) * (1.0 - 0.3 * age);
		clump = max(clump, 1.0 - smoothstep(lump_radius * 0.45 * (1.0 - age), lump_radius, length(q - lump * 0.9)));
	}
	float angle = atan(q.y, q.x) + seed * 6.2832;
	float arms = pow(abs(cos(angle * 3.0)), 12.0) * (1.0 - smoothstep(0.05, 0.85, length(q))) * (1.0 - age) * (1.0 - age);
	return max(clump * 0.85, arms);
}

// How much of the water at world_xz the melting flakes cover (0 - 1); footprint - how wide a pixel is
// there (length(fwidth(world_xz))): gone where a pixel is wider than a flake
float gnd_weather_flakes_on_water_at(vec2 world_xz, float footprint) {
	float rate = clamp(gnd_snowfall, 0.0, 1.0) * GND_FLAKE_RATE;
	float shown = 1.0 - smoothstep(GND_FLAKE_RADIUS * 0.5, GND_FLAKE_RADIUS * 3.0, footprint);
	if (rate <= 0.0 || shown <= 0.0) {
		return 0.0;
	}
	vec2 p = world_xz / GND_FLAKE_CELL;
	vec2 cell = floor(p);
	float h = gnd_weather_hash(cell + 3.7);
	// each cell's melts in their own time, one flake a melt at the most
	float melt = TIME / GND_FLAKE_MELT_SECONDS + h * 13.0;
	float landing = floor(melt);
	float age = fract(melt);
	if (gnd_weather_hash(cell * 1.3 + landing * 0.71) > rate) {
		return 0.0;
	}
	// within the cell, its edge clear of the cell's
	vec2 centre = cell + 0.3 + 0.4 * vec2(gnd_weather_hash(cell + landing * 1.9), gnd_weather_hash(cell * 2.1 + landing));
	vec2 q = (p - centre) * GND_FLAKE_CELL / (GND_FLAKE_RADIUS * mix(0.7, 1.3, h));
	return gnd_weather_flake_shape(q, gnd_weather_hash(cell * 0.7 + landing * 3.3), age) * (1.0 - age) * shown;
}

// How much of the ice the snow's first flakes lying on it cover (0 - 1): as many of the cells as
// cover (the snow lying there, 0 - 1) times GND_FLAKES_LYING_PER_COVER hold a flake, which stays -
// the ice is dusted with them before the snow covers it; footprint as for the melting ones
const float GND_FLAKES_LYING_PER_COVER = 4.0;
float gnd_weather_flakes_lying_at(vec2 world_xz, float footprint, float cover) {
	float density = clamp(cover * GND_FLAKES_LYING_PER_COVER, 0.0, 1.0);
	float shown = 1.0 - smoothstep(GND_FLAKE_RADIUS * 0.5, GND_FLAKE_RADIUS * 3.0, footprint);
	if (density <= 0.0 || shown <= 0.0) {
		return 0.0;
	}
	vec2 p = world_xz / GND_FLAKE_CELL;
	vec2 cell = floor(p);
	if (gnd_weather_hash(cell * 1.9 + 5.3) > density) {
		return 0.0;
	}
	float h = gnd_weather_hash(cell + 3.7);
	vec2 centre = cell + 0.3 + 0.4 * vec2(gnd_weather_hash(cell + 1.9), gnd_weather_hash(cell * 2.1));
	vec2 q = (p - centre) * GND_FLAKE_CELL / (GND_FLAKE_RADIUS * mix(0.7, 1.3, h));
	return gnd_weather_flake_shape(q, gnd_weather_hash(cell * 0.7 + 3.3), 0.0) * shown;
}

// The wavelets the air ruffles the standing water with: how big they are (m), how high in the still air
// and in a GND_WIND_WAVELET_FULL wind - the water is never a still mirror, which only the ice is
const float GND_WIND_WAVELET_SIZE = 0.7;
const float GND_WIND_WAVELET_STILL = 0.012;
const float GND_WIND_WAVELET_HIGH = 0.08;
const float GND_WIND_WAVELET_FULL = 8.0;

// The wavelets' slope (x, z) at world_xz: two layers of noise drifting across, the higher the harder the
// wind blows (gnd_wind_speed); footprint as for the rings
vec2 gnd_weather_wind_wavelets_at(vec2 world_xz, float footprint) {
	float faded = 1.0 - smoothstep(0.03, 0.15, footprint);
	if (faded <= 0.0) {
		return vec2(0.0);
	}
	float height = mix(GND_WIND_WAVELET_STILL, GND_WIND_WAVELET_HIGH, smoothstep(0.0, GND_WIND_WAVELET_FULL, gnd_wind_speed));
	vec2 slope = vec2(0.0);
	float e = 0.05;
	for (int layer = 0; layer < 2; layer++) {
		float size = GND_WIND_WAVELET_SIZE * (layer == 0 ? 1.0 : 0.43);
		vec2 drift = (layer == 0 ? vec2(0.31, 0.17) : vec2(-0.22, 0.27)) * TIME;
		vec2 p = world_xz / size + drift + float(layer) * 7.1;
		float here = gnd_weather_noise(p);
		slope += vec2(gnd_weather_noise(p + vec2(e, 0.0)) - here, gnd_weather_noise(p + vec2(0.0, e)) - here) / (e * size);
	}
	return slope * height * faded;
}

// gnd_weather_snow() with the weather there given (gnd_weather_local()'s)
float gnd_weather_snow_at(vec3 world_normal, vec3 world_position, vec4 local) {
	float facing_up = smoothstep(0.25, 0.75, normalize(world_normal).y);
	float depth = gnd_snow_depth * local.r * gnd_weather_snow_kept(local.a, 0.0);
	float cover = clamp(depth * gnd_weather_snow_heaping(world_position.xz) / GND_SNOW_COVER_DEPTH, 0.0, 1.0);
	if (facing_up <= 0.0 || cover <= 0.001) {
		return 0.0;
	}
	return facing_up * gnd_weather_snow_patches(world_position.xz, cover);
}

// How much snow lies on a surface (0 - 1): on what faces up, in patches while the cover is thin, as
// much of it as lies there (gnd_weather_local())
float gnd_weather_snow(vec3 world_normal, vec3 world_position) {
	if (!gnd_weather_snow_exists) {
		return 0.0;
	}
	float facing_up = smoothstep(0.25, 0.75, normalize(world_normal).y);
	if (facing_up <= 0.0) {
		return 0.0;
	}
	return gnd_weather_snow_at(world_normal, world_position, gnd_weather_local(world_position));
}

// The deepest a surface is raised by the snow, in metres, however deep it lies (#define it before
// including this to change it): a deeper snow would bury what the scene does not bury - a kerb,
// a step's edge
#ifndef GND_SNOW_MAX_DEPTH
#define GND_SNOW_MAX_DEPTH 1.0
#endif

// gnd_weather_snow_depth() with the weather there given (gnd_weather_local()'s)
float gnd_weather_snow_depth_at(vec3 world_normal, vec3 world_position, vec4 local) {
	float facing_up = smoothstep(0.5, 0.9, normalize(world_normal).y);
	float depth = gnd_snow_depth * local.r * gnd_weather_snow_kept(local.a, 0.0) * gnd_weather_snow_heaping(world_position.xz);
	return facing_up * min(depth, GND_SNOW_MAX_DEPTH);
}

// How deep the snow lies at a point of a surface facing up, in metres: as deep as it lies on the
// average, heaped up here. For vertex(), to raise the surface by:
//   vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
//   vec3 world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
//   float depth = gnd_weather_snow_depth(world_normal, world_position);
//   VERTEX += inverse(mat3(MODEL_MATRIX)) * vec3(0.0, depth, 0.0);
// It moves vertices, so it shows on a dense mesh (a terrain) and not on a box of eight corners.
float gnd_weather_snow_depth(vec3 world_normal, vec3 world_position) {
	if (!gnd_weather_snow_exists) {
		return 0.0;
	}
	return gnd_weather_snow_depth_at(world_normal, world_position, gnd_weather_local(world_position));
}

// The surface's normal turned by the heaps the snow lies in (world space), where there is snow
vec3 gnd_weather_snow_normal(vec3 world_normal, vec3 world_position) {
	if (!gnd_weather_snow_exists) {
		return world_normal;
	}
	float e = 0.15;
	// the probes' once: they stand metres apart, the samples a span
	vec4 local = gnd_weather_local(world_position);
	float here = gnd_weather_snow_depth_at(world_normal, world_position, local);
	if (here <= 0.0001) {
		return world_normal;
	}
	float dx = gnd_weather_snow_depth_at(world_normal, world_position + vec3(e, 0.0, 0.0), local) - here;
	float dz = gnd_weather_snow_depth_at(world_normal, world_position + vec3(0.0, 0.0, e), local) - here;
	return normalize(world_normal - vec3(dx, 0.0, dz) / e);
}

// The weather on a surface: the wet, the water standing in its hollows and the snow on it.
// puddling - how much water the surface holds standing (a paving 1, a soil 0.3, a gravel 0)
void gnd_weather_surface_puddled(inout vec3 surface_albedo, inout float surface_roughness, vec3 world_normal, vec3 world_position, float puddling) {
	if (!gnd_weather_surfaces_active) {
		return;
	}
	// before any branch on the pixel's own: the derivatives are good only in uniform control flow
	float reflections_near = gnd_weather_reflections_near(world_position);
	vec4 local = gnd_weather_local(world_position);
	// wet: darker (the water fills the pores) and glossier
	if (gnd_weather_wet_exists) {
		float wet = clamp(gnd_wetness * local.g, 0.0, 1.0);
		surface_albedo *= mix(1.0, 0.62, wet);
		surface_roughness = mix(surface_roughness, min(surface_roughness, mix(0.7, 0.18, reflections_near)), wet * 0.85);
	}
	// standing water: a mirror over a darker ground, ice in a frost
	// gone beyond the reflections' reach, as the wet's sheen: far off it was the sun's glare
	float water = gnd_weather_standing_water_at(world_normal, world_position, puddling, local) * reflections_near;
	float ice = gnd_weather_water_ice(local.a);
	surface_albedo *= mix(1.0, mix(0.45, 0.8, ice), water);
	surface_roughness = mix(surface_roughness, mix(0.02, 0.1, ice), water);
	// soaked, it greys to a glistening slush
	float snow = gnd_weather_snow_exists ? gnd_weather_snow_at(world_normal, world_position, local) : 0.0;
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
	// a branch on a global: the control flow stays uniform for the derivatives below
	if (!gnd_weather_surfaces_active) {
		return 0.0;
	}
	vec3 normal = normalize(world_normal);
	// before any branch on the pixel's own: the derivatives are good only in uniform control flow
	float footprint = length(fwidth(world_position.xz));
	float reflections_near = gnd_weather_reflections_near(world_position);
	vec3 weather_normal = normal;
	vec4 local = gnd_weather_local(world_position);
	snow_share *= local.r * gnd_weather_snow_kept(local.a, surface_heat);

	if (gnd_weather_wet_exists) {
		float wet = clamp(gnd_wetness * local.g, 0.0, 1.0);
		surface_albedo *= mix(1.0, 0.62, wet);
		surface_roughness = mix(surface_roughness, min(surface_roughness, mix(0.7, 0.18, reflections_near)), wet * 0.85);
	}

	// the water standing in the hollows: a mirror over a darker ground, its level face ringed by the
	// rain, ice in a frost
	// gone beyond the reflections' reach, as the wet's sheen: far off it was the sun's glare
	float water = gnd_weather_standing_water_at(normal, world_position, puddling, local) * reflections_near;
	float liquid = 0.0;
	float frozen_water = 0.0;
	if (water > 0.001) {
		float ice = gnd_weather_water_ice(local.a);
		surface_albedo *= mix(1.0, mix(0.45, 0.8, ice), water);
		surface_roughness = mix(surface_roughness, mix(0.02, 0.1, ice), water);
		// the drops' rings where they reach it, the wind's wavelets everywhere: ice does not stir
		vec2 ripples = (gnd_weather_rain_ripples_at(world_position.xz, footprint)
			* gnd_weather_shelter_exposure(world_position, gnd_weather_surface_shelter_bias())
			+ gnd_weather_wind_wavelets_at(world_position.xz, footprint)) * (1.0 - ice);
		weather_normal = normalize(mix(normal, normalize(vec3(-ripples.x, 1.0, -ripples.y)), water));
		// the flakes melting on it where they reach it
		float flakes = gnd_weather_flakes_on_water_at(world_position.xz, footprint) * water * (1.0 - ice)
			* gnd_weather_shelter_exposure(world_position, gnd_weather_surface_shelter_bias());
		surface_albedo = mix(surface_albedo, GND_SNOW_ALBEDO, flakes);
		surface_roughness = mix(surface_roughness, 0.6, flakes);
		// the snow lies on the ice, not on the water: it melts into it
		liquid = water * (1.0 - ice);
		frozen_water = water * ice;
	}
	snow_share *= 1.0 - liquid;

	float snow = 0.0;
	float facing_up = smoothstep(0.25, 0.75, normal.y);
	if (gnd_weather_snow_exists && snow_share > 0.0 && facing_up > 0.0) {
		float depth = gnd_snow_depth * snow_share;
		float heaping = gnd_weather_snow_heaping(world_position.xz);
		float cover = clamp(depth * heaping / GND_SNOW_COVER_DEPTH, 0.0, 1.0);
		if (cover > 0.001) {
			snow = facing_up * gnd_weather_snow_patches(world_position.xz, cover);
			// on the ice its first flakes, lying as they fell
			snow = max(snow, gnd_weather_flakes_lying_at(world_position.xz, footprint, cover) * frozen_water);
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
