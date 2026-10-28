@tool
class_name WeatherNode
extends Node3D

## The seasons, from the winter
enum Season { WINTER, SPRING, SUMMER, AUTUMN }

## The thunder heard (0 - 1): as long after its flash as the sound takes from the strike, the
## fainter the farther (lightning_distance_km)
signal thunder(strength: float)
## A flash, as bright as it is seen (0 - 1), and how far off it struck in kilometres
signal lightning_flashed(strength: float, distance_km: float)
## The precipitation everywhere (0 - 1) and how much of it is snow (0 rain - 1 snow): the rain's own
## is strength * (1 - snow)
signal precipitation_strength_changed(strength: float, snow: float)
## The same where the camera is, less under a shelter (PrecipitationVolume)
signal precipitation_local_strength_changed(strength: float, snow: float)
signal wind_changed(speed: float, direction: Vector2)
## The date or the latitude reached another season
signal season_changed(season: Season)

const RAIN_STREAK_SHADER := preload("./precipitation_rain.gdshader")
const SNOW_SHADER := preload("./precipitation_snow.gdshader")
## How fast a rain's drops fall, in metres a second (2 - 3 mm drops, a heavy rain's)
const RAIN_DROP_FALL_SPEED := 7.5
const NEAR_FIELD_NAME := "RainNear"
const MID_FIELD_NAME := "RainMid"
const SNOW_NEAR_FIELD_NAME := "SnowNear"
const SNOW_MID_FIELD_NAME := "SnowMid"
const SNOW_FAR_FIELD_NAME := "SnowFar"
## The far snow's grid: cells this many metres across, this many to a side
const SNOW_FAR_CELL := 6.0
const SNOW_FAR_CELLS := 10
## How far below the camera the near and mid snow reach
const SNOW_BELOW_EYE := 2.5
## How much further out than the rain's mid layer the snow's reaches
const SNOW_MID_REACH := 3.0
## A light snow's flakes, of a heavy one's: their fall speed (big loose flakes drifting down some
## third as fast) and how far they sway, as many times wider
const SNOW_LIGHT_FALL_SHARE := 0.35
const SNOW_LIGHT_SWAY_FACTOR := 4.0
## A sleet's flakes, of a dry snow's: wet and heavy, they fall this many times as fast and sway this
## share as wide
const SLEET_FALL_FACTOR := 2.5
const SLEET_SWAY_SHARE := 0.4
## The shaders' TIME rolls over after this many seconds (the project's own)
const TIME_ROLLOVER_SETTING := "rendering/limits/time/time_rollover_secs"
## The weather goes on in ticks of this many seconds, not every frame: it changes over seconds, and
## nothing the camera does needs it - the shaders wrap the precipitation round the camera themselves
const WEATHER_TICK_SECONDS := 0.1
## The rain's lattice is laid again only as its spacing changes by this much (m): a rain thickening
## slowly changes it a little every tick
const RAIN_LATTICE_SPACING_STEP := 0.05
const PRECIPITATION_FIELD_COUNT_REDUCTION_SPACING_SCALE := 2.0
const PRECIPITATION_FIELD_WIDTH_SCALE := 1.5
const LIGHTNING_ROLL_INTERVAL_SEC := 0.1
## The flashes a minute of the fiercest storm (lightning_rate): its flashes as bright as they come
const LIGHTNING_RATE_FULL := 12.0
## How far a strike lies, of lightning_distance_km: from the one share of it to the other
const LIGHTNING_DISTANCE_SPREAD := Vector2(0.4, 1.6)
## How far off a flash lights the sky half as brightly as one overhead, in kilometres
const LIGHTNING_HALF_BRIGHT_KM := 5.0
## How far off the thunder is half as loud as overhead, and beyond how far it is not heard at all
const THUNDER_HALF_LOUD_KM := 3.0
const THUNDER_AUDIBLE_KM := 20.0
## The speed of sound, in kilometres a second: the thunder comes this much later a kilometre
const SOUND_SPEED_KM_PER_SECOND := 0.343
# Must match MAX_EXCLUSIONS in the precipitation shaders.
const MAX_PRECIPITATION_EXCLUSION_VOLUMES := 16

## Takes the WeatherSettings project settings (gnd_weather/*) over this node's own values on ready.
@export var apply_project_settings: bool = false

@export_group("Nodes")
@export_node_path("Node") var skydome_path: NodePath
@export_node_path("WorldEnvironment") var world_environment_path: NodePath:
    set(value):
        world_environment_path = value
        if is_inside_tree():
            _refresh_environment_cache()

@export_group("Weather")
@export_range(0.0, 1.0, 0.001) var precipitation_intensity: float = 0.0:
    set(value):
        precipitation_intensity = clampf(value, 0.0, 1.0)
        if is_inside_tree():
            _push_weather_server_settings()
            _apply_weather_state(true)
            _refresh_editor_preview()
## How much of the precipitation is snow: 0 rain, 1 snow, between them sleet. Unless
## snow_from_temperature works it out of air_temperature instead.
@export_range(0.0, 1.0, 0.001) var precipitation_snow: float = 0.0:
    set(value):
        precipitation_snow = clampf(value, 0.0, 1.0)
        _weather_input_changed()
enum TemperatureUnit { CELSIUS, FAHRENHEIT }
## The unit air_temperature, snow_temperature_max and rain_temperature_min are in; changing it
## converts them, so the temperature stays what it was. The weather works in degrees Celsius.
@export var temperature_unit: TemperatureUnit = TemperatureUnit.CELSIUS:
    set(value):
        if value == temperature_unit:
            return
        var air := get_air_temperature_celsius()
        var snow_max := _to_celsius(snow_temperature_max)
        var rain_min := _to_celsius(rain_temperature_min)
        temperature_unit = value
        air_temperature = _from_celsius(air)
        snow_temperature_max = _from_celsius(snow_max)
        rain_temperature_min = _from_celsius(rain_min)
        notify_property_list_changed()
## Snow below snow_temperature_max, rain above rain_temperature_min, sleet between them - as wet
## snow does, falling half and half at some +1.5 °C
@export var snow_from_temperature: bool = false:
    set(value):
        snow_from_temperature = value
        _weather_input_changed()
## The air's temperature, in temperature_unit
@export_range(-60.0, 60.0, 0.1, "suffix:°C") var air_temperature: float = 10.0:
    set(value):
        air_temperature = value
        _weather_input_changed()
@export_range(-10.0, 10.0, 0.1, "suffix:°C") var snow_temperature_max: float = -0.5:
    set(value):
        snow_temperature_max = value
        _weather_input_changed()
@export_range(-10.0, 10.0, 0.1, "suffix:°C") var rain_temperature_min: float = 3.5:
    set(value):
        rain_temperature_min = value
        _weather_input_changed()
## World seconds the falling snow's share takes to follow a change (most of the way), so a jump of
## the temperature does not switch the snow to rain in a frame; 0 at once
@export_range(0.0, 600.0, 0.1, "suffix:s") var snow_change_seconds: float = 3.0:
    set(value):
        snow_change_seconds = maxf(value, 0.0)
        _weather_input_changed()
@export_range(0.0, 1.0, 0.001) var cloud_density: float = 0.0:
    set(value):
        cloud_density = clampf(value, 0.0, 1.0)
        if is_inside_tree():
            _push_weather_server_settings()
            _apply_weather_state(true)
            _refresh_editor_preview()
@export_range(0.0, 1.0, 0.001) var cloud_overcast_intensity: float = 0.0:
    set(value):
        cloud_overcast_intensity = clampf(value, 0.0, 1.0)
        if is_inside_tree():
            _push_weather_server_settings()
            _apply_weather_state(true)
            _refresh_editor_preview()
## The rainbow in the sky (Skydome's rainbow_intensity), where rain falls in the sunshine; below 0
## the sky's own is left as it is
@export_range(-1.0, 2.0, 0.001) var rainbow_intensity: float = -1.0:
    set(value):
        rainbow_intensity = value
        if is_inside_tree():
            _apply_weather_state(true)
@export_range(0.0, 1.0, 0.001) var storm_intensity: float = 0.0:
    set(value):
        storm_intensity = clampf(value, 0.0, 1.0)
        if is_inside_tree():
            _push_weather_server_settings()
            _apply_weather_state(true)
            _refresh_editor_preview()
@export_range(0.0, 1.0, 0.001) var storm_fog_intensity: float = 0.0:
    set(value):
        storm_fog_intensity = clampf(value, 0.0, 1.0)
        if is_inside_tree():
            _push_weather_server_settings()
            _apply_weather_state(true)
            _refresh_editor_preview()

@export_group("Wind")
## Where the wind blows towards, on the ground plane (x, z); shared by everything the weather drives
## (WeatherServer, the wind shader globals, the rain, the snow, the sky's clouds)
@export var global_wind_direction: Vector2 = Vector2(0.8, 0.3):
    set(value):
        global_wind_direction = value
        if is_inside_tree():
            _push_weather_server_settings()
            _apply_weather_state(true)
## The wind's speed at the ground, in metres a second, before its gusts and the rain's own
@export_range(0.0, 40.0, 0.01, "or_greater", "suffix:m/s") var global_wind_speed: float = 1.0:
    set(value):
        global_wind_speed = maxf(value, 0.0)
        if is_inside_tree():
            _push_weather_server_settings()
            _apply_weather_state(true)
## How gusty it is: 0 a steady wind, 1 gusts and lulls of up to about a quarter of its speed, and
## gusts sweeping across the scene and eddies whirling the rain and the snow about, the more the
## stronger the wind
@export_range(0.0, 4.0, 0.01, "or_greater") var global_wind_turbulence: float = 1.0:
    set(value):
        global_wind_turbulence = maxf(value, 0.0)
        if is_inside_tree():
            _push_weather_server_settings()
            _apply_weather_state(true)
## How long the waves of the gusts sweeping across the scene are, in metres
@export_range(2.0, 200.0, 0.1, "suffix:m") var global_wind_gust_size: float = 40.0:
    set(value):
        global_wind_gust_size = maxf(value, 2.0)
        if is_inside_tree():
            _push_weather_server_settings()
## Metres a second a full rain adds to the wind (snow adds none)
@export_range(0.0, 30.0, 0.01, "suffix:m/s") var precipitation_wind_strength: float = 2.0:
    set(value):
        precipitation_wind_strength = maxf(value, 0.0)
        if is_inside_tree():
            _push_weather_server_settings()
            _refresh_editor_preview()
## How hard the vegetation sways in the wind (the gnd_wind_strength shader global): a factor for the
## grass' and the trees' shaders, not a speed
@export_range(0.0, 10.0, 0.01, "or_greater") var global_wind_strength: float = 4.0:
    set(value):
        global_wind_strength = maxf(value, 0.0)
        if is_inside_tree():
            _push_weather_server_settings()
            _apply_weather_state(true)
## How much of the wind's speed the drops are carried at: falling some 7.5 m/s, they slant as far as
## the wind blows them - 45 degrees in a 7.5 m/s wind, 65 in an 18 m/s gale
@export_range(0.0, 1.0, 0.01) var wind_influence: float = 1.0

@export_group("Precipitation")
## The shaders the rain and the snow are drawn with: a weather's own - one with gusts and eddies in
## its wind - in place of gnd-weather's (precipitation_rain.gdshader, precipitation_snow.gdshader:
## a steady wind), the body of either included after a wind of its own
## (precipitation_rain.gdshaderinc, precipitation_snow.gdshaderinc); none - gnd-weather's
@export var rain_shader: Shader:
    set(value):
        rain_shader = value
        if is_inside_tree():
            _ensure_precipitation_field_nodes()
@export var snow_shader: Shader:
    set(value):
        snow_shader = value
        if is_inside_tree():
            _ensure_precipitation_field_nodes()
## How far above the camera the layers of precipitation are centred
@export var follow_height: float = 7.5
## Half the size of the box about the camera the near layers fill
@export var near_emission_extents: Vector3 = Vector3(4.6, 3.0, 4.6)
## Half the size of the box about the camera the mid layers fill
@export var mid_emission_extents: Vector3 = Vector3(4.2, 2.8, 4.2)
## How many cells of the field the layers have, relative to the default
@export_range(0.1, 8.0, 0.01) var precipitation_mesh_density: float = 1.0:
    set(value):
        precipitation_mesh_density = maxf(value, 0.1)
        _invalidate_precipitation_lattices()
        _refresh_editor_preview()
## How fast the near layers fall, relative to the kind's speed
@export_range(0.1, 4.0, 0.01) var near_layer_speed_multiplier: float = 1.0
## How fast the mid layers fall, relative to the kind's speed
@export_range(0.1, 4.0, 0.01) var mid_layer_speed_multiplier: float = 0.78
## The mid layers, further from the camera
@export var mid_layer_enabled: bool = true
@export_range(0.0, 1.0, 0.01) var sheltered_volumetric_emission_scale: float = 0.0:
    set(value):
        sheltered_volumetric_emission_scale = clampf(value, 0.0, 1.0)
        if is_inside_tree():
            _push_weather_server_settings()
            _apply_weather_state(true)
            _refresh_editor_preview()
@export_range(0.1, 4.0, 0.05) var near_field_spacing: float = 0.8
@export_range(0.1, 4.0, 0.05) var mid_field_spacing: float = 1.35
@export_range(0.0, 1.0, 0.01) var near_field_jitter: float = 0.38
@export_range(0.0, 1.0, 0.01) var mid_field_jitter: float = 0.48
@export_group("Weather probes", "weather_probe")
## How far apart the weather probes are, in metres: a lattice of them fixed in the world about the
## camera (WeatherProbes), how much of the precipitation reaches each, its temperature and humidity,
## and the ground at it over time - a few metres is enough, the materials blend between them
@export_range(0.5, 16.0, 0.1, "suffix:m") var weather_probe_cell: float = 2.0:
    set(value):
        weather_probe_cell = maxf(value, 0.5)
        if is_inside_tree():
            _setup_weather_probes()
## How far the probes reach about the camera, in metres (each way the half of it): out of them, the
## open ground's weather
@export var weather_probe_extent: Vector3 = Vector3(128.0, 32.0, 128.0):
    set(value):
        weather_probe_extent = value.max(Vector3.ONE * 8.0)
        if is_inside_tree():
            _setup_weather_probes()
## How often the probes are worked out (seconds of the game's time) - at once as a heat source or a
## volume changes or the camera leaves their middle
@export_range(0.1, 10.0, 0.1, "suffix:s") var weather_probe_seconds: float = 0.5
@export_group("Precipitation")
@export_group("Rain")
## How fast the rain falls
@export_range(1.0, 80.0, 0.1) var base_fall_speed: float = 26.0
@export var near_rain_color: Color = Color(0.72, 0.74, 0.76, 0.08):
    set(value):
        near_rain_color = value
        _sync_precipitation_materials()
        _refresh_editor_preview()
@export var mid_rain_color: Color = Color(0.66, 0.68, 0.72, 0.055):
    set(value):
        mid_rain_color = value
        _sync_precipitation_materials()
        _refresh_editor_preview()
@export_range(0.0, 1.0, 0.01) var near_rain_blur: float = 0.74:
    set(value):
        near_rain_blur = clampf(value, 0.0, 1.0)
        _sync_precipitation_materials()
        _refresh_editor_preview()
@export_range(0.0, 1.0, 0.01) var near_rain_glow: float = 0.28:
    set(value):
        near_rain_glow = clampf(value, 0.0, 1.0)
        _sync_precipitation_materials()
        _refresh_editor_preview()
@export_range(0.0, 1.0, 0.01) var mid_rain_blur: float = 0.22:
    set(value):
        mid_rain_blur = clampf(value, 0.0, 1.0)
        _sync_precipitation_materials()
        _refresh_editor_preview()
@export_range(0.0, 1.0, 0.01) var mid_rain_glow: float = 0.1:
    set(value):
        mid_rain_glow = clampf(value, 0.0, 1.0)
        _sync_precipitation_materials()
        _refresh_editor_preview()
## How bright the rain's streaks are
@export_range(0.0, 1.0, 0.01) var visual_intensity = 0.50:
    set(value):
        visual_intensity = clampf(value, 0.0, 1.0)
        _sync_precipitation_materials()
        _refresh_editor_preview()
@export_range(0.0, 1.0, 0.01) var rain_specular = 0.50:
    set(value):
        rain_specular = clampf(value, 0.0, 1.0)
        _sync_precipitation_materials()
        _refresh_editor_preview()
@export_range(0.0, 1.0, 0.01) var rain_roughness = 0.18:
    set(value):
        rain_roughness = clampf(value, 0.0, 1.0)
        _sync_precipitation_materials()
        _refresh_editor_preview()
@export_range(0.1, 50.0, 0.1) var rain_specular_fade_start = 2.0:
    set(value):
        rain_specular_fade_start = value
        _sync_precipitation_materials()
        _refresh_editor_preview()
@export_range(0.1, 100.0, 0.1) var rain_specular_fade_end = 8.0:
    set(value):
        rain_specular_fade_end = value
        _sync_precipitation_materials()
        _refresh_editor_preview()
@export_group("Snow")
@export var near_snow_color: Color = Color(1.0, 1.0, 1.0, 0.85):
    set(value):
        near_snow_color = value
        _refresh_editor_preview()
@export var mid_snow_color: Color = Color(0.94, 0.96, 1.0, 0.6):
    set(value):
        mid_snow_color = value
        _refresh_editor_preview()
## A flake's size, in metres (the mid layer's are smaller)
@export_range(0.002, 0.08, 0.001, "suffix:m") var snow_flake_size: float = 0.022
@export_range(0.1, 5.0, 0.01, "suffix:m/s") var snow_fall_speed: float = 0.9
## How far the flakes sway to the sides
@export_range(0.0, 1.5, 0.01, "suffix:m") var snow_sway: float = 0.1
## How much of the wind's speed the snow drifts at (near the ground, out of the full wind aloft)
@export_range(0.0, 2.0, 0.01) var snow_wind_drift: float = 0.5
## Flakes to a cell of the field, relative to the default
@export_range(0.1, 4.0, 0.01) var snow_density: float = 1.0
## How much a falling snow fogs the view (the Skydome's fog, or the Environment's without one): 0
## not at all, 1 a heavy snowfall all but hides the world
@export_range(0.0, 1.0, 0.01) var fog_snow_affect: float = 0.5
## How much a downpour greys the distance out, as fog_snow_affect; a light rain hardly does
@export_range(0.0, 1.0, 0.01) var fog_rain_affect: float = 0.5
## Seconds the haze of a snowfall takes to gather most of the way, or to lift
@export_range(0.0, 300.0, 0.1, "suffix:s") var fog_snow_seconds: float = 30.0
## The far snow, a box of 60 m about the camera, which makes a heavy snow thicken into the distance
@export var snow_far_layer_enabled: bool = true

@export_group("Season")
## Where the weather is, in degrees (south negative), and the date: they make the season
@export_range(-90.0, 90.0, 0.01, "suffix:°") var latitude: float = 50.0:
    set(value):
        latitude = clampf(value, -90.0, 90.0)
        _update_season()
@export_range(1, 9999) var date_year: int = 2026:
    set(value):
        date_year = value
        _update_season()
@export_range(1, 12) var date_month: int = 6:
    set(value):
        date_month = clampi(value, 1, 12)
        _update_season()
@export_range(1, 31) var date_day: int = 21:
    set(value):
        date_day = clampi(value, 1, 31)
        _update_season()
## The season of the date at the latitude (WeatherServer.get_season()), read only
@export var season: Season:
    get:
        return _season
    set(value):
        pass

@export_group("Ground")
## World seconds a second of the weather on the ground takes (the game's time scale): how fast the
## snow settles and melts and the ground wets and dries
@export_range(0.0, 1000.0, 0.01, "or_greater") var weather_time_scale: float = 1.0:
    set(value):
        weather_time_scale = maxf(value, 0.0)
        _weather_input_changed()
## How deep the snow lies, on the average: set it to start a scenario under snow; the weather
## changes it
@export_range(0.0, 3.0, 0.001, "or_greater", "suffix:m") var snow_depth: float = 0.0:
    set(value):
        snow_depth = maxf(value, 0.0)
        if not _syncing_ground:
            _push_ground_state({"snow_depth": snow_depth})
## How much of the ground the snow covers (0 - 1): full from some 3 cm of it
## (WeatherServer.SNOW_COVER_DEPTH); setting it sets the depth that covers that much
@export_range(0.0, 1.0, 0.001) var snow_cover: float = 0.0:
    set(value):
        snow_cover = clampf(value, 0.0, 1.0)
        if not _syncing_ground:
            _push_ground_state({"snow_cover": snow_cover})
## How wet the ground is (0 - 1); the weather changes it
@export_range(0.0, 1.0, 0.001) var wetness: float = 0.0:
    set(value):
        wetness = clampf(value, 0.0, 1.0)
        if not _syncing_ground:
            _push_ground_state({"wetness": wetness})
## Whether the snow lies on the ground: off, it falls and none of it lies, and what lay is gone - a
## scene that wants the snowfall without its cover
@export var snow_cover_enabled: bool = true:
    set(value):
        snow_cover_enabled = value
        _weather_input_changed()
## How deep a heavy snowfall lies in a world hour (a heavy one is some 3 - 8 cm)
@export_range(0.0, 0.5, 0.001, "suffix:m/h") var snowfall_depth_per_hour: float = 0.06:
    set(value):
        snowfall_depth_per_hour = maxf(value, 0.0)
        _weather_input_changed()
## The snow's water a degree above freezing melts in a world hour, in still air (a wind of 4 m/s
## doubles it): a settled snow's measured 3 - 6 mm of water a degree a day; a rain falling on it
## melts more with its own warmth
@export_range(0.0, 2.0, 0.001, "suffix:mm/h") var snow_melt_rate: float = 0.17:
    set(value):
        snow_melt_rate = maxf(value, 0.0)
        _weather_input_changed()
## The rain a full precipitation_intensity brings, in millimetres an hour: a downpour's 50 (heavy
## rain is 8 and more, violent 50); it goes as the square of the intensity, so 0.5 is some 12 and a
## light 0.2 is 2, which the ground soaks up without a puddle
@export_range(0.0, 200.0, 0.1, "suffix:mm/h") var rain_mm_per_hour: float = 50.0:
    set(value):
        rain_mm_per_hour = maxf(value, 0.0)
        _weather_input_changed()
## The water that dries off the surfaces and the puddles in a world hour at 10 degrees in still air of
## air_humidity 0.7: as fast as the air's vapour pressure falls short of the saturated - some 6 times
## faster at 40 degrees - and faster in a wind
@export_range(0.0, 5.0, 0.01, "suffix:mm/h") var drying_mm_per_hour: float = 0.3:
    set(value):
        drying_mm_per_hour = maxf(value, 0.0)
        _weather_input_changed()
## How humid the air is (0 - 1): the drier, the faster the ground dries - drying_mm_per_hour is
## at 0.7, a mild day's; a saturated air dries nothing
@export_range(0.0, 1.0, 0.001) var air_humidity: float = 0.7:
    set(value):
        air_humidity = clampf(value, 0.0, 1.0)
        _weather_input_changed()

@export_group("Storm")
@export var lightning_enabled: bool = true:
    set(value):
        lightning_enabled = value
        if is_inside_tree():
            _push_weather_server_settings()
            _apply_weather_state(true)
            _refresh_editor_preview()
@export_range(0.1, 30.0, 0.1) var lightning_min_interval: float = 3.2:
    set(value):
        lightning_min_interval = maxf(value, 0.1)
        if is_inside_tree():
            _push_weather_server_settings()
            _apply_weather_state(true)
            _refresh_editor_preview()
@export_range(0.1, 30.0, 0.1) var lightning_max_interval: float = 9.5:
    set(value):
        lightning_max_interval = maxf(value, 0.1)
        if is_inside_tree():
            _push_weather_server_settings()
            _apply_weather_state(true)
            _refresh_editor_preview()
@export_range(0.1, 20.0, 0.01) var lightning_flash_decay: float = 4.8:
    set(value):
        lightning_flash_decay = maxf(value, 0.1)
        if is_inside_tree():
            _push_weather_server_settings()
            _apply_weather_state(true)
            _refresh_editor_preview()
## Flashes a minute, for a weather simulation to set (seen where the camera is, fewer under a
## shelter); below 0 they come of storm_intensity, lightning_max_interval - lightning_min_interval
## apart
@export_range(-1.0, 60.0, 0.01) var lightning_rate: float = -1.0:
    set(value):
        lightning_rate = value
        if is_inside_tree():
            _apply_weather_state(true)
## How far off the strikes are, on average, in kilometres: the farther, the dimmer the flash and the
## later and fainter its thunder; 0 - overhead
@export_range(0.0, 50.0, 0.01, "suffix:km") var lightning_distance_km: float = 0.0:
    set(value):
        lightning_distance_km = maxf(value, 0.0)
## The flashes' own sequence: with one seed the same flashes come every time; 0 - others each run
@export var lightning_seed: int = 0:
    set(value):
        lightning_seed = value
        _seed_lightning()
@export_range(0.1, 20.0, 0.1) var thunder_lock_min_duration: float = 2.4:
    set(value):
        thunder_lock_min_duration = maxf(value, 0.1)
        if thunder_lock_max_duration < thunder_lock_min_duration:
            thunder_lock_max_duration = thunder_lock_min_duration
@export_range(0.1, 20.0, 0.1) var thunder_lock_max_duration: float = 4.8:
    set(value):
        thunder_lock_max_duration = maxf(value, thunder_lock_min_duration)
@export_range(0.1, 8.0, 0.01) var storm_intensity_exponent: float = 2.2:
    set(value):
        storm_intensity_exponent = maxf(value, 0.1)
        if is_inside_tree():
            _apply_weather_state(true)
            _refresh_editor_preview()
@export var storm_intensity_curve: Curve:
    set(value):
        storm_intensity_curve = value
        if is_inside_tree():
            _apply_weather_state(true)
            _refresh_editor_preview()

var _rain_near: PrecipitationMesh
var _rain_mid: PrecipitationMesh
var _snow_near: PrecipitationMesh
var _snow_mid: PrecipitationMesh
var _snow_far: PrecipitationMesh
# the Environment's own fog, which the snow thickens when there is no Skydome to do it
var _environment_fog_saved: bool = false
# the haze as it is, gathering towards the snowfall's or lifting
var _snow_haze: float = 0.0
var _environment_fog_enabled: bool = false
var _environment_fog_density: float = 0.0
# The wind carries the flakes TIME * its flight less this offset, taken up as the flight changes so
# that none moves; the flight it was taken for
var _snow_drift_offset: Vector3 = Vector3.ZERO
var _snow_flight: Vector3 = Vector3.ZERO
# the weather's ticks (WEATHER_TICK_SECONDS), a lightning flash dying away, and the wind Skydome's
# clouds were last given (its direction, its speed)
var _weather_tick: Timer
var _lightning_tween: Tween
var _skydome_wind: Vector3 = Vector3(INF, INF, INF)
# the weather probes (none without a RenderingDevice), how long since they were worked out, and
# whether they must be at once
var _weather_probes: WeatherProbes
var _weather_probes_elapsed: float = INF
var _weather_probes_dirty: bool = true
# the probes' textures stand on the GPU and are the materials' (WeatherProbes.textures_created)
var _weather_probes_created: bool = false
# whether the materials read the probes (gnd_weather_probes_enabled, weather_probes_enabled)
var _weather_probes_shown: bool = false
# The flakes fall TIME * their speed less this offset, taken up as the speed changes so that none
# moves: TIME * the new speed alone moved every flake by the whole time it had snowed, up into the
# sky as a sleet turned to snow. The speed it was taken for, -1 none yet
var _snow_fall_offset: float = 0.0
var _snow_fall_speed: float = -1.0
# The rain's streaks the same way, in their cycles
var _rain_flow_offset: float = 0.0
var _rain_flow_speed: float = -1.0
# The air the wind carries the rain's gusts and swirls in moves TIME * the wind less this offset,
# taken up as the wind changes so that they go on where they were; the wind it was taken for
var _rain_wind_offset: Vector2 = Vector2.ZERO
var _rain_wind: Vector2 = Vector2.ZERO
var _current_snow_fraction: float = 0.0
var _syncing_ground: bool = false
var _season: Season = Season.SUMMER
var _setting_date: bool = false
var _last_emitted_snow: float = -1.0
var _last_emitted_local_snow: float = -1.0
var _near_precipitation_debug_material: StandardMaterial3D
var _mid_precipitation_debug_material: StandardMaterial3D
var _precipitation_mesh_debug_preview_enabled: bool = false
var _environment: Environment
var _current_global_precipitation: float = 0.0
var _current_cloud_density: float = 0.0
var _current_cloud_overcast_intensity_input: float = 0.0
var _current_storm_intensity_input: float = 0.0
var _current_storm_fog_intensity_input: float = 0.0
var _current_local_precipitation: float = 0.0
var _current_storm_factor: float = 0.0
var _current_lightning_flash: float = 0.0
var _current_shelter_factor: float = 0.0
var _current_local_emission_scale: float = 1.0
var _lightning_activity: float = 0.0
var _lightning_roll_timer: float = 0.0
# how long until the next thunder may come, in seconds: counted by the frames as the thunder on its
# way is, so a seeded storm thunders the same
var _thunder_lock_seconds: float = 0.0
var _lightning_rng := RandomNumberGenerator.new()
# the thunder on its way: the seconds until it is heard (x) and how loud (y)
var _thunder_coming: Array[Vector2] = []

var _last_emitted_precipitation_strength: float = -1.0
var _last_emitted_local_precipitation_strength: float = -1.0
var _last_emitted_wind_speed: float = -1.0
var _last_emitted_wind_direction: Vector2 = Vector2(INF, INF)
var _editor_preview_camera_id: int = 0
var _editor_preview_camera_transform: Transform3D = Transform3D.IDENTITY
var _editor_preview_camera_transform_valid: bool = false
var _precipitation_mesh_debug_near_tint: Color = Color.BLACK
var _precipitation_mesh_debug_mid_tint: Color = Color.BLACK


func _notification(what: int) -> void:
    if what == NOTIFICATION_ENTER_WORLD:
        _refresh_environment_cache()
        if Engine.is_editor_hint():
            call_deferred("_refresh_editor_preview")
    elif what == NOTIFICATION_POST_ENTER_TREE:
        if Engine.is_editor_hint():
            call_deferred("_refresh_editor_preview")


func _ready() -> void:
    if apply_project_settings:
        for property in WeatherSettings.PROPERTIES:
            # keep what the property was initialised with where the setting does not exist,
            # which is every exported build (see WeatherSettings.get_value())
            set(property, WeatherSettings.get_value(property, get(property)))
    _refresh_environment_cache()
    _seed_lightning()
    _push_weather_server_settings()
    var ground := {"snow_depth": snow_depth, "wetness": wetness}
    # a scene saved with the cover alone
    if snow_depth < snow_cover * WeatherServer.SNOW_COVER_DEPTH:
        ground["snow_cover"] = snow_cover
    _push_ground_state(ground)
    _push_precipitation_volume_reach()
    _ensure_precipitation_field_nodes()
    _setup_weather_probes()
    _apply_weather_state(true)
    _weather_tick = Timer.new()
    _weather_tick.wait_time = WEATHER_TICK_SECONDS
    _weather_tick.timeout.connect(_on_weather_tick)
    add_child(_weather_tick, false, Node.INTERNAL_MODE_BACK)
    _weather_tick.start()


func _enter_tree() -> void:
    if not WeatherServer.precipitation_volumes_moved.is_connected(_on_precipitation_volumes_moved):
        WeatherServer.precipitation_volumes_moved.connect(_on_precipitation_volumes_moved)
    if not WeatherServer.heat_sources_changed.is_connected(_on_heat_sources_changed):
        WeatherServer.heat_sources_changed.connect(_on_heat_sources_changed)
    if not WeatherServer.ground_state_set.is_connected(_on_ground_state_set):
        WeatherServer.ground_state_set.connect(_on_ground_state_set)
    # back in the tree: its probes, let go of as it left it
    if is_node_ready() and _weather_probes == null:
        _setup_weather_probes()


func _exit_tree() -> void:
    if WeatherServer.precipitation_volumes_moved.is_connected(_on_precipitation_volumes_moved):
        WeatherServer.precipitation_volumes_moved.disconnect(_on_precipitation_volumes_moved)
    if WeatherServer.heat_sources_changed.is_connected(_on_heat_sources_changed):
        WeatherServer.heat_sources_changed.disconnect(_on_heat_sources_changed)
    if WeatherServer.ground_state_set.is_connected(_on_ground_state_set):
        WeatherServer.ground_state_set.disconnect(_on_ground_state_set)
    _invalidate_precipitation_lattices()
    if _weather_probes != null:
        # the materials let go of the textures before their GPU textures go
        WeatherServer.set_ground_global(WeatherServer.WEATHER_PROBES_ENABLED_GLOBAL, 0.0)
        WeatherServer.set_ground_global(WeatherServer.WEATHER_GROUND_GLOBAL, null)
        WeatherServer.set_ground_global(WeatherServer.WEATHER_PROBES_GLOBAL, null)
        for mesh in _get_precipitation_meshes():
            mesh.set_shader_parameter(&"weather_probes_enabled", false)
            mesh.set_shader_parameter(&"weather_probes", null)
        _weather_probes.release()
        _weather_probes = null
        _weather_probes_created = false
        _weather_probes_shown = false
    # the Environment gets the fog it had before the snow
    var environment := _get_environment()
    if _environment_fog_saved and environment != null:
        environment.fog_enabled = _environment_fog_enabled
        environment.fog_density = _environment_fog_density
        _environment_fog_saved = false
    _clear_thunder_lock()
    WeatherServer.clear_weather_observer_sample(get_world_3d())
    WeatherServer.clear_weather_state(get_world_3d())
    var skydome := _get_skydome()
    if skydome:
        skydome.set_sky_param(&"clouds_coverage", 0.0)
        #skydome.cloud_overcast_intensity = -1.0
        #skydome.cloud_shadow_intensity = 0.0
        skydome.set_sky_param(&"fog_density", 0.0)
        #skydome.local_emission_scale = 1.0
        skydome.set_sky_param(&"lightning_flash", 0.0)


## The weather's tick: it goes on by WEATHER_TICK_SECONDS of the game's time, and the precipitation's
## parameters follow it only where it changed
func _on_weather_tick() -> void:
    var delta := WEATHER_TICK_SECONDS
    _advance_snow_haze(delta)
    _update_follow_position()
    _update_weather_observer()
    WeatherServer.update_weather_state(get_world_3d(), delta)
    _sync_weather_state()
    _emit_current_wind_changed()
    _update_lightning(delta)
    _update_precipitation_rendering()
    WeatherServer.get_ground_model(get_world_3d()).process(self, delta)
    _push_weather_state()
    _update_weather_probes(delta)


func set_precipitation_intensity(value: float) -> void:
    precipitation_intensity = value


func set_precipitation_snow(value: float) -> void:
    precipitation_snow = value


func set_date(year: int, month: int, day: int) -> void:
    _setting_date = true
    date_year = year
    date_month = month
    date_day = day
    _setting_date = false
    _update_season()


func get_season() -> Season:
    return season


func _update_season() -> void:
    if _setting_date:
        return
    var next := WeatherServer.get_season(latitude, date_year, date_month, date_day)
    if next == _season:
        return
    _season = next
    season_changed.emit(_season)


## In temperature_unit
func set_air_temperature(value: float) -> void:
    air_temperature = value


## In degrees Celsius, whatever temperature_unit is
func set_air_temperature_celsius(value: float) -> void:
    air_temperature = _from_celsius(value)


## How much of what falls now is snow (0 - 1): get_snow_fraction(), come round to over
## snow_change_seconds
func get_falling_snow_fraction() -> float:
    return _current_snow_fraction


## How much of the precipitation is snow (0 - 1): precipitation_snow, or out of air_temperature
func get_snow_fraction() -> float:
    if not snow_from_temperature:
        return precipitation_snow
    return get_snow_fraction_at(get_air_temperature_celsius())


## How much of the precipitation is snow at an air's temperature (degrees Celsius)
func get_snow_fraction_at(celsius: float) -> float:
    var snow_max := _to_celsius(snow_temperature_max)
    var rain_min := maxf(_to_celsius(rain_temperature_min), snow_max + 0.01)
    return 1.0 - _smooth_factor(celsius, snow_max, rain_min)


func get_air_temperature_celsius() -> float:
    return _to_celsius(air_temperature)


## A temperature in temperature_unit, in degrees Celsius
func _to_celsius(value: float) -> float:
    return (value - 32.0) * 5.0 / 9.0 if temperature_unit == TemperatureUnit.FAHRENHEIT else value


func _from_celsius(value: float) -> float:
    return value * 9.0 / 5.0 + 32.0 if temperature_unit == TemperatureUnit.FAHRENHEIT else value


func _validate_property(property: Dictionary) -> void:
    if property["name"] == "season":
        property["usage"] |= PROPERTY_USAGE_READ_ONLY
        # worked out, not stored
        property["usage"] &= ~PROPERTY_USAGE_STORAGE
        return
    # the temperatures' ranges and suffix follow temperature_unit
    var ranges := {&"air_temperature": Vector2(-60.0, 60.0), &"snow_temperature_max": Vector2(-10.0, 10.0),
        &"rain_temperature_min": Vector2(-10.0, 10.0)}
    var name := StringName(property["name"])
    if not ranges.has(name):
        return
    var limits: Vector2 = ranges[name]
    if temperature_unit == TemperatureUnit.FAHRENHEIT:
        property["hint_string"] = "%.1f,%.1f,0.1,suffix:°F" % [limits.x * 1.8 + 32.0, limits.y * 1.8 + 32.0]
    else:
        property["hint_string"] = "%.1f,%.1f,0.1,suffix:°C" % [limits.x, limits.y]


func _push_ground_state(ground: Dictionary) -> void:
    if is_inside_tree():
        WeatherServer.set_ground_state(get_world_3d(), ground)


func _weather_input_changed() -> void:
    if is_inside_tree():
        _push_weather_server_settings()
        _apply_weather_state(true)
        _refresh_editor_preview()


func set_cloud_density(value: float) -> void:
    cloud_density = value


func set_cloud_overcast_intensity(value: float) -> void:
    cloud_overcast_intensity = value


func set_storm_intensity(value: float) -> void:
    storm_intensity = value


func set_storm_fog_intensity(value: float) -> void:
    storm_fog_intensity = value


func apply_wind_controls(strength_ratio: float, direction: Vector2) -> void:
    global_wind_direction = direction.normalized()
    global_wind_speed = lerpf(0.15, 3.0, strength_ratio)
    global_wind_strength = lerpf(0.4, 5.0, strength_ratio)
    apply_now()


func apply_now() -> void:
    _sync_weather_state(true)
    _emit_current_wind_changed()
    _apply_weather_state(true)


func _refresh_editor_preview() -> void:
    if not Engine.is_editor_hint() or not is_inside_tree():
        return
    _invalidate_precipitation_lattices()
    _push_weather_server_settings()
    _push_precipitation_volume_reach()
    _apply_weather_state(true)


func get_effective_precipitation_intensity() -> float:
    return _current_local_precipitation


func get_precipitation_strength_at_position(world_position: Vector3) -> float:
    return WeatherServer.get_precipitation_participation_strength(
        get_world_3d(),
        world_position,
        _get_global_precipitation_setting()
    )


func get_storm_factor(precipitation_override: float = -1.0) -> float:
    if precipitation_override < 0.0:
        return _current_storm_factor
    return _evaluate_storm_intensity_response(_current_storm_intensity_input)


func _apply_weather_state(force: bool = false) -> void:
    _ensure_precipitation_field_nodes()
    _update_follow_position()
    _update_weather_observer()
    _sync_weather_state(force)
    _update_lightning(0.0, force)
    _update_precipitation_rendering()
    _push_weather_state(force)


func _get_skydome() -> Node:
    if not skydome_path.is_empty():
        return get_node_or_null(skydome_path)

    var root := get_tree().current_scene
    if root != null:
        return root.find_child("Skydome", true, false)
    return null


func _get_world_environment() -> WorldEnvironment:
    if not world_environment_path.is_empty():
        return get_node_or_null(world_environment_path) as WorldEnvironment

    return null


func _get_environment() -> Environment:
    return _environment


func _refresh_environment_cache() -> void:
    var env_node := _get_world_environment()
    if env_node != null:
        _environment = env_node.environment
        return

    var world_3d := get_world_3d()
    _environment = world_3d.environment if world_3d != null else null


## How far about the observer the volumes count for its own queries (the shelters the shaders cull
## exactly, the precipitation where it stands): as far as the precipitation drawn about it
func _push_precipitation_volume_reach() -> void:
    WeatherServer.set_precipitation_volume_active_distance(
        get_world_3d(), maxf(near_emission_extents.length(), mid_emission_extents.length()))
    _invalidate_precipitation_lattices()


## The weather probes made for weather_probe_cell and weather_probe_extent, as they change (none
## without a RenderingDevice: the materials take the open ground's weather then)
func _setup_weather_probes() -> void:
    if not WeatherProbes.is_supported():
        WeatherServer.set_ground_global(WeatherServer.WEATHER_PROBES_ENABLED_GLOBAL, 0.0)
        return
    if _weather_probes == null:
        _weather_probes = WeatherProbes.new()
        _weather_probes.textures_created.connect(_on_weather_probe_textures_created)
    _weather_probes_created = false
    if _weather_probes_shown:
        _weather_probes_shown = false
        WeatherServer.set_ground_global(WeatherServer.WEATHER_PROBES_ENABLED_GLOBAL, 0.0)
        for mesh in _get_precipitation_meshes():
            mesh.set_shader_parameter(&"weather_probes_enabled", false)
    _weather_probes.setup(_get_weather_probe_dims())
    _weather_probes_dirty = true
    _weather_probes_elapsed = INF
    _place_weather_probes(true)


## The probes' textures stand on the GPU: given to the materials, the probes for them from now
func _on_weather_probe_textures_created() -> void:
    if _weather_probes == null:
        return
    _weather_probes_created = true
    WeatherServer.set_ground_global(WeatherServer.WEATHER_GROUND_GLOBAL, _weather_probes.ground_texture)
    WeatherServer.set_ground_global(WeatherServer.WEATHER_PROBES_GLOBAL, _weather_probes.probes_texture)
    WeatherServer.set_ground_global(WeatherServer.WEATHER_PROBE_SIZE_GLOBAL, Vector3(_get_weather_probe_dims()) * weather_probe_cell)
    for mesh in _get_precipitation_meshes():
        mesh.set_shader_parameter(&"weather_probes", _weather_probes.probes_texture)
        mesh.set_shader_parameter(&"weather_probe_size", Vector3(_get_weather_probe_dims()) * weather_probe_cell)
    _weather_probes_dirty = true


## Where the probes stand now, every step-th of them each way (the editor's preview of them)
func get_weather_probe_positions(step: int = 1) -> PackedVector3Array:
    var positions := PackedVector3Array()
    if _weather_probes == null:
        return positions
    var dims := _get_weather_probe_dims()
    var base := _weather_probes.get_base()
    step = maxi(step, 1)
    for x in range(0, dims.x, step):
        for y in range(0, dims.y, step):
            for z in range(0, dims.z, step):
                positions.append((Vector3(base + Vector3i(x, y, z)) + Vector3.ONE * 0.5) * weather_probe_cell)
    return positions


func _get_weather_probe_dims() -> Vector3i:
    return Vector3i((weather_probe_extent / weather_probe_cell).ceil()).max(Vector3i.ONE * 4)


## The probes' window about the camera, moved by whole cells once the camera leaves its middle half:
## its corner given to the materials only then. Returns whether it moved
func _place_weather_probes(force: bool = false) -> bool:
    var follow_target := _get_follow_target()
    if _weather_probes == null or follow_target == null:
        return false
    var dims := _get_weather_probe_dims()
    var camera_cell := Vector3i((follow_target.global_position / weather_probe_cell).floor())
    var base := _weather_probes.get_base()
    var off_middle := (camera_cell - (base + dims / 2)).abs()
    if not force and off_middle.x <= dims.x / 4 and off_middle.y <= dims.y / 4 and off_middle.z <= dims.z / 4:
        return false
    base = camera_cell - dims / 2
    _weather_probes.set_base(base)
    var origin := Vector3(base) * weather_probe_cell
    WeatherServer.set_ground_global(WeatherServer.WEATHER_PROBE_ORIGIN_GLOBAL, origin)
    for mesh in _get_precipitation_meshes():
        mesh.set_shader_parameter(&"weather_probe_origin", origin)
    return true


## The probes worked out on the weather's tick: every weather_probe_seconds, and at once as their
## window moves or a heat source or a volume changes - the heat sources asked then, the ground at
## them gone on by the time since
func _update_weather_probes(delta: float) -> void:
    if _weather_probes == null:
        return
    _weather_probes_elapsed += delta
    var moved := _place_weather_probes()
    if not moved and not _weather_probes_dirty and _weather_probes_elapsed < weather_probe_seconds:
        return
    var world_3d := get_world_3d()
    var state := WeatherServer.get_weather_state(world_3d)
    var rates: Dictionary = WeatherServer.get_ground_model(world_3d).get_probe_rates(state)
    var dims := _get_weather_probe_dims()
    var origin := Vector3(_weather_probes.get_base()) * weather_probe_cell
    var region := AABB(origin, Vector3(dims) * weather_probe_cell)
    var air := get_air_temperature_celsius()
    # the way it falls: the rain's and the snow's, as much of each as falls
    var snow := clampf(_current_snow_fraction, 0.0, 1.0)
    var snow_flight := get_snow_flight()
    var fall := _get_rain_direction(_get_steady_wind_speed(), _get_precipitation_heaviness()).lerp(
        snow_flight.normalized() if snow_flight.length_squared() > 0.0001 else Vector3.DOWN, snow).normalized()
    var params := PackedFloat32Array()
    params.resize(WeatherProbes.Param.COUNT)
    params[WeatherProbes.Param.CELL] = weather_probe_cell
    params[WeatherProbes.Param.FALL_X] = fall.x
    params[WeatherProbes.Param.FALL_Y] = fall.y
    params[WeatherProbes.Param.FALL_Z] = fall.z
    params[WeatherProbes.Param.AIR_TEMPERATURE] = air
    params[WeatherProbes.Param.HUMIDITY] = clampf(air_humidity, 0.0, 1.0)
    params[WeatherProbes.Param.HOURS] = (0.0 if is_inf(_weather_probes_elapsed) else _weather_probes_elapsed) \
            * weather_time_scale / WeatherServer.SECONDS_PER_HOUR
    params[WeatherProbes.Param.RAIN_MM] = float(rates.get("rain_mm", 0.0))
    params[WeatherProbes.Param.SNOW_FALL] = float(rates.get("snow_fall", 0.0))
    params[WeatherProbes.Param.OPEN_WET] = float(rates.get("wet", 0.0))
    params[WeatherProbes.Param.OPEN_SNOW] = float(rates.get("snow", 0.0))
    params[WeatherProbes.Param.OPEN_WATER] = float(rates.get("water", 0.0))
    params[WeatherProbes.Param.WET_FILM] = WeatherServer.WET_FILM_MM
    params[WeatherProbes.Param.MELT_PER_DEGREE] = float(rates.get("melt_per_degree", 0.0))
    params[WeatherProbes.Param.DRYING_MM] = float(rates.get("drying_mm", 0.0))
    _weather_probes.update(params, WeatherServer.get_precipitation_volumes_packed(world_3d, region),
        WeatherServer.get_heat_sources(world_3d, region))
    # the materials read them once they have the textures and the probes in them
    if _weather_probes_created != _weather_probes_shown:
        _weather_probes_shown = _weather_probes_created
        WeatherServer.set_ground_global(WeatherServer.WEATHER_PROBES_ENABLED_GLOBAL, 1.0 if _weather_probes_shown else 0.0)
        for mesh in _get_precipitation_meshes():
            mesh.set_shader_parameter(&"weather_probes_enabled", _weather_probes_shown)
    _weather_probes_elapsed = 0.0
    _weather_probes_dirty = false


func _on_heat_sources_changed(world_3d: World3D) -> void:
    if world_3d == get_world_3d():
        _weather_probes_dirty = true


## The open ground set: the ground at the probes laid anew from it at once
func _on_ground_state_set(world_3d: World3D) -> void:
    if world_3d == get_world_3d() and _weather_probes != null:
        _weather_probes.reset_ground()
        _weather_probes_dirty = true


func _push_weather_server_settings() -> void:
    WeatherServer.configure_global_wind(
        global_wind_direction,
        global_wind_speed,
        global_wind_strength,
        global_wind_turbulence,
        global_wind_gust_size
    )
    WeatherServer.configure_weather_state(get_world_3d(), {
        "precipitation_intensity": precipitation_intensity,
        "snow_fraction": get_snow_fraction(),
        "snow_change_seconds": snow_change_seconds,
        "air_temperature": get_air_temperature_celsius(),
        "time_scale": weather_time_scale,
        "snow_cover_enabled": snow_cover_enabled,
        "snowfall_depth_per_hour": snowfall_depth_per_hour,
        "snow_melt_rate": snow_melt_rate,
        "rain_mm_per_hour": rain_mm_per_hour,
        "drying_mm_per_hour": drying_mm_per_hour,
        "air_humidity": air_humidity,
        "cloud_density": cloud_density,
        "cloud_overcast_intensity": cloud_overcast_intensity,
        "storm_intensity": storm_intensity,
        "storm_fog_intensity": storm_fog_intensity,
        "precipitation_wind_strength": precipitation_wind_strength,
        "sheltered_volumetric_emission_scale": sheltered_volumetric_emission_scale,
        "lightning_enabled": lightning_enabled,
        "lightning_min_interval": lightning_min_interval,
        "lightning_max_interval": lightning_max_interval,
        "lightning_flash_decay": lightning_flash_decay,
    })


func _update_weather_observer() -> void:
    var follow_target := _get_follow_target()
    if follow_target == null:
        WeatherServer.clear_weather_observer_sample(get_world_3d())
        return

    WeatherServer.set_weather_observer_sample(get_world_3d(), follow_target.global_position)


func _sync_weather_state(force: bool = false) -> void:
    var state := _get_server_weather_state(force)
    if state.is_empty():
        return
    _apply_weather_state_snapshot(state)


func _apply_weather_state_snapshot(state: Dictionary) -> void:
    var precipitation_was := Vector3(_current_global_precipitation, _current_local_precipitation, _current_snow_fraction)
    _current_global_precipitation = clampf(float(state.get("global_precipitation", precipitation_intensity)), 0.0, 1.0)
    _current_cloud_density = clampf(float(state.get("cloud_density", cloud_density)), 0.0, 1.0)
    _current_cloud_overcast_intensity_input = clampf(float(state.get("cloud_overcast_intensity_input", cloud_overcast_intensity)), 0.0, 1.0)
    _current_storm_intensity_input = clampf(float(state.get("storm_intensity_input", storm_intensity)), 0.0, 1.0)
    _current_storm_fog_intensity_input = clampf(float(state.get("storm_fog_intensity_input", storm_fog_intensity)), 0.0, 1.0)
    _current_local_precipitation = clampf(float(state.get("local_precipitation", _current_global_precipitation)), 0.0, 1.0)
    _current_snow_fraction = clampf(float(state.get("snow_fraction", get_snow_fraction())), 0.0, 1.0)
    # the fall's and the flow's speeds only as what falls changed
    if not precipitation_was.is_equal_approx(
            Vector3(_current_global_precipitation, _current_local_precipitation, _current_snow_fraction)):
        _update_precipitation_speeds()
    # the inspector shows the ground as the weather changes it
    _syncing_ground = true
    snow_depth = float(state.get("snow_depth", snow_depth))
    snow_cover = float(state.get("snow_cover", snow_cover))
    wetness = float(state.get("wetness", wetness))
    _syncing_ground = false
    _current_storm_factor = clampf(float(state.get("storm_factor", 0.0)), 0.0, 1.0)
    _current_shelter_factor = clampf(float(state.get("shelter_factor", 0.0)), 0.0, 1.0)
    _current_local_emission_scale = clampf(float(state.get("local_emission_scale", 1.0)), 0.0, 1.0)


func _get_server_weather_state(force_refresh: bool = false) -> Dictionary:
    var world_3d := get_world_3d()
    if world_3d == null:
        return {}

    if force_refresh:
        _push_weather_server_settings()
        WeatherServer.update_weather_state(world_3d, 0.0)

    return WeatherServer.get_weather_state(world_3d)


func _get_global_precipitation_setting() -> float:
    return clampf(precipitation_intensity, 0.0, 1.0)


func _evaluate_storm_intensity_response(intensity: float) -> float:
    var clamped_intensity := clampf(intensity, 0.0, 1.0)
    if storm_intensity_curve != null:
        return clampf(storm_intensity_curve.sample_baked(clamped_intensity), 0.0, 1.0)
    return clampf(pow(clamped_intensity, storm_intensity_exponent), 0.0, 1.0)


func _update_lightning(delta: float, force: bool = false) -> void:
    var lightning_multiplier := 1.0
    var follow_target := _get_follow_target()
    if follow_target != null:
        lightning_multiplier = WeatherServer.get_precipitation_lightning_multiplier(get_world_3d(), follow_target.global_position)

    var storm_response := _evaluate_storm_intensity_response(_current_storm_intensity_input)
    if lightning_rate >= 0.0:
        storm_response = clampf(lightning_rate / LIGHTNING_RATE_FULL, 0.0, 1.0)
    _lightning_activity = clampf(storm_response * lightning_multiplier, 0.0, 1.0)
    _advance_thunder(delta)

    if force and (not lightning_enabled or _lightning_activity <= 0.02):
        _flash_lightning(0.0)

    var flashes_per_minute := _get_flashes_per_minute(lightning_multiplier)
    if not lightning_enabled or flashes_per_minute <= 0.0:
        _lightning_roll_timer = 0.0
        if force:
            _flash_lightning(0.0)
        return

    if delta <= 0.0:
        return

    _lightning_roll_timer += delta
    var flash_chance := clampf(LIGHTNING_ROLL_INTERVAL_SEC * flashes_per_minute / 60.0, 0.0, 1.0)
    while _lightning_roll_timer >= LIGHTNING_ROLL_INTERVAL_SEC:
        _lightning_roll_timer -= LIGHTNING_ROLL_INTERVAL_SEC
        if _lightning_rng.randf() <= flash_chance:
            _trigger_lightning_pulse(_lightning_activity)


## How many flashes a minute: lightning_rate's, or out of the storm's activity
func _get_flashes_per_minute(lightning_multiplier: float) -> float:
    if lightning_rate >= 0.0:
        return lightning_rate * lightning_multiplier
    if _lightning_activity <= 0.02:
        return 0.0
    var flash_interval := clampf(lerpf(lightning_max_interval, lightning_min_interval, _lightning_activity), 0.1, 60.0)
    return 60.0 / flash_interval


func _seed_lightning() -> void:
    if lightning_seed != 0:
        _lightning_rng.seed = lightning_seed
    else:
        _lightning_rng.randomize()


func _trigger_lightning_pulse(activity: float) -> void:
    var clamped_activity := clampf(activity, 0.0, 1.0)
    var strength_roll := _lightning_rng.randf()
    var min_strength := lerpf(0.03, 0.22, clamped_activity)
    var max_strength := lerpf(0.35, 1.0, clamped_activity)
    var flash_strength := lerpf(min_strength, max_strength, pow(strength_roll, 1.35))
    var distance_km := 0.0
    if lightning_distance_km > 0.0:
        distance_km = lightning_distance_km * lerpf(LIGHTNING_DISTANCE_SPREAD.x, LIGHTNING_DISTANCE_SPREAD.y, _lightning_rng.randf())
    var seen := flash_strength / (1.0 + pow(distance_km / LIGHTNING_HALF_BRIGHT_KM, 2.0))
    _flash_lightning(maxf(_current_lightning_flash, seen))
    lightning_flashed.emit(seen, distance_km)
    if _thunder_lock_seconds > 0.0 or distance_km > THUNDER_AUDIBLE_KM:
        return
    var loud := clampf(flash_strength / (1.0 + distance_km / THUNDER_HALF_LOUD_KM), 0.0, 1.0)
    _start_thunder_lock()
    if distance_km <= 0.0:
        thunder.emit(loud)
    else:
        _thunder_coming.append(Vector2(distance_km / SOUND_SPEED_KM_PER_SECOND, loud))


## The sky lit as bright as flash, dying away at lightning_flash_decay a second: a tween of its own,
## only while it lasts
func _flash_lightning(flash: float) -> void:
    if _lightning_tween != null:
        _lightning_tween.kill()
        _lightning_tween = null
    _set_lightning_flash(flash)
    if flash <= 0.0 or not is_inside_tree():
        return
    _lightning_tween = create_tween()
    _lightning_tween.tween_method(_set_lightning_flash, flash, 0.0, flash / maxf(lightning_flash_decay, 0.1))


func _set_lightning_flash(flash: float) -> void:
    _current_lightning_flash = flash
    var skydome := _get_skydome()
    if skydome != null:
        skydome.set_sky_param(&"lightning_flash", flash)


## The thunder on its way heard when its sound arrives
func _advance_thunder(delta: float) -> void:
    if delta <= 0.0:
        return
    _thunder_lock_seconds = maxf(_thunder_lock_seconds - delta, 0.0)
    if _thunder_coming.is_empty():
        return
    var still_coming: Array[Vector2] = []
    for coming in _thunder_coming:
        coming.x -= delta
        if coming.x <= 0.0:
            thunder.emit(coming.y)
        else:
            still_coming.append(coming)
    _thunder_coming = still_coming


func _start_thunder_lock() -> void:
    _thunder_lock_seconds = _lightning_rng.randf_range(thunder_lock_min_duration, thunder_lock_max_duration)


func _clear_thunder_lock() -> void:
    _thunder_lock_seconds = 0.0
    _thunder_coming.clear()


func _get_follow_target() -> Node3D:
    if Engine.is_editor_hint() and _editor_preview_camera_id != 0:
        var editor_camera := instance_from_id(_editor_preview_camera_id) as Camera3D
        if editor_camera != null:
            return editor_camera

    var viewport := get_viewport()
    if viewport != null:
        var camera := viewport.get_camera_3d()
        if camera != null:
            return camera
    return null


func _ensure_precipitation_field_nodes() -> void:
    _rain_near = _ensure_precipitation_mesh(NEAR_FIELD_NAME, PrecipitationMesh.Kind.RAIN, PrecipitationMesh.Layer.NEAR, _get_rain_shader())
    _rain_mid = _ensure_precipitation_mesh(MID_FIELD_NAME, PrecipitationMesh.Kind.RAIN, PrecipitationMesh.Layer.MID, _get_rain_shader())
    _snow_near = _ensure_precipitation_mesh(SNOW_NEAR_FIELD_NAME, PrecipitationMesh.Kind.SNOW, PrecipitationMesh.Layer.NEAR, _get_snow_shader())
    _snow_mid = _ensure_precipitation_mesh(SNOW_MID_FIELD_NAME, PrecipitationMesh.Kind.SNOW, PrecipitationMesh.Layer.MID, _get_snow_shader())
    _snow_far = _ensure_precipitation_mesh(SNOW_FAR_FIELD_NAME, PrecipitationMesh.Kind.SNOW, PrecipitationMesh.Layer.FAR, _get_snow_shader())
    _sync_precipitation_materials()


func _ensure_precipitation_mesh(
    node_name: String, kind: PrecipitationMesh.Kind, layer: PrecipitationMesh.Layer, shader: Shader
) -> PrecipitationMesh:
    var existing_node := get_node_or_null(node_name)
    if existing_node != null and not (existing_node is PrecipitationMesh):
        remove_child(existing_node)
        existing_node.queue_free()

    var mesh := get_node_or_null(node_name) as PrecipitationMesh
    if mesh == null:
        mesh = PrecipitationMesh.new()
        mesh.name = node_name
        add_child(mesh)
    return mesh.setup(kind, layer, shader)


## Every precipitation layer there is
func _get_precipitation_meshes() -> Array[PrecipitationMesh]:
    var meshes: Array[PrecipitationMesh] = []
    for mesh in [_rain_near, _rain_mid, _snow_near, _snow_mid, _snow_far]:
        if mesh != null:
            meshes.append(mesh)
    return meshes


func _clear_precipitation_meshes() -> void:
    for mesh in _get_precipitation_meshes():
        mesh.clear()


func _sync_precipitation_materials() -> void:
    for mesh in [_rain_near, _rain_mid]:
        if mesh == null:
            continue
        mesh.set_shader_parameter(&"tint", mid_rain_color if mesh.is_mid() else near_rain_color)
        mesh.set_shader_parameter(&"intensity", visual_intensity)
        mesh.set_shader_parameter(&"roughness", rain_roughness)
        mesh.set_shader_parameter(&"specular", rain_specular)
        mesh.set_shader_parameter(&"specular_fade_start", rain_specular_fade_start)
        mesh.set_shader_parameter(&"specular_fade_end", rain_specular_fade_end)


func set_precipitation_mesh_debug_preview(enabled: bool, near_tint: Color, mid_tint: Color) -> void:
    _ensure_precipitation_field_nodes()
    var changed := (
        _precipitation_mesh_debug_preview_enabled != enabled
        or not _precipitation_mesh_debug_near_tint.is_equal_approx(near_tint)
        or not _precipitation_mesh_debug_mid_tint.is_equal_approx(mid_tint)
    )
    if not changed:
        return

    _precipitation_mesh_debug_preview_enabled = enabled
    _precipitation_mesh_debug_near_tint = near_tint
    _precipitation_mesh_debug_mid_tint = mid_tint
    if enabled:
        _ensure_precipitation_debug_materials(near_tint, mid_tint)
    for mesh in _get_precipitation_meshes():
        var debug_material: Material = null
        if enabled:
            debug_material = _mid_precipitation_debug_material if mesh.is_mid() else _near_precipitation_debug_material
        mesh.set_debug_override(debug_material)

    if Engine.is_editor_hint() and is_inside_tree():
        _refresh_editor_preview()


func set_editor_preview_camera(camera: Camera3D) -> void:
    var next_camera_id := camera.get_instance_id() if camera != null else 0
    var next_transform := camera.global_transform if camera != null else Transform3D.IDENTITY
    var changed := _editor_preview_camera_id != next_camera_id
    if not changed and camera != null:
        changed = (
            not _editor_preview_camera_transform_valid
            or not _editor_preview_camera_transform.is_equal_approx(next_transform)
        )
    elif not changed and camera == null:
        changed = _editor_preview_camera_transform_valid

    if not changed:
        return

    _editor_preview_camera_id = next_camera_id
    _editor_preview_camera_transform = next_transform
    _editor_preview_camera_transform_valid = camera != null
    if Engine.is_editor_hint() and is_inside_tree():
        _refresh_editor_preview()


func _ensure_precipitation_debug_materials(near_tint: Color, mid_tint: Color) -> void:
    if _near_precipitation_debug_material == null:
        _near_precipitation_debug_material = StandardMaterial3D.new()
        _near_precipitation_debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        _near_precipitation_debug_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        _near_precipitation_debug_material.no_depth_test = false
        _near_precipitation_debug_material.cull_mode = BaseMaterial3D.CULL_DISABLED
    if _mid_precipitation_debug_material == null:
        _mid_precipitation_debug_material = StandardMaterial3D.new()
        _mid_precipitation_debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        _mid_precipitation_debug_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        _mid_precipitation_debug_material.no_depth_test = false
        _mid_precipitation_debug_material.cull_mode = BaseMaterial3D.CULL_DISABLED

    _near_precipitation_debug_material.albedo_color = near_tint
    _near_precipitation_debug_material.emission_enabled = true
    _near_precipitation_debug_material.emission = near_tint
    _mid_precipitation_debug_material.albedo_color = mid_tint
    _mid_precipitation_debug_material.emission_enabled = true
    _mid_precipitation_debug_material.emission = mid_tint


## A shelter moved (PrecipitationVolume): the shaders take its box as it is now, the probes it on
## their next tick
func _on_precipitation_volumes_moved(world_3d: World3D) -> void:
    if is_inside_tree() and world_3d == get_world_3d():
        _push_precipitation_exclusion_volumes()


## The shelters the shaders cull the precipitation in, exactly: the nearest of them, each as its
## box stands now
func _push_precipitation_exclusion_volumes() -> void:
    var volumes: Array = WeatherServer.get_precipitation_exclusion_volumes(get_world_3d(), MAX_PRECIPITATION_EXCLUSION_VOLUMES)
    var inverse_transforms: Array[Projection] = []
    var half_sizes := PackedVector3Array()
    var enclosed_mask: int = 0
    for index in volumes.size():
        var precipitation_volume := volumes[index] as PrecipitationVolume
        inverse_transforms.append(Projection(precipitation_volume.global_transform.affine_inverse()))
        half_sizes.append(precipitation_volume.get_half_size())
        if precipitation_volume.enclosed:
            enclosed_mask |= 1 << index
    while inverse_transforms.size() < MAX_PRECIPITATION_EXCLUSION_VOLUMES:
        inverse_transforms.append(Projection.IDENTITY)
        half_sizes.append(Vector3.ZERO)

    for mesh in _get_precipitation_meshes():
        mesh.set_exclusions(volumes.size(), inverse_transforms, half_sizes, enclosed_mask)


func _get_rain_shader() -> Shader:
    return rain_shader if rain_shader else RAIN_STREAK_SHADER


func _get_snow_shader() -> Shader:
    return snow_shader if snow_shader else SNOW_SHADER


## The ground set, by whichever of its ground model's keys ground has (WeatherServer.set_ground_state()),
## as a scenario starts or a weather simulation declares it; the node's properties show it at once
func set_ground(ground: Dictionary) -> void:
    if not is_inside_tree():
        return
    WeatherServer.set_ground_state(get_world_3d(), ground)
    _apply_weather_state_snapshot(WeatherServer.get_weather_state(get_world_3d()))


## The light all round the rain's drops take (their shaders leave the engine's ambient light, worked
## out for every pixel of every drop, out): the Environment's as it mixes it - its ambient colour into
## the sky's by ambient_light_sky_contribution, the sky's the fog's light colour (the sky's own as the
## sky draws it) - times its energy; none without an Environment
func get_rain_ambient_light() -> Color:
    var environment := _get_environment()
    if environment == null:
        return Color.BLACK
    var light := environment.ambient_light_color
    match environment.ambient_light_source:
        Environment.AMBIENT_SOURCE_DISABLED:
            return Color.BLACK
        Environment.AMBIENT_SOURCE_BG, Environment.AMBIENT_SOURCE_SKY:
            light = light.lerp(environment.fog_light_color, environment.ambient_light_sky_contribution)
    return light * environment.ambient_light_energy


## The way the rain falls now (world space, any length), the steady wind slanting it as the drawn
## rain's (its gusts are the gust field's, place by place)
func get_rain_fall_direction() -> Vector3:
    return _get_rain_direction(_get_steady_wind_speed(), _current_global_precipitation)


## The way the snow flies now (world space, m/s): the steady wind carrying it, falling at snow_fall_speed
func get_snow_flight() -> Vector3:
    var flight := _get_wind_direction() * _get_steady_wind_speed() * snow_wind_drift
    return Vector3(flight.x, -maxf(snow_fall_speed, 0.1), flight.y)


## The wind's speed without its gusts (the rain's own included), m/s
func get_steady_wind_speed() -> float:
    return _get_steady_wind_speed()


## How much of the precipitation falls in the world now (0 - 1), sheltered or not
func get_global_precipitation() -> float:
    return _current_global_precipitation


func _update_follow_position() -> void:
    var follow_target := _get_follow_target()
    if follow_target == null:
        return

    global_position = follow_target.global_position + Vector3(0.0, follow_height, 0.0)


func _update_precipitation_rendering() -> void:
    var global_intensity := _current_global_precipitation
    var local_intensity := _current_local_precipitation
    var render_intensity := maxf(global_intensity, local_intensity)
    var snow := _current_snow_fraction
    _emit_precipitation_strength_changed(global_intensity, snow)
    _emit_local_precipitation_strength_changed(local_intensity, snow)

    var camera := _get_follow_target() as Camera3D
    if camera == null or render_intensity <= 0.0:
        _clear_precipitation_meshes()
        return

    _push_precipitation_exclusion_volumes()
    # the speeds once, if nothing changed before the first drawing
    if _snow_fall_speed < 0.0:
        _update_precipitation_speeds()
    # sleet is both at once, each as heavy as its share
    var rain_intensity := render_intensity * (1.0 - snow)
    var snow_intensity := render_intensity * snow
    if rain_intensity > 0.0001:
        _update_rain_layers(camera, rain_intensity, global_intensity)
    else:
        for mesh in [_rain_near, _rain_mid]:
            if mesh != null:
                mesh.clear()
    if snow_intensity > 0.0001:
        _update_snow_layers(camera, snow_intensity, global_intensity)
    else:
        for mesh in [_snow_near, _snow_mid, _snow_far]:
            if mesh != null:
                mesh.clear()


## The rain slants and drifts with the steady wind, as the snow does: its gusts are the gust field's,
## which differs from place to place - the gusting wind's speed, the same everywhere and changing at
## every tick, tilted the whole rain at once and, times TIME, threw its gusts and swirls metres aside
func _update_rain_layers(camera: Camera3D, render_intensity: float, _global_intensity: float) -> void:
    var steady_speed := _get_steady_wind_speed()
    var fall_direction := _get_rain_direction(steady_speed, render_intensity)
    var wind := _get_wind_direction()
    if wind.length_squared() > 0.0001:
        wind = wind.normalized() * steady_speed
    if not wind.is_equal_approx(_rain_wind):
        _rain_wind_offset += (wind - _rain_wind) * _get_shader_time()
        _rain_wind = wind
    for mesh in [_rain_near, _rain_mid]:
        if mesh != null:
            mesh.set_shader_parameter(&"fall_direction", fall_direction)
            mesh.set_shader_parameter(&"wind", wind)
            mesh.set_shader_parameter(&"wind_offset", _rain_wind_offset)
            mesh.set_shader_parameter(&"ambient_light", get_rain_ambient_light())
            mesh.set_shader_parameter(&"gust_strength", get_wind_gust_strength())
            mesh.set_shader_parameter(&"gust_scale", global_wind_gust_size)
            mesh.set_shader_parameter(&"turbulence", get_wind_eddy_strength())
    _update_rain_layer(_rain_near, camera, render_intensity, fall_direction, near_emission_extents, near_field_spacing,
        near_field_jitter, near_layer_speed_multiplier)
    if not mid_layer_enabled:
        if _rain_mid != null:
            _rain_mid.clear()
        return
    _update_rain_layer(_rain_mid, camera, render_intensity, fall_direction, mid_emission_extents, mid_field_spacing,
        mid_field_jitter, mid_layer_speed_multiplier)


## A rain layer: its cards on a lattice fixed in the world, extents (half its size) a side, which the
## shader wraps round in a box about the camera - upwind of it as the rain slants, so the drops come
## down past the camera rather than a gale's width downwind of it
func _update_rain_layer(
    mesh: PrecipitationMesh,
    camera: Camera3D,
    rain_intensity: float,
    fall_direction: Vector3,
    extents: Vector3,
    base_spacing: float,
    jitter: float,
    speed_multiplier: float
) -> void:
    if mesh == null:
        return
    var is_mid := mesh.is_mid()
    var layer_intensity: float = _get_layer_intensity(rain_intensity, is_mid)
    # a slanting rain's cards are longer, to reach as far down
    var steepness := clampf(-fall_direction.normalized().y, 0.25, 1.0)
    var upright_height: float = _get_precipitation_field_card_height(extents, layer_intensity, is_mid)
    var card_height: float = upright_height / steepness
    # a downpour is many more drops, not only brighter ones: some 2.8 times as many at the full
    var spacing: float = maxf(snappedf(_get_precipitation_field_spacing(
        base_spacing * lerpf(1.0, 0.6, rain_intensity * rain_intensity), camera), RAIN_LATTICE_SPACING_STEP), 0.1)
    var cells := Vector2i(maxi(roundi(extents.x * 2.0 / spacing), 2), maxi(roundi(extents.z * 2.0 / spacing), 2))
    _lay_lattice(mesh, cells, Vector2(extents.x * 2.0 / float(cells.x), extents.z * 2.0 / float(cells.y)), jitter)
    _update_rain_layer_visuals(mesh, rain_intensity, layer_intensity, speed_multiplier, card_height, spacing)
    mesh.set_shader_parameter(&"box_extents", extents)
    mesh.set_shader_parameter(&"card_center_height", maxf(upright_height * 0.5 - 0.9, 0.0))
    # the streaks as long as on an upright card, not stretched with it
    mesh.set_shader_parameter(&"streak_length_scale", lerpf(0.001, 1.0, pow(clampf(rain_intensity, 0.0, 1.0), 2.1)) * steepness)


## A layer's lattice: cells.x by cells.y instances on cells of cell metres from the world's origin -
## the shader wraps them round the camera - each with its phase, its variation and its detail, moved
## by up to jitter of a cell about its centre; laid again only as it changes
func _lay_lattice(mesh: PrecipitationMesh, cells: Vector2i, cell: Vector2, jitter: float) -> void:
    var lattice := [cells, cell, jitter]
    if mesh.get_meta(&"lattice", []) == lattice:
        if mesh.multimesh != null and mesh.multimesh.visible_instance_count == 0:
            mesh.multimesh.visible_instance_count = mesh.multimesh.instance_count
        return
    var positions := PackedVector3Array()
    var custom_data := PackedColorArray()
    for i in cells.x:
        for j in cells.y:
            var h := absi(hash(Vector3i(i, j, mesh.layer + 10 * mesh.kind)))
            var shift := Vector2(float(h % 89) / 89.0 - 0.5, float(h % 83) / 83.0 - 0.5) * jitter
            positions.append(Vector3((float(i) + 0.5 + shift.x) * cell.x, 0.0, (float(j) + 0.5 + shift.y) * cell.y))
            custom_data.append(Color(float(h % 997) / 997.0, 1.0, float(h % 991) / 991.0, float(h % 983) / 983.0))
    mesh.fill({"positions": positions, "custom_data": custom_data, "count": positions.size()})
    mesh.set_meta(&"lattice", lattice)


func _update_snow_layers(camera: Camera3D, snow_intensity: float, global_intensity: float) -> void:
    # the wind's flight, its offset taken up as it changed so that no flake moves
    var flight := _get_snow_flight_velocity()
    if not flight.is_equal_approx(_snow_flight):
        _snow_drift_offset += (flight - _snow_flight) * _get_shader_time()
        _snow_flight = flight
    _update_snow_layer(_snow_near, camera, snow_intensity, global_intensity, near_emission_extents, near_field_spacing, near_field_jitter, near_layer_speed_multiplier)
    _update_snow_far(camera, snow_intensity)
    if not mid_layer_enabled:
        if _snow_mid != null:
            _snow_mid.clear()
        return
    # the mid snow reaches out further than the rain's mid layer: the heavy snow is made of it beyond
    # the near box, which a shelter over the camera half fills
    var mid_extents := Vector3(mid_emission_extents.x * SNOW_MID_REACH, mid_emission_extents.y, mid_emission_extents.z * SNOW_MID_REACH)
    _update_snow_layer(_snow_mid, camera, snow_intensity, global_intensity, mid_extents, mid_field_spacing * 1.6, mid_field_jitter, mid_layer_speed_multiplier)


func _update_snow_layer(
    mesh: PrecipitationMesh,
    camera: Camera3D,
    snow_intensity: float,
    _base_strength: float,
    extents: Vector3,
    base_spacing: float,
    _jitter: float,
    speed_multiplier: float
) -> void:
    if mesh == null:
        return
    var is_mid := mesh.is_mid()
    # the near flakes whole from the lightest snow - a light one is fewer of them, not fainter
    # (_set_snow_look()'s count) - the mid ones fading in as it thickens into the distance
    var layer_intensity: float = _smooth_factor(snow_intensity, 0.2, 0.8) if is_mid else _smooth_factor(snow_intensity, 0.0, 0.05)
    if layer_intensity <= 0.001:
        mesh.clear()
        return
    var card_height: float = _get_precipitation_field_card_height(extents, layer_intensity, is_mid)
    var spacing: float = _get_precipitation_field_spacing(base_spacing, camera)
    # down to the ground under a standing eye: the rain's streaks reach it from higher up, the flakes
    # have to fall all the way
    var box_center_height := card_height * 0.5 - SNOW_BELOW_EYE
    _update_snow_box(mesh, snow_intensity, layer_intensity, Vector3(extents.x, card_height * 0.5, extents.z),
        box_center_height, maxi(roundi(extents.x * 2.0 / spacing), 2), 0.8 if is_mid else 1.6, 0.6 if is_mid else 1.0,
        speed_multiplier, mid_snow_color if is_mid else near_snow_color, 0.0 if is_mid else 1.0)


## The far snow: thinner and larger flakes in a box of SNOW_FAR_CELL * SNOW_FAR_CELLS metres, which
## a heavy snow fills into the distance
func _update_snow_far(_camera: Camera3D, snow_intensity: float) -> void:
    if _snow_far == null:
        return
    var layer_intensity := _smooth_factor(snow_intensity, 0.05, 0.7)
    if not snow_far_layer_enabled or layer_intensity <= 0.001:
        _snow_far.clear()
        return
    var half := SNOW_FAR_CELL * SNOW_FAR_CELLS * 0.5
    _update_snow_box(_snow_far, snow_intensity, layer_intensity, Vector3(half, half * 0.4, half), half * 0.25,
        SNOW_FAR_CELLS, 2.2, 1.6, 0.9, mid_snow_color, 0.0)


## A snow layer: instances on a lattice fixed in the world, one box (box_extents, its half size) of
## it, cells to a side; the shader wraps the flakes round in the box about the camera, so walking
## only moves the box over the same snow. On the field's cells about the camera, which moved with it,
## the flakes - scattered far over the box by the wind - came and went every refresh as cells did.
func _update_snow_box(
    mesh: PrecipitationMesh, snow_intensity: float, layer_intensity: float, box_extents: Vector3,
    box_center_height: float, cells: int, size_scale: float, count_scale: float, speed_multiplier: float,
    tint: Color, detail: float
) -> void:
    var cell := Vector2(box_extents.x * 2.0 / float(cells), box_extents.z * 2.0 / float(cells))
    _lay_lattice(mesh, Vector2i(cells, cells), cell, 0.0)
    _set_snow_look(mesh, snow_intensity, layer_intensity, box_extents, box_center_height, size_scale, count_scale,
        maxf(cell.x, cell.y), speed_multiplier, tint, detail)


## The uniforms of a snow layer: its box (half size, centre above the camera), flakes (size and
## count relative to the near layer's, spread over their cell), fall, drift, eddies and streaks
func _set_snow_look(
    mesh: PrecipitationMesh, snow_intensity: float, layer_intensity: float, box_extents: Vector3,
    box_center_height: float, size_scale: float, count_scale: float, spread: float, speed_multiplier: float,
    tint: Color, detail: float
) -> void:
    mesh.set_shader_parameter(&"tint", tint)
    mesh.set_shader_parameter(&"flake_size", snow_flake_size * size_scale)
    var layer_speed := maxf(speed_multiplier, 0.1)
    mesh.set_shader_parameter(&"fall_speed", _snow_fall_speed * layer_speed)
    mesh.set_shader_parameter(&"fall_offset", _snow_fall_offset * layer_speed)
    mesh.set_shader_parameter(&"box_center_height", box_center_height)
    mesh.set_shader_parameter(&"box_extents", box_extents)
    mesh.set_shader_parameter(&"sway", snow_sway * lerpf(SNOW_LIGHT_SWAY_FACTOR, 1.0, _get_precipitation_heaviness())
        * lerpf(1.0, SLEET_SWAY_SHARE, 1.0 - clampf(_current_snow_fraction, 0.0, 1.0)))
    mesh.set_shader_parameter(&"flight", _snow_flight)
    mesh.set_shader_parameter(&"drift_offset", _snow_drift_offset)
    # eddies grow with the gustiness and the wind: a still snowfall barely, a blizzard by metres
    mesh.set_shader_parameter(&"turbulence", get_wind_eddy_strength())
    # the snow takes the gusts as it takes the wind
    mesh.set_shader_parameter(&"gust_strength", get_wind_gust_strength() * snow_wind_drift)
    mesh.set_shader_parameter(&"gust_scale", global_wind_gust_size)
    mesh.set_shader_parameter(&"layer_alpha", layer_intensity)
    mesh.set_shader_parameter(&"flake_detail", detail)
    # as many flakes as the snow is heavy - a light snow few of them, each whole: the layer's own
    # intensity is full long before it; a quarter of the most at snow_density 1, all of them at 4
    var flakes := lerpf(1.0, float(PrecipitationMesh.SNOW_FLAKES_PER_CARD) * 0.25, snow_intensity) * count_scale * snow_density
    mesh.set_shader_parameter(&"flake_count", clampi(roundi(flakes), 1, PrecipitationMesh.SNOW_FLAKES_PER_CARD))
    mesh.set_shader_parameter(&"cell_spread", spread)


## The snow drifts with the steady wind, its gusts from the gust field, which differs from place to
## place: with the gusting wind's speed, the same everywhere, all the snow sped up and slowed down at
## once, layer by layer
## The way the wind carries the snow now (m/s): along the steady wind, by snow_wind_drift
func _get_snow_flight_velocity() -> Vector3:
    var direction := _get_wind_direction()
    if direction.length_squared() <= 0.0001:
        return Vector3.ZERO
    direction = direction.normalized()
    return Vector3(direction.x, 0.0, direction.y) * _get_steady_wind_speed() * snow_wind_drift


## How heavy the precipitation falls as a whole (0 - 1), not its snow's share: a sleet's few flakes
## fall with it, not drifting like the lightest snow
func _get_precipitation_heaviness() -> float:
    return clampf(maxf(_current_global_precipitation, _current_local_precipitation), 0.0, 1.0)


## How fast the snow falls now (m/s): a light one drifts down slowly, a heavy one falls faster, and a
## sleet's wet flakes the faster the more of it is rain
func _get_snow_fall_speed() -> float:
    var wet := 1.0 - clampf(_current_snow_fraction, 0.0, 1.0)
    return (snow_fall_speed * lerpf(SNOW_LIGHT_FALL_SHARE, 1.0, _get_precipitation_heaviness())
        * lerpf(1.0, SLEET_FALL_FACTOR, wet))


## The shaders' TIME now: the real seconds since the engine started, rolled over as they are
func _get_shader_time() -> float:
    return fposmod(Time.get_ticks_usec() / 1000000.0, float(ProjectSettings.get_setting(TIME_ROLLOVER_SETTING, 3600.0)))


## The fall's and the flow's speeds as the weather has them now, each offset taken up as it changed
## so that nothing falling moves; only then do the shaders' parameters change
func _update_precipitation_speeds() -> void:
    var snow_speed := _get_snow_fall_speed()
    if not is_equal_approx(snow_speed, _snow_fall_speed):
        if _snow_fall_speed >= 0.0:
            _snow_fall_offset += _get_shader_time() * (snow_speed - _snow_fall_speed)
        _snow_fall_speed = snow_speed
    var rain_speed := _get_rain_flow_speed()
    if not is_equal_approx(rain_speed, _rain_flow_speed):
        if _rain_flow_speed >= 0.0:
            _rain_flow_offset += _get_shader_time() * (rain_speed - _rain_flow_speed)
        _rain_flow_speed = rain_speed


## How fast the rain's streaks flow now (their cycles a second), by the rain's share of the
## precipitation: a heavy rain's long streaks cycle slower
func _get_rain_flow_speed() -> float:
    var rain := _get_precipitation_heaviness() * (1.0 - clampf(_current_snow_fraction, 0.0, 1.0))
    return (base_fall_speed / 26.0) * lerpf(18.0, 7.5, pow(rain, 0.7))


## The wind's speed without its gusts over time (the rain's own included)
func _get_steady_wind_speed() -> float:
    return maxf(WeatherServer.get_weather_controlled_wind_speed(get_world_3d()), 0.0)


## The lattices laid again on the next drawing
func _invalidate_precipitation_lattices() -> void:
    for mesh in _get_precipitation_meshes():
        mesh.remove_meta(&"lattice")


func _emit_precipitation_strength_changed(strength: float, snow: float) -> void:
    var clamped_strength := clampf(strength, 0.0, 1.0)
    if absf(_last_emitted_precipitation_strength - clamped_strength) <= 0.0001 and absf(_last_emitted_snow - snow) <= 0.0001:
        return
    _last_emitted_precipitation_strength = clamped_strength
    _last_emitted_snow = snow
    precipitation_strength_changed.emit(clamped_strength, snow)


func _emit_local_precipitation_strength_changed(strength: float, snow: float) -> void:
    var clamped_strength := clampf(strength, 0.0, 1.0)
    if absf(_last_emitted_local_precipitation_strength - clamped_strength) <= 0.0001 and absf(_last_emitted_local_snow - snow) <= 0.0001:
        return
    _last_emitted_local_precipitation_strength = clamped_strength
    _last_emitted_local_snow = snow
    precipitation_local_strength_changed.emit(clamped_strength, snow)


func _emit_current_wind_changed() -> void:
    var world_3d := get_world_3d()
    if world_3d == null:
        return

    var speed := maxf(WeatherServer.get_final_wind_speed(world_3d), 0.0)
    var direction := WeatherServer.get_final_wind_direction(world_3d)
    if direction.length_squared() <= 0.0001:
        direction = Vector2(0.8, 0.3)
    direction = direction.normalized()

    if absf(_last_emitted_wind_speed - speed) <= 0.0001 and _last_emitted_wind_direction.is_equal_approx(direction):
        return

    _last_emitted_wind_speed = speed
    _last_emitted_wind_direction = direction
    wind_changed.emit(speed, direction)


func _smooth_factor(value: float, start: float, end: float) -> float:
    var t := clampf((value - start) / maxf(end - start, 0.0001), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


## The way the drops fall: down at their own speed, sideways at the wind's (they take it up within
## a few metres of falling); it used to stop at some 18 degrees, a drizzle's slant in a gale
func _get_rain_direction(wind_speed_value: float, _rain_intensity: float) -> Vector3:
    var wind_dir := _get_wind_direction()
    var lateral_strength := maxf(wind_speed_value * wind_influence, 0.0) / RAIN_DROP_FALL_SPEED
    return Vector3(wind_dir.x * lateral_strength, -1.0, wind_dir.y * lateral_strength).normalized()


func _get_layer_intensity(intensity: float, is_mid_layer: bool) -> float:
    if is_mid_layer:
        return _smooth_factor(intensity, 0.28, 0.9)
    return _smooth_factor(intensity, 0.0, 0.42)


func _update_rain_layer_visuals(
    mesh: PrecipitationMesh,
    rain_intensity: float,
    layer_intensity: float,
    speed_multiplier: float,
    card_height: float,
    field_spacing: float
) -> void:
    var is_mid := mesh.is_mid()
    mesh.set_card(_get_precipitation_field_visual_width(layer_intensity, is_mid, field_spacing), card_height)
    mesh.set_shader_parameter(&"intensity", visual_intensity)
    mesh.set_shader_parameter(&"roughness", rain_roughness)
    mesh.set_shader_parameter(&"specular", rain_specular)
    mesh.set_shader_parameter(&"specular_fade_start", rain_specular_fade_start)
    mesh.set_shader_parameter(&"specular_fade_end", rain_specular_fade_end)
    mesh.set_shader_parameter(&"tint", mid_rain_color if is_mid else near_rain_color)
    mesh.set_shader_parameter(&"blur_amount", mid_rain_blur if is_mid else near_rain_blur)
    mesh.set_shader_parameter(&"glow_amount", mid_rain_glow if is_mid else near_rain_glow)
    mesh.set_shader_parameter(&"width_softness", lerpf(0.14, 0.24, layer_intensity))
    var timing_intensity := clampf(rain_intensity, 0.0, 1.0)
    var layer_speed := maxf(speed_multiplier, 0.1)
    mesh.set_shader_parameter(&"flow_speed", _rain_flow_speed * layer_speed)
    mesh.set_shader_parameter(&"flow_offset", _rain_flow_offset * layer_speed)
    mesh.set_shader_parameter(&"travel_distance", _get_precipitation_field_travel_distance(card_height, timing_intensity))
    mesh.set_shader_parameter(&"respawn_spread", _get_precipitation_field_respawn_spread(field_spacing))
    mesh.set_shader_parameter(&"streak_length_scale", lerpf(0.001, 1.0, pow(timing_intensity, 2.1)))


func _get_precipitation_field_visual_width(layer_intensity: float, is_mid_layer: bool, field_spacing: float) -> float:
    var streak_width := (
        lerpf(0.006, 0.0105, layer_intensity)
        if not is_mid_layer
        else lerpf(0.005, 0.009, layer_intensity)
    ) * PRECIPITATION_FIELD_WIDTH_SCALE
    if not _precipitation_mesh_debug_preview_enabled:
        return streak_width

    var debug_width_scale := 0.82 if not is_mid_layer else 0.74
    return maxf(streak_width, field_spacing * debug_width_scale)


func _get_precipitation_field_respawn_spread(field_spacing: float) -> float:
    if _precipitation_mesh_debug_preview_enabled:
        return 0.0
    return minf(field_spacing * 0.14, 0.08)


func _get_precipitation_field_travel_distance(card_height: float, rain_intensity: float) -> float:
    var timing_intensity := clampf(rain_intensity, 0.0, 1.0)
    return lerpf(card_height * 0.14, card_height * 1.05, pow(timing_intensity, 1.3))


func _get_precipitation_field_card_height(extents: Vector3, layer_intensity: float, is_mid_layer: bool) -> float:
    var vertical_extent := 2.2 if is_mid_layer else 2.0
    return maxf(follow_height + extents.y * vertical_extent, 6.0)


func _get_precipitation_field_spacing(base_spacing: float, camera: Camera3D = null) -> float:
    var spacing := maxf(
        base_spacing
        * PRECIPITATION_FIELD_COUNT_REDUCTION_SPACING_SCALE
        / sqrt(maxf(precipitation_mesh_density * 4.0, 0.1)),
        0.1
    )
    return maxf(spacing, 0.1)


func _get_wind_direction() -> Vector2:
    return WeatherServer.get_final_wind_direction(get_world_3d())


func _get_wind_speed() -> float:
    return WeatherServer.get_final_wind_speed(get_world_3d())


## How far a full gust shoves what the wind blows about, in metres (weather_wind.gdshaderinc)
func get_wind_gust_strength() -> float:
    return WeatherServer.get_wind_gust_strength(get_world_3d())


## How far the wind's eddies whirl things about, in metres
func get_wind_eddy_strength() -> float:
    return global_wind_turbulence * clampf(_get_steady_wind_speed() / 6.0, 0.05, 2.0) * 0.35


## How much a heavy snow or a downpour takes the view away (0 - 1), as it is now
func get_precipitation_haze() -> float:
    return _snow_haze


## The haze the snowfall and the rain make once it has gathered: a snow's flakes hide more than
## a rain's drops, which grey out the distance in a downpour only
func _get_snow_haze_target() -> float:
    var snowfall := _current_global_precipitation * _current_snow_fraction
    var rainfall := _current_global_precipitation * (1.0 - _current_snow_fraction)
    var snow_haze := clampf(pow(snowfall, 1.5) * 0.75 * fog_snow_affect, 0.0, 1.0)
    var rain_haze := clampf(pow(rainfall, 2.0) * 0.5 * fog_rain_affect, 0.0, 1.0)
    return 1.0 - (1.0 - snow_haze) * (1.0 - rain_haze)


## The haze gathers and lifts over fog_snow_seconds: it followed the snowfall at once, so a
## temperature dropping past freezing threw a fog over everything in a frame
func _advance_snow_haze(delta: float) -> void:
    var target := _get_snow_haze_target()
    if fog_snow_seconds <= 0.0 or Engine.is_editor_hint():
        _snow_haze = target
        return
    _snow_haze = lerpf(_snow_haze, target, 1.0 - exp(-maxf(delta, 0.0) / fog_snow_seconds))
    if absf(_snow_haze - target) < 0.0005:
        _snow_haze = target


## Without a Skydome the snow thickens the Environment's own fog; it gets its fog back as it clears
func _apply_environment_snow_fog() -> void:
    var environment := _get_environment()
    if environment == null:
        return
    var haze := get_precipitation_haze()
    if not _environment_fog_saved:
        if haze <= 0.0001:
            return
        _environment_fog_saved = true
        _environment_fog_enabled = environment.fog_enabled
        _environment_fog_density = environment.fog_density
    environment.fog_enabled = _environment_fog_enabled or haze > 0.0001
    # 0.1 a metre at a full haze: nothing past some 30 m
    environment.fog_density = _environment_fog_density + haze * 0.1
    if haze <= 0.0001:
        environment.fog_enabled = _environment_fog_enabled
        _environment_fog_saved = false


func _push_weather_state(force: bool = false) -> void:
    var skydome := _get_skydome()
    if skydome == null:
        _apply_environment_snow_fog()
        return

    var state := _get_server_weather_state(force)
    if state.is_empty():
        return

    var current_cloud_density := clampf(float(state.get("cloud_density", _current_cloud_density)), 0.0, 1.0)
    var current_cloud_overcast_intensity := clampf(float(state.get("cloud_overcast_intensity_input", _current_cloud_overcast_intensity_input)), 0.0, 1.0)
    var current_fog_intensity := clampf(float(state.get("storm_fog_intensity_input", _current_storm_fog_intensity_input)), 0.0, 1.0)
    var current_cloud_shadow_intensity := clampf(float(state.get("storm_factor", _current_storm_factor)), 0.0, 1.0)
    var local_emission_scale := clampf(float(state.get("local_emission_scale", _current_local_emission_scale)), 0.0, 1.0)
    var final_wind_speed := maxf(float(state.get("final_wind_speed", _get_wind_speed())), 0.0)
    var final_wind_direction := state.get("final_wind_direction", _get_wind_direction()) as Vector2
    if final_wind_direction.length_squared() <= 0.0001:
        final_wind_direction = Vector2(0.8, 0.3)
    final_wind_direction = final_wind_direction.normalized()

    # only what changed: each of these sets Skydome's sky and light up again
    if not is_equal_approx(skydome.get_sky_param(&"clouds_coverage"), current_cloud_density):
        skydome.set_sky_param(&"clouds_coverage", current_cloud_density)
    var wind := Vector3(final_wind_direction.x, final_wind_direction.y, final_wind_speed)
    if not wind.is_equal_approx(_skydome_wind):
        _skydome_wind = wind
        skydome.set_sky_param(&"clouds_wind_direction", final_wind_direction)
        skydome.set_sky_param(&"clouds_wind_strength", final_wind_speed)
        skydome.apply_wind_now()
    #skydome.cloud_overcast_intensity = current_cloud_overcast_intensity
    #skydome.cloud_shadow_intensity = current_cloud_shadow_intensity
    # the storm's fog and the snow's haze together
    skydome.set_sky_param(&"fog_density",
        1.0 - (1.0 - current_fog_intensity) * (1.0 - get_precipitation_haze()))
    #skydome.local_emission_scale = local_emission_scale
    if rainbow_intensity >= 0.0 and not skydome.get_sky_param(&"rainbow_intensity") == rainbow_intensity:
        skydome.set_sky_param(&"rainbow_intensity", rainbow_intensity)
