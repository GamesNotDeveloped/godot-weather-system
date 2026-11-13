// The weather's wind for any shader (the vegetation's): #define GND_WIND_GLOBALS before including
// this. The globals are WeatherServer's, set by the WeatherNode (the plugin registers them). A
// weather of more - gusts sweeping across the scene, eddies - brings shaders of its own.
#ifdef GND_WIND_GLOBALS
global uniform vec2 gnd_wind_direction;
// metres a second, its gusts and lulls over time included
global uniform float gnd_wind_speed;
// how hard the vegetation sways in it (a factor for its shaders)
global uniform float gnd_wind_strength;
global uniform float gnd_wind_turbulence;

// The wind where world_position is, in metres a second: the same everywhere, as strong as it
// blows now
vec3 gnd_wind_at(vec3 gw_world_position) {
	vec2 gw_wind = gnd_wind_direction * gnd_wind_speed;
	return vec3(gw_wind.x, 0.0, gw_wind.y);
}
#endif
