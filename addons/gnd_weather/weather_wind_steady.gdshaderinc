// The precipitation in a steady wind: it falls slanting with the wind (its flight, the drops' and the
// flakes' own sway), evenly, without gusts or eddies - a weather of more brings a wind of its own
// with them (precipitation_rain.gdshaderinc, precipitation_snow.gdshaderinc)

vec3 precipitation_rain_wind(vec3 world_position, vec2 wind, float gust_strength, float gust_scale,
		float turbulence, float seed, float variation, float time) {
	return vec3(0.0);
}

vec3 precipitation_snow_wind(vec3 position, vec2 flight, float gust_strength, float gust_scale,
		float turbulence, float seed, float detail, float response, float time) {
	return position;
}
