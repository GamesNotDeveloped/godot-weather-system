#[compute]
#version 450

// The weather probes (WeatherProbes.gd): a lattice of them fixed in the world about the camera, held
// in 3D textures addressed round in it - the probe of world cell w in texel w mod dims, so the window
// moving over the world re-works only what came into it.
//
// mode 0 - the probes: how much of the precipitation reaches each (the PrecipitationVolumes, by
//   their delta, multiplier and feathered edge; a roof by the way the rain or the snow comes), the
//   temperature there (the heat sources: weight 1 inside, smoothstep down to 0 over falloff, T = T_air + sum weight * level * (temperature - T_air)
//   kept between the air's and the sources' temperatures), the air's humidity as warm as it is there,
//   and the lightning's multiplier
// mode 1 - the ground at each probe over time: its wet, snow and standing water, gathering as the
//   probe lets the precipitation in, never more than the open ground's, and melting and drying faster
//   as it is warmer than the air; kept as amounts (ground_state) and given as the open ground's share
//   with the temperature (ground)

layout(local_size_x = 4, local_size_y = 4, local_size_z = 4) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict image3D probes;
layout(rgba32f, set = 0, binding = 1) uniform restrict image3D ground_state;
layout(rgba16f, set = 0, binding = 2) uniform restrict writeonly image3D ground;

// WeatherProbes.Param by their index
layout(set = 0, binding = 3, std430) restrict readonly buffer Params {
	float p[];
} params;

// WeatherProbes.VOLUME_STRIDE floats each, sorted as the volumes are applied: the world-to-volume
// transform's rows (12), half size (3), edge feather, delta, multiplier, lightning multiplier,
// enclosed (1 or 0), 4 unused
layout(set = 0, binding = 4, std430) restrict readonly buffer Volumes {
	float v[];
} volumes;

// WeatherHeatProvider.STRIDE floats each, as WeatherProbes lays them: the world-to-source transform's
// rows (12), shape (0 a sphere, 1 a box), radius or half size (3), falloff, temperature, level, unused
layout(set = 0, binding = 5, std430) restrict readonly buffer HeatSources {
	float h[];
} heat;

const int VOLUME_STRIDE = 24;
const int HEAT_STRIDE = 20;
// the share of a feathered edge a volume that takes the precipitation away keeps it at, remapped so
// the edge does not let a thin rain through
const float SUPPRESSIVE_BLEND_START = 0.28;
const float SUPPRESSIVE_BLEND_END = 0.94;

ivec3 dims() {
	return ivec3(params.p[4], params.p[5], params.p[6]);
}

// the world cell a texel holds in a window from base (GLSL's % is undefined for a negative operand,
// so by floor)
ivec3 world_cell(ivec3 texel, ivec3 base) {
	ivec3 d = dims();
	ivec3 m = texel - base;
	m -= d * ivec3(floor(vec3(m) / vec3(d)));
	return base + m;
}

vec3 to_local(int offset, bool is_heat, vec3 point) {
	vec4 position = vec4(point, 1.0);
	if (is_heat) {
		return vec3(dot(vec4(heat.h[offset], heat.h[offset + 1], heat.h[offset + 2], heat.h[offset + 3]), position),
			dot(vec4(heat.h[offset + 4], heat.h[offset + 5], heat.h[offset + 6], heat.h[offset + 7]), position),
			dot(vec4(heat.h[offset + 8], heat.h[offset + 9], heat.h[offset + 10], heat.h[offset + 11]), position));
	}
	return vec3(dot(vec4(volumes.v[offset], volumes.v[offset + 1], volumes.v[offset + 2], volumes.v[offset + 3]), position),
		dot(vec4(volumes.v[offset + 4], volumes.v[offset + 5], volumes.v[offset + 6], volumes.v[offset + 7]), position),
		dot(vec4(volumes.v[offset + 8], volumes.v[offset + 9], volumes.v[offset + 10], volumes.v[offset + 11]), position));
}

vec3 volume_direction(int offset, vec3 direction) {
	return vec3(dot(vec3(volumes.v[offset], volumes.v[offset + 1], volumes.v[offset + 2]), direction),
		dot(vec3(volumes.v[offset + 4], volumes.v[offset + 5], volumes.v[offset + 6]), direction),
		dot(vec3(volumes.v[offset + 8], volumes.v[offset + 9], volumes.v[offset + 10]), direction));
}

// PrecipitationVolume.get_precipitation_blend(): 1 inside, a smoothstep over the feather outside, by
// the axis nearest the feathered box's side (only x and z for a roof's footprint)
float box_blend(vec3 local, vec3 half_size, float feather, bool footprint) {
	vec3 a = abs(local);
	bool inside = a.x <= half_size.x && a.z <= half_size.z && (footprint || a.y <= half_size.y);
	if (inside) {
		return 1.0;
	}
	if (feather <= 0.0001) {
		return 0.0;
	}
	vec3 to_edge = half_size + feather - a;
	float d = footprint ? min(to_edge.x, to_edge.z) : min(to_edge.x, min(to_edge.y, to_edge.z));
	if (d <= 0.0) {
		return 0.0;
	}
	return smoothstep(0.0, 1.0, clamp(d / feather, 0.0, 1.0));
}

// Magnus: the vapour pressure of saturated air at t (hPa)
float saturation(float t) {
	return 6.112 * exp(17.62 * t / (243.12 + t));
}

void work_probe(ivec3 texel, vec3 point) {
	vec3 fall = vec3(params.p[12], params.p[13], params.p[14]);
	float air = params.p[15];
	float humidity = params.p[16];
	int volume_count = int(params.p[18]);
	int heat_count = int(params.p[19]);

	// the precipitation reaching it, of the open sky's, and the lightning's multiplier
	float reach = 1.0;
	float lightning = 1.0;
	for (int i = 0; i < volume_count; i++) {
		int o = i * VOLUME_STRIDE;
		vec3 local = to_local(o, false, point);
		vec3 half_size = vec3(volumes.v[o + 12], volumes.v[o + 13], volumes.v[o + 14]);
		float feather = volumes.v[o + 15];
		float delta = volumes.v[o + 16];
		float multiplier = volumes.v[o + 17];
		bool enclosed = volumes.v[o + 19] > 0.5;
		float blend;
		if (delta <= -1.0 && !enclosed) {
			// a roof keeps dry all under it, below its box too, as far as the way the rain or the snow
			// came, back up against its flight, goes through its top
			vec3 back = volume_direction(o, -fall);
			if (local.y > half_size.y + feather || back.y <= 0.0001) {
				blend = 0.0;
			} else {
				vec3 at_roof = local + back * ((half_size.y - local.y) / back.y);
				blend = box_blend(local.y > half_size.y ? local : at_roof, half_size, feather, true);
				if (local.y > half_size.y) {
					blend *= 1.0 - smoothstep(0.0, 1.0, (local.y - half_size.y) / max(feather, 0.0001));
				}
			}
		} else {
			blend = box_blend(local, half_size, feather, false);
		}
		if (blend <= 0.0) {
			continue;
		}
		float full = clamp((reach + delta) * multiplier, 0.0, 1.0);
		float effective = blend;
		if (full < reach - 0.0001 && blend < 1.0) {
			effective = smoothstep(SUPPRESSIVE_BLEND_START, SUPPRESSIVE_BLEND_END, blend);
		}
		reach = clamp((reach + delta * effective) * mix(1.0, multiplier, effective), 0.0, 1.0);
		lightning *= mix(1.0, volumes.v[o + 18], blend);
	}

	// the temperature: the heat sources' about it
	float t = air;
	float low = air;
	float high = air;
	for (int i = 0; i < heat_count; i++) {
		int o = i * HEAT_STRIDE;
		vec3 local = to_local(o, true, point);
		vec3 extent = vec3(heat.h[o + 13], heat.h[o + 14], heat.h[o + 15]);
		float distance_out = heat.h[o + 12] < 0.5
			? length(local) - extent.x
			: length(max(abs(local) - extent, vec3(0.0)));
		float falloff = heat.h[o + 16];
		float weight = distance_out <= 0.0 ? 1.0
			: (falloff > 0.0001 ? 1.0 - smoothstep(0.0, falloff, distance_out) : 0.0);
		if (weight <= 0.0) {
			continue;
		}
		float temperature = heat.h[o + 17];
		t += weight * clamp(heat.h[o + 18], 0.0, 1.0) * (temperature - air);
		low = min(low, temperature);
		high = max(high, temperature);
	}
	t = clamp(t, low, high);
	// the air's water as warm as it is here: warmer, drier
	float local_humidity = clamp(humidity * saturation(air) / saturation(t), 0.0, 1.0);
	imageStore(probes, texel, vec4(reach, t, local_humidity, lightning));
}

void work_ground(ivec3 texel) {
	vec4 probe = imageLoad(probes, texel);
	float reach = probe.r;
	float t = probe.g;
	float air = params.p[15];
	float hours = params.p[20];
	float rain_mm = params.p[21];
	float snow_fall = params.p[22];
	float open_wet = params.p[23];
	float open_snow = params.p[24];
	float open_water = params.p[25];
	float wet_film = max(params.p[26], 0.0001);
	float melt_per_degree = params.p[27];
	float drying_mm = params.p[28];

	vec4 state = imageLoad(ground_state, texel);
	ivec3 base = ivec3(params.p[0], params.p[1], params.p[2]);
	ivec3 old_base = ivec3(params.p[8], params.p[9], params.p[10]);
	bool fresh = params.p[11] > 0.5 || world_cell(texel, base) != world_cell(texel, old_base);
	if (fresh) {
		// one come into the window: as if the weather had always been as it is
		state = vec4(open_wet * reach, open_snow * reach, open_water * reach, 0.0);
	} else {
		state.x = min(state.x + rain_mm * hours / wet_film * reach, open_wet);
		state.y = min(state.y + snow_fall * hours * reach, open_snow);
		state.z = min(state.z + rain_mm * hours * reach, open_water);
		// warmer than the air: the snow melts by as much more, and the wet dries as much faster as the
		// air's vapour pressure falls further short of the saturated there than on the open ground (the
		// open ground's own drying is the ground model's: its amounts cap these)
		float warmth = max(t, 0.0) - max(air, 0.0);
		if (warmth > 0.0) {
			state.y = max(state.y - hours * melt_per_degree * warmth, 0.0);
			float vapour = clamp(params.p[16], 0.0, 1.0) * saturation(air);
			float open_deficit = max(saturation(air) - vapour, 0.0001);
			float drying = hours * drying_mm * max((saturation(t) - vapour) / open_deficit - 1.0, 0.0);
			state.x = max(state.x - drying / wet_film, 0.0);
			state.z = max(state.z - drying, 0.0);
		}
	}
	imageStore(ground_state, texel, state);
	vec3 share = vec3(
		open_snow > 0.0001 ? clamp(state.y / open_snow, 0.0, 1.0) : 1.0,
		open_wet > 0.0001 ? clamp(state.x / open_wet, 0.0, 1.0) : 1.0,
		open_water > 0.0001 ? clamp(state.z / open_water, 0.0, 1.0) : 1.0);
	imageStore(ground, texel, vec4(share, t));
}

void main() {
	ivec3 texel = ivec3(gl_GlobalInvocationID);
	ivec3 d = dims();
	if (any(greaterThanEqual(texel, d))) {
		return;
	}
	ivec3 base = ivec3(params.p[0], params.p[1], params.p[2]);
	float cell = params.p[7];
	vec3 point = (vec3(world_cell(texel, base)) + 0.5) * cell;
	if (params.p[3] < 0.5) {
		work_probe(texel, point);
	} else {
		work_ground(texel);
	}
}
