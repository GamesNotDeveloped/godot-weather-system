// The precipitation's shelter map (PrecipitationShelterMap, precipitation_shelter_map.gdshaderinc) for
// the scene's materials: every roof, canopy, tree and vehicle shelters what is under it, and a
// slanting rain wets the windward edge under a roof. Out of the map, or without one, nothing is
// sheltered by it (the PrecipitationVolumes and the probes still are).
//
// The globals are WeatherServer's (SHELTER_*_GLOBAL, by gnd_weather/ground_globals_prefix as the
// ground's are), set by the map as it is rendered.

#ifndef GND_WEATHER_SHELTER_INCLUDED
#define GND_WEATHER_SHELTER_INCLUDED

#include "res://addons/gnd_weather/precipitation_shelter_map.gdshaderinc"

// how far along the fall the first thing the precipitation meets is, in metres from the map's camera
global uniform sampler2D gnd_weather_shelter_map : filter_nearest, repeat_disable;
// world to the map: x, y - the texel's coordinates (0 - 1), z - how far along the fall, in metres
global uniform mat4 gnd_weather_shelter_transform;
global uniform float gnd_weather_shelter_enabled;

// How much of the precipitation reaches a surface at world_position, of the open sky's (0 - 1): beyond
// the first thing it meets by more than bias metres, none; 1 out of the map or without one
float gnd_weather_shelter_exposure(vec3 world_position, float bias) {
	if (gnd_weather_shelter_enabled < 0.5) {
		return 1.0;
	}
	return precipitation_shelter_exposure(gnd_weather_shelter_map, gnd_weather_shelter_transform, world_position, bias);
}

#endif
