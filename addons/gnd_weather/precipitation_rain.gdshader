shader_type spatial;
render_mode blend_premul_alpha, depth_draw_never, cull_disabled, skip_vertex_transform, ambient_light_disabled;

// The rain in a steady wind (weather_wind_steady.gdshaderinc)
#include "res://addons/gnd_weather/weather_wind_steady.gdshaderinc"
#include "res://addons/gnd_weather/precipitation_rain.gdshaderinc"
