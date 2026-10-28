# Godot Weather System

Weather for Godot 4: rain, snow and sleet falling about the camera, the snow lying and melting and
the ground wetting and drying over time, puddles, shelters that keep the precipitation out, a gusty
wind for everything that sways in it, lightning, and the season of the date and the place. It drives
[godot-skydome](https://github.com/GamesNotDeveloped/godot-skydome)'s clouds, fog and lightning when
there is one, and works without it.

## Features

* rain, snow and sleet (`precipitation_intensity`, `precipitation_snow`), or the snow worked out of
  the air temperature (`snow_from_temperature`, °C or °F): snow below `snow_temperature_max`
  (-0.5 °C), rain above `rain_temperature_min` (+3.5 °C), sleet between them, the one turning to
  the other over `snow_change_seconds` (3) of the world's time
* a heavy snow that hides the world (`fog_snow_affect`), a downpour that greys the distance out
  (`fog_rain_affect`), and a blizzard in a gusty wind
* a rain that slants as far as the wind carries it (falling 7.5 m/s: 45 degrees in a 7.5 m/s wind,
  65 in an 18 m/s gale), and pours at the full intensity: 50 mm an hour, many more drops
* the wind: direction, speed in m/s with its gusts and lulls over time, the rain, the snow and the
  vegetation going with it evenly; a weather of more brings gusts sweeping across the scene and
  eddies (`GndWeatherServer` extended, `rain_shader`, `snow_shader`)
* snow lying deeper and deeper over the world's time and melting in a thaw, and the rain in
  millimetres of water wetting the surfaces and drying, for the scene's own materials - a model of
  the ground (`WeatherGroundModel`) of more brings drifts, the walls' snow, puddles and ice
* puddles that ripple in the rain, freeze and go under the snow, and reflect, as full as a ground
  model of standing water fills them
* `PrecipitationVolume`s - shelters, closed interiors - that keep it out, a roof letting a slanting
  one in from the windward side, an enclosed one none
* lightning and thunder in a storm; or flashes a minute and how far off they strike from a weather
  simulation, the thunder after its flash
* the rainbow set from outside, or left to the sky
* the season by the latitude and the date, as the Earth has it

## Usage

1. Enable the plugin (Project Settings → Plugins → gnd_weather). It registers the shader globals
   the weather sets (`shader_globals/gnd_*`) and its project settings (`gnd_weather/*`).
2. Add a `WeatherNode` to the scene. Nothing of it runs every frame: the weather goes on in ticks
   (`WEATHER_TICK_SECONDS`, 0.1 s of the game's time), the rain and the snow stand on lattices fixed
   in the world which their shaders wrap round the camera - its moving costs nothing - and the
   shaders' parameters change only as the weather does; a shelter (`PrecipitationVolume`) gives the
   shaders its box only as it moves.
3. Optionally point its `skydome_path` at a Skydome; without one it finds a node named `Skydome`, and
   with none it fogs the `Environment` itself for a heavy snow.
4. Set the weather: the **Weather** group (`precipitation_intensity`, `precipitation_snow` or
   `snow_from_temperature` with `air_temperature`, clouds, storm), the **Wind** group, the
   **Season** group (`latitude`, `set_date()`) and the **Ground** group (`weather_time_scale` - the
   game's time scale - and a scenario's starting `snow_depth` and `wetness`).

The `demo/` project shows all of it, with a panel of the inputs.

## The ground in your materials

The weather does not touch the scene's materials. A spatial shader that should take the snow and
the wet includes `weather_surface.gdshaderinc`:

```glsl
shader_type spatial;
#include "res://addons/gnd_weather/weather_surface.gdshaderinc"

varying vec3 world_position;

void vertex() {
	// not INV_VIEW_MATRIX * VERTEX in fragment(): a double precision build keeps the view's origin
	// there its own way, kilometres off far from the world's origin
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 albedo = texture(albedo_texture, UV).rgb;
	float roughness = 0.8;
	vec3 world_normal = mat3(INV_VIEW_MATRIX) * NORMAL;
	// the snow lying on what faces up (dusting, then patches, then a full cover), the wet darker
	// and glossier
	gnd_weather_surface(albedo, roughness, world_normal, world_position);
	ALBEDO = albedo;
	ROUGHNESS = roughness;
}
```

`gnd_weather_surface_puddled(albedo, roughness, world_normal, world_position, puddling)` takes how
much water the surface would hold standing - a pavement 1, a soil 0.3 or so, a gravel that lets
it through 0 (`gnd_weather_surface()` takes 0.5) - for a
`weather_surface.gdshaderinc` of a weather that draws it, served in this one's place; this one has
none. `gnd_weather_apply()` sets the normal as well: the snow's heaps in the light.

A dense mesh - a terrain - can heap the snow up as well:

```glsl
void vertex() {
	vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	VERTEX += inverse(mat3(MODEL_MATRIX)) * vec3(0.0, gnd_weather_snow_depth(world_normal, world_position), 0.0);
}
```

and light its heaps with `gnd_weather_snow_normal()` in
`fragment()`. It moves vertices, so a box of eight corners would only part its top face from its
sides: keep it to dense meshes. `#define GND_SNOW_MAX_DEPTH` before the include caps how far a
surface is raised however deep the snow lies (1 m), so it does not bury what the game does not.

The snow is reckoned as water: a heavy snowfall lays `snowfall_depth_per_hour` (6 cm of a fresh
snow, 6 mm of water) an hour, as deep as the frost makes it light - a dry powder some 0.07 of the
water's density, a snow about freezing twice that. It settles to some 0.3 over a couple of days;
a rain soaks it and soaked it sinks to a 0.45 slush within the hour, grey and glistening, the rain's
drops dimpling it. It melts `snow_melt_rate` (0.17 mm of water) a degree an hour in still air,
twice that in a 4 m/s wind, and more with the warmth of the rain falling on it: 8 cm of powder goes
in an hour of a downpour at +5 °C. The rain and the melt both soak the ground under it.
`snow_cover_enabled` off, the snow falls and none of it lies, and what lay is gone: a scene that
wants the snowfall without its cover (the demo's "Snow lies on the ground").
The cover is full from some 3 cm.

The rain is water in millimetres: `rain_mm_per_hour` (50) at the full intensity, as its square (a
heavy 0.5 is some 12, a light 0.2 is 2). The first millimetre, and the melt's water, wet the
surfaces through (`wetness` 1) - a downpour in a minute; the rest runs off. The water dries off
`drying_mm_per_hour` (0.3, faster the warmer, and the drier the air: `air_humidity` 0.7 is that rate,
a saturated air dries nothing).

That is `WeatherSimpleGround`, a world's ground model unless another is set:
`WeatherServer.set_ground_model(world, model)` with a `WeatherGroundModel` of your own - its keys of
the weather's state and rates, its `advance()` over the world's hours, `set_ground()`, the ground's
globals it sets (`get_globals()`), what it tells (`get_report()`) and, each frame of a `WeatherNode`,
`process()` with how the rain falls and the snow flies (`get_rain_fall_direction()`,
`get_snow_flight()`). Extending `WeatherSimpleGround` keeps its snow and wet.

The ground's state is in the shader globals `gnd_snow_depth` (m), `gnd_snow_cover`, `gnd_wetness`,
`gnd_rain`, `gnd_snow_wetness` (0 - 1) and `gnd_air_temperature` (°C), for shaders of your own, and in
`WeatherServer.get_weather_state()`; `WeatherServer.set_ground_state(world, {"snow_depth": ...,
"wetness": ...})` sets it, as the node's properties do. A ground model of more sets globals of its
own (`WeatherServer.set_ground_global()`, added where the project does not declare them), for
materials of its own: `weather_surface.gdshaderinc` has the snow lying and the wet. A project whose materials read the ground's state under names of
its own sets `gnd_weather/ground_globals_prefix` (e.g. `game_`: `game_snow_depth`, ...); the
wind's globals keep theirs.

## Puddles

`PuddleSurface3D`: a `mesh` (a plane) and a `mask_texture` whose alpha is the puddle's depth - a
round gradient will do: its shore wanders and its bottom is uneven (`shore_irregularity`,
`shore_scale`), each puddle its own, so it dries into a few smaller ones. It fills with a ground
model's standing water (`puddles`), ripples with the rain's share of the precipitation where it lies (a shelter over it keeps the
ripples off), freezes to a still sheet below 0 °C and goes under the snow. It is opaque, so the
screen-space reflections take it in (it no longer refracts what is under it:
`refraction_strength` and `refraction_mix` are gone).

## Shelters

`PrecipitationVolume` with `precipitation_delta` -1 keeps the rain and the snow out of a box -
a shelter, a porch, a car's interior - the way a roof does: what comes down
through its top stays out, a slanting rain or a blowing snow gets in from the open side. One with
`enclosed` has walls all round, a car's interior: nothing inside it is wet, however flat a gale
blows the snow. The sixteen
nearest the camera are culled exactly in the shaders (`WeatherNode.MAX_PRECIPITATION_EXCLUSION_VOLUMES`),
each given to them only as it moves; others between -1 and 1 thin the precipitation out or add to it
where the camera is (`precipitation_multiplier`, `lightning_multiplier`, `edge_feather`).

## The wind for the vegetation

`weather_wind.gdshaderinc` with `GND_WIND_GLOBALS` gives any shader the weather's wind, in m/s - the
same across the scene, its gusts and lulls over time in its speed:

```glsl
shader_type spatial;
#define GND_WIND_GLOBALS
#include "res://addons/gnd_weather/weather_wind.gdshaderinc"

void vertex() {
	vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wind = gnd_wind_at(world_position);
	// lean with it, the more the higher the vertex
	float height = max(VERTEX.y, 0.0);
	VERTEX += inverse(mat3(MODEL_MATRIX)) * wind * 0.003 * height * height * gnd_wind_strength;
}
```

The wind is set in the **Wind** group: `global_wind_direction`, `global_wind_speed` (m/s, at the
ground), `global_wind_turbulence` (gustiness), `global_wind_gust_size`
(m, for a weather of more's gusts), `precipitation_wind_strength` (what a full rain adds) and
`global_wind_strength` (how hard the vegetation sways - a factor, not a speed). The shader globals:
`gnd_wind_direction`, `gnd_wind_speed`, `gnd_wind_strength`, `gnd_wind_turbulence`, `gnd_wind_time`.
A weather of more - gusts sweeping across the scene - extends `GndWeatherServer` (the `WeatherServer`
autoload's class) and registers its own under that name (`get_wind_gust_strength()`).

The rain and the snow slant with the wind evenly (`weather_wind_steady.gdshaderinc`). A weather of
more draws them with gusts and eddies of its own: `rain_shader` and `snow_shader` - a shader
including its wind (`precipitation_rain_wind()`, `precipitation_snow_wind()`) and then
`precipitation_rain.gdshaderinc` or `precipitation_snow.gdshaderinc`.

## Sound

`precipitation_strength_changed(strength, snow)` and `precipitation_local_strength_changed(strength,
snow)` (less under a shelter): the rain's share is `strength * (1.0 - snow)`, the snow is silent.
`thunder(strength)` with every lightning that thunders, as long after its flash as the sound takes
and the fainter the farther, `lightning_flashed(strength, distance_km)` with every flash,
`wind_changed(speed, direction)`.

## Driven by a weather simulation

The **Storm** group's `lightning_rate` (flashes a minute; below 0 they come of `storm_intensity`) and
`lightning_distance_km` (how far off on average: the flash dimmer, the thunder later - 3 s a
kilometre - and fainter, none beyond 20 km), with `lightning_seed` for the same flashes every time.
`rainbow_intensity` (below 0 the sky's own) sets the Skydome's rainbow; the kinds of cloud are the
sky's own (a Skydome's `clouds_renderer`).

## Season

`latitude` and `set_date(year, month, day)` give `season` (`WeatherNode.Season`: winter, spring,
summer, autumn) and `season_changed`: by the
sun's ecliptic longitude - spring from the March equinox, summer from the June solstice - half a
year round in the southern hemisphere, summer all the year between the tropics.
`WeatherServer.get_season(latitude, year, month, day)` without a node.

## Migrating from the rain-only versions

| Was | Is |
|---|---|
| `RainVolume` | `PrecipitationVolume` |
| `rain_strength_changed(strength)` | `precipitation_strength_changed(strength, snow)` |
| `rain_local_strength_changed(strength)` | `precipitation_local_strength_changed(strength, snow)` |
| `rain_mesh_density`, `rain_probe_max_count`, `rain_probe_distance` (and their `gnd_weather/*` project settings) | `precipitation_mesh_density`, `precipitation_probe_*` |
| `WeatherServer.*rain*` (volumes, probes, participation) | `WeatherServer.*precipitation*` |
| `WeatherServer.get_precipitation_render_field_state()`, `clear_precipitation_render_field_cache()`; `PrecipitationMesh.get_field_state()`, `invalidate_field_cache()`, `get_layer_key()` | none: the layers are lattices the shaders wrap round the camera |
| the snow shader's `camera_position`, `drift` | none (the camera's place from `INV_VIEW_MATRIX`, `view_origin_negated` in a double precision build), `drift_offset` |
| `WeatherServer.set_rain_volume_active_distance()` | `set_precipitation_volume_active_distance()` |
| `WeatherServer.configure_weather_state(world, 11 values)` | `configure_weather_state(world, settings: Dictionary)` |
| `WeatherServer.get_precipitation_wind_strength(fallback)` | `get_precipitation_wind_strength(world, fallback)` |

The rain's own look keeps its `rain_*` names (`near_rain_color`, `rain_specular`, ...), and so do
the puddles' ripples.
