// The precipitation's shelter map (PrecipitationShelterMap) read, given the map and its world-to-map
// transform: the scene's own opaque geometry about the camera, rendered looking the way the
// precipitation falls (the wind slanting it), kept as how far along the fall the first thing the
// precipitation meets is. A point beyond that, back up along the fall, is under a roof. Out of the map
// nothing is sheltered by it. The precipitation's shaders take the map as their own parameters
// (precipitation_exclusion.gdshaderinc), the scene's materials as globals
// (precipitation_shelter.gdshaderinc).

#ifndef PRECIPITATION_SHELTER_MAP_INCLUDED
#define PRECIPITATION_SHELTER_MAP_INCLUDED

// How far beyond the first thing it meets a drop or a flake is before it counts as under it (m): one
// falling onto a surface reaches it
const float PRECIPITATION_SHELTER_DROP_BIAS = 0.05;
// How far beyond the first thing the precipitation meets a surface is before it counts as under it (m):
// a roof is the first thing itself, and a texel of a sloping one some centimetres deep
const float PRECIPITATION_SHELTER_SURFACE_BIAS = 0.3;
// How far in from the map's sides it shelters fully (of its width): blended into the open sky's
// towards them, so the dry floor under a far roof fades instead of ending at a line
const float PRECIPITATION_SHELTER_EDGE = 0.06;

// Whether a drop or a flake at world_position is under something: one texel of the map, beyond it by
// more than bias metres; to_map - world to the map (x, y - the texel's coordinates, 0 - 1, z - how far
// along the fall, in metres)
bool precipitation_shelter_covered(sampler2D map, mat4 to_map, vec3 world_position, float bias) {
	vec3 in_map = (to_map * vec4(world_position, 1.0)).xyz;
	if (any(lessThan(in_map.xy, vec2(0.0))) || any(greaterThan(in_map.xy, vec2(1.0)))) {
		return false;
	}
	return in_map.z - bias > textureLod(map, in_map.xy, 0.0).r;
}

// How much of the precipitation reaches a surface at world_position, of the open sky's (0 - 1): the
// four texels about it, blended, so a roof's shadow on the floor has a soft edge; 1 out of the map
float precipitation_shelter_exposure(sampler2D map, mat4 to_map, vec3 world_position, float bias) {
	vec3 in_map = (to_map * vec4(world_position, 1.0)).xyz;
	vec2 from_side = min(in_map.xy, 1.0 - in_map.xy);
	float inside = smoothstep(0.0, PRECIPITATION_SHELTER_EDGE, min(from_side.x, from_side.y));
	if (inside <= 0.0) {
		return 1.0;
	}
	// textureGather's order: x (0, 1), y (1, 1), z (1, 0), w (0, 0) - the bottom row w, z
	vec4 first = textureGather(map, in_map.xy, 0);
	vec4 open = step(vec4(in_map.z - bias), first);
	vec2 f = fract(in_map.xy * vec2(textureSize(map, 0)) - 0.5);
	float exposure = mix(mix(open.w, open.z, f.x), mix(open.x, open.y, f.x), f.y);
	return mix(1.0, exposure, inside);
}

#endif
