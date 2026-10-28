// The PrecipitationVolumes that keep the precipitation out (precipitation delta -1), for the
// precipitation shaders: boxes (world-to-box transforms and half sizes), set by PrecipitationMesh.
// A box is a roof with all that is under it, below the box's bottom too: a point is kept dry only if
// the way the rain or the snow came to it, back up against its flight, goes through the box's top -
// the flakes falling out of a shelter's bottom flickered as they left the box. A slanting rain gets in
// under the roof from the windward side, as it does. An enclosed box (its bit in
// exclusion_enclosed_mask, PrecipitationVolume.enclosed) has walls all round - a car's interior: nothing
// inside it is wet, whichever way the wind blows.

// as many as WeatherNode.MAX_PRECIPITATION_EXCLUSION_VOLUMES, the nearest the camera
const int MAX_EXCLUSIONS = 16;
uniform int exclusion_count = 0;
uniform mat4 exclusion_inverse_transforms[MAX_EXCLUSIONS];
uniform vec3 exclusion_half_sizes[MAX_EXCLUSIONS];
uniform int exclusion_enclosed_mask = 0;

// world_position - the drop's or the flake's; velocity - its flight (world space, any length)
bool precipitation_sheltered(vec3 world_position, vec3 velocity) {
	for (int i = 0; i < MAX_EXCLUSIONS; i++) {
		if (i >= exclusion_count) {
			break;
		}
		vec3 half_size = exclusion_half_sizes[i];
		vec3 local_position = (exclusion_inverse_transforms[i] * vec4(world_position, 1.0)).xyz;
		bool enclosed = (exclusion_enclosed_mask & (1 << i)) != 0;
		// under the roof, or within the box all round for an enclosed one
		if (any(greaterThan(abs(local_position.xz), half_size.xz)) || local_position.y > half_size.y
				|| (enclosed && local_position.y < -half_size.y)) {
			continue;
		}
		if (enclosed) {
			return true;
		}
		// back the way it came, up to the roof
		vec3 back = (exclusion_inverse_transforms[i] * vec4(-velocity, 0.0)).xyz;
		if (back.y <= 0.0001) {
			// flying flat or upwards: nothing above shelters it
			continue;
		}
		vec3 at_roof = local_position + back * ((half_size.y - local_position.y) / back.y);
		if (abs(at_roof.x) <= half_size.x && abs(at_roof.z) <= half_size.z) {
			return true;
		}
	}
	return false;
}
