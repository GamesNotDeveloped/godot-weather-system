@tool
class_name GndWeatherServer
extends Node

## The weather of every world - its state, its ground model, its precipitation volumes and probes,
## the global wind - and the shader globals it sets: the plugin's autoload singleton WeatherServer
## (add_autoload_singleton()), its class GndWeatherServer - an autoload's name is no class's. A game
## of more registers its subclass (extends GndWeatherServer) under the same name in its own project:
## its gusts sweeping across the scene (get_wind_gust_strength(), _apply_weather_controlled_wind()).

## A precipitation volume of world_3d moved, or one came or went: the shaders' shelters (their
## boxes) are taken again then, not every frame
signal precipitation_volumes_moved(world_3d: World3D)

const WIND_DIRECTION_GLOBAL := &"gnd_wind_direction"
const WIND_SPEED_GLOBAL := &"gnd_wind_speed"
const WIND_TIME_GLOBAL := &"gnd_wind_time"
const WIND_DIRECTION_SETTING := &"shader_globals/gnd_wind_direction"
const WIND_SPEED_SETTING := &"shader_globals/gnd_wind_speed"
const WIND_STRENGTH_SETTING := &"shader_globals/gnd_wind_strength"
const WIND_TIME_SETTING := &"shader_globals/gnd_wind_time"
const WIND_TURBULENCE_SETTING := &"shader_globals/gnd_wind_turbulence"
const WIND_PATTERN_SETTING := &"shader_globals/gnd_wind_pattern"
const WIND_STRENGTH_GLOBAL := &"gnd_wind_strength"
const WIND_TURBULENCE_GLOBAL := &"gnd_wind_turbulence"
## The ground's state for materials (weather_surface.gdshaderinc): snow cover and wetness 0 - 1,
## the air's temperature in degrees Celsius, the snow's depth in metres
const SNOW_COVER_GLOBAL := &"gnd_snow_cover"
const SNOW_DEPTH_GLOBAL := &"gnd_snow_depth"
## How wet the lying snow is (0 - 1): soaked by a rain or a thaw, grey slush
const SNOW_WETNESS_GLOBAL := &"gnd_snow_wetness"
const WETNESS_GLOBAL := &"gnd_wetness"
const AIR_TEMPERATURE_GLOBAL := &"gnd_air_temperature"
## The rain falling on the ground (0 - 1, its share of the precipitation)
const RAIN_GLOBAL := &"gnd_rain"
## The ground's globals are named with this prefix instead of gnd_, for a project whose materials
## read the ground's state under names of its own (e.g. "game_": game_snow_depth, ...); the
## wind's keep theirs
const GROUND_GLOBALS_PREFIX_SETTING := "gnd_weather/ground_globals_prefix"
const DEFAULT_GLOBALS_PREFIX := "gnd_"
## The shader globals the weather adds to a project that does not have them (in the editor, and as it
## runs): the ground's WeatherSimpleGround sets. A ground model
## of more adds its own as it sets them (set_ground_global()) - the project of a game drawing them
## declares them
const GROUND_GLOBAL_DEFAULTS := {
    &"gnd_snow_cover": 0.0,
    &"gnd_snow_depth": 0.0,
    &"gnd_snow_wetness": 0.0,
    &"gnd_wetness": 0.0,
    &"gnd_air_temperature": 10.0,
    &"gnd_rain": 0.0,
}
## The snow's depth at which it covers the ground, in metres: below it the ground shows through
## in patches (weather_surface.gdshaderinc has the same)
const SNOW_COVER_DEPTH := 0.03
## The water the surfaces hold before it runs off into the hollows, in millimetres: wet through
## (wetness 1) once it is there
const WET_FILM_MM := 1.0
## The air's humidity drying_mm_per_hour is at (a mild day's), and how many times faster the driest
## air dries the ground
const DRYING_HUMIDITY := 0.7
const DRYING_HUMIDITY_MAX_SPEEDUP := 3.0
## The density, of the water's, a snowfall's depth is reckoned at (snowfall_depth_per_hour); a
## scenario's snow lies at SETTLED_SNOW_DENSITY, a soaked one sinks to WET_SNOW_DENSITY
const REFERENCE_SNOW_DENSITY := 0.1
const SETTLED_SNOW_DENSITY := 0.25
const WET_SNOW_DENSITY := 0.45
const SECONDS_PER_HOUR := 3600.0
const VISIBLE_PRECIPITATION_PROBE_REFERENCE_DISTANCE := 8.0
const PRECIPITATION_FIELD_FEATHER_RENDER_CUTOFF := 0.24
const PRECIPITATION_PROBE_SUPPRESSIVE_FEATHER_BLEND_START := 0.28
const PRECIPITATION_PROBE_SUPPRESSIVE_FEATHER_BLEND_END := 0.94
const PRECIPITATION_FIELD_LOWER_CULL_SAMPLE_FACTORS := [0.18, 0.42]
const PRECIPITATION_FIELD_RESAMPLE_INTERVAL_MSEC := 250
const PRECIPITATION_FIELD_FOOTPRINT_OFFSETS := [
    Vector3.ZERO,
    Vector3(1.0, 0.0, 1.0),
    Vector3(1.0, 0.0, -1.0),
    Vector3(-1.0, 0.0, 1.0),
    Vector3(-1.0, 0.0, -1.0),
]
const WIND_GUST_PRIMARY_RATE := 0.055
const WIND_GUST_SECONDARY_RATE := 0.11
const WIND_GUST_MACRO_RATE := 0.21

var _precipitation_volumes_by_world: Dictionary = {}
var _precipitation_volume_revision_by_world: Dictionary = {}
var _visible_precipitation_probe_fields_by_world: Dictionary = {}
var _visible_precipitation_probe_configs_by_world: Dictionary = {}
var _weather_state_by_world: Dictionary = {}
var _ground_models_by_world: Dictionary = {}
var _active_precipitation_volumes_by_world: Dictionary = {}
var _global_wind_direction: Vector2 = Vector2(0.8, 0.3)
var _global_wind_speed: float = 1.0
var _global_wind_strength: float = 4.0
var _global_wind_turbulence: float = 1.0
var _global_wind_gust_size: float = 40.0


func _make_default_weather_state() -> Dictionary:
    return {
        "precipitation_intensity": 0.0,
        # what is falling now, following snow_target (what the temperature makes of it) over
        # snow_change_seconds of the world's time, so sleet comes on as the air warms instead of at once
        "snow_fraction": 0.0,
        "snow_target": 0.0,
        "snow_change_seconds": 3.0,
        "snow_settled": false,
        "air_temperature": 10.0,
        "cloud_density": 0.0,
        "cloud_overcast_intensity": 0.0,
        "storm_intensity": 0.0,
        "storm_fog_intensity": 0.0,
        "precipitation_wind_strength": 2.0,
        "sheltered_volumetric_emission_scale": 0.0,
        "lightning_enabled": true,
        "lightning_min_interval": 3.2,
        "lightning_max_interval": 9.5,
        "lightning_flash_decay": 4.8,
        "observer_position": Vector3.ZERO,
        "has_observer_sample": false,
        "global_precipitation": 0.0,
        "local_precipitation": 0.0,
        "storm_factor": 0.0,
        "shelter_factor": 0.0,
        "local_emission_scale": 1.0,
        "wind_time": 0.0,
        # the world's time a second of the weather takes; the ground's own keys are its model's
        "time_scale": 1.0,
        "air_humidity": DRYING_HUMIDITY,
        "precipitation_volume_active_distance": INF,
    }


func _ensure_weather_state(world_3d: World3D) -> Dictionary:
    if world_3d == null:
        return {}

    var world_id := world_3d.get_instance_id()
    var state: Dictionary = _weather_state_by_world.get(world_id, {})
    if state.is_empty():
        state = _make_default_weather_state()
        state.merge(get_ground_model(world_3d).get_state_defaults())
        _weather_state_by_world[world_id] = state
    return state


## The model of what the weather leaves on the ground in world_3d (WeatherSimpleGround unless set):
## its ground starts bare, the weather going on over it
func set_ground_model(world_3d: World3D, model: WeatherGroundModel) -> void:
    if world_3d == null or model == null:
        return
    var world_id := world_3d.get_instance_id()
    var previous: WeatherGroundModel = _ground_models_by_world.get(world_id)
    if previous:
        previous.clear()
    _ground_models_by_world[world_id] = model
    var state: Dictionary = _weather_state_by_world.get(world_id, {})
    if not state.is_empty():
        state.merge(model.get_state_defaults(), true)
        _apply_ground_globals(state, model)


func get_ground_model(world_3d: World3D) -> WeatherGroundModel:
    if world_3d == null:
        return null
    var world_id := world_3d.get_instance_id()
    var model: WeatherGroundModel = _ground_models_by_world.get(world_id)
    if model == null:
        model = WeatherSimpleGround.new()
        _ground_models_by_world[world_id] = model
    return model


## The wind's speed the weather's state has, a downpour's own in it (a ground model's)
func get_state_wind_speed(state: Dictionary) -> float:
    return _get_weather_controlled_wind_speed_for_state(state, 1.0)


func _store_weather_state(world_3d: World3D, state: Dictionary) -> void:
    if world_3d == null:
        return
    _weather_state_by_world[world_3d.get_instance_id()] = state


func _refresh_weather_state(world_3d: World3D, state: Dictionary) -> void:
    if world_3d == null or state.is_empty():
        return

    var next_global := clampf(float(state.get("precipitation_intensity", 0.0)), 0.0, 1.0)
    var next_local := next_global
    if bool(state.get("has_observer_sample", false)):
        next_local = get_precipitation_participation_strength(
            world_3d,
            state.get("observer_position", Vector3.ZERO),
            next_global
        )

    var next_storm := clampf(float(state.get("storm_intensity", 0.0)), 0.0, 1.0)
    var next_shelter := 0.0
    if next_global > 0.0001 and next_local < next_global:
        next_shelter = clampf((next_global - next_local) / next_global, 0.0, 1.0)

    state["global_precipitation"] = next_global
    state["local_precipitation"] = next_local
    state["storm_factor"] = next_storm
    state["shelter_factor"] = next_shelter
    state["local_emission_scale"] = lerpf(
        1.0,
        clampf(float(state.get("sheltered_volumetric_emission_scale", 0.0)), 0.0, 1.0),
        next_shelter
    )


func _get_weather_controlled_wind_speed_for_state(state: Dictionary, fallback: float = 1.0) -> float:
    var base_speed := get_global_wind_speed(fallback)
    if state.is_empty():
        return base_speed
    # a downpour brings its wind; a snowfall comes down in still air as often as not, and blowing
    # every flake sideways at a still wind made it fly at the camera instead of falling
    var rain_share := 1.0 - clampf(float(state.get("snow_fraction", 0.0)), 0.0, 1.0)
    var precipitation_boost := clampf(float(state.get("precipitation_intensity", 0.0)), 0.0, 1.0) * maxf(float(state.get("precipitation_wind_strength", 2.0)), 0.0) * rain_share
    return maxf(base_speed + precipitation_boost, 0.0)


func add_precipitation_volume(world_3d: World3D, volume_rid: RID, volume: PrecipitationVolume) -> void:
    if world_3d == null or not volume_rid.is_valid() or volume == null:
        return

    var world_id := world_3d.get_instance_id()
    var world_bucket: Dictionary = _precipitation_volumes_by_world.get(world_id, {})
    world_bucket[volume_rid.get_id()] = volume
    _precipitation_volumes_by_world[world_id] = world_bucket
    _notify_precipitation_volumes_changed(world_3d)


func remove_precipitation_volume(world_3d: World3D, volume_rid: RID) -> void:
    if world_3d == null or not volume_rid.is_valid():
        return

    var world_id := world_3d.get_instance_id()
    var world_bucket: Dictionary = _precipitation_volumes_by_world.get(world_id, {})
    if world_bucket.is_empty():
        return

    world_bucket.erase(volume_rid.get_id())
    if world_bucket.is_empty():
        _precipitation_volumes_by_world.erase(world_id)
    else:
        _precipitation_volumes_by_world[world_id] = world_bucket
    _notify_precipitation_volumes_changed(world_3d)


## Rain volumes farther than this from the weather observer are ignored by all rain queries.
func set_precipitation_volume_active_distance(world_3d: World3D, distance: float) -> void:
    var state := _ensure_weather_state(world_3d)
    if state.is_empty():
        return
    state["precipitation_volume_active_distance"] = maxf(distance, 0.0)
    _active_precipitation_volumes_by_world.erase(world_3d.get_instance_id())
    _store_weather_state(world_3d, state)


## Nearest active volumes that remove rain completely (precipitation delta -1), for exact
## per-frame culling in the rain shader.
## The volumes that keep the precipitation out (delta -1), the max_count nearest the observer: the
## shaders cull it exactly in those - the first ones of the list were a station's far roofs while the
## rain fell through the one overhead
func get_precipitation_exclusion_volumes(world_3d: World3D, max_count: int) -> Array:
    var exclusion_volumes: Array = []
    for volume in _get_active_precipitation_volumes(world_3d):
        if (volume as PrecipitationVolume).get_precipitation_delta() <= -1.0:
            exclusion_volumes.append(volume)
    var state: Dictionary = _weather_state_by_world.get(world_3d.get_instance_id(), {}) if world_3d != null else {}
    if exclusion_volumes.size() > max_count and bool(state.get("has_observer_sample", false)):
        var observer: Vector3 = state.get("observer_position", Vector3.ZERO)
        exclusion_volumes.sort_custom(func(a: PrecipitationVolume, b: PrecipitationVolume) -> bool:
            return a.get_distance_to(observer) < b.get_distance_to(observer))
    return exclusion_volumes.slice(0, max_count)


func mark_precipitation_volumes_changed(world_3d: World3D) -> void:
    _notify_precipitation_volumes_changed(world_3d)


## A precipitation volume moved (PrecipitationVolume, as its transform changes)
func notify_precipitation_volume_moved(world_3d: World3D) -> void:
    if world_3d != null:
        precipitation_volumes_moved.emit(world_3d)


func get_precipitation_volume_revision(world_3d: World3D) -> int:
    if world_3d == null:
        return 0

    return int(_precipitation_volume_revision_by_world.get(world_3d.get_instance_id(), 0))


func configure_visible_precipitation_probe_field(
    world_3d: World3D,
    cache_key: int,
    max_probes: int,
    distance: float
) -> void:
    if world_3d == null or cache_key < 0:
        return

    var world_id := world_3d.get_instance_id()
    var world_bucket: Dictionary = _visible_precipitation_probe_configs_by_world.get(world_id, {})
    world_bucket[cache_key] = {
        "max_probes": maxi(max_probes, 1),
        "distance": maxf(distance, 0.1),
    }
    _visible_precipitation_probe_configs_by_world[world_id] = world_bucket
    clear_visible_precipitation_participation_cache(world_3d, cache_key)


func clear_visible_precipitation_probe_field_config(world_3d: World3D, cache_key: int) -> void:
    if world_3d == null or cache_key < 0:
        return

    var world_id := world_3d.get_instance_id()
    var world_bucket: Dictionary = _visible_precipitation_probe_configs_by_world.get(world_id, {})
    if world_bucket.is_empty():
        return

    world_bucket.erase(cache_key)
    if world_bucket.is_empty():
        _visible_precipitation_probe_configs_by_world.erase(world_id)
    else:
        _visible_precipitation_probe_configs_by_world[world_id] = world_bucket

    clear_visible_precipitation_participation_cache(world_3d, cache_key)


func clear_weather_state(world_3d: World3D) -> void:
    if world_3d == null:
        return

    var world_id := world_3d.get_instance_id()
    _weather_state_by_world.erase(world_id)
    _precipitation_volume_revision_by_world.erase(world_id)
    var model: WeatherGroundModel = _ground_models_by_world.get(world_id)
    if model:
        model.clear()
    _apply_weather_controlled_wind(null)


## The weather's inputs, by the names of _make_default_weather_state(); the ones left out keep their
## values. A dictionary rather than a dozen positional arguments, which every new input broke.
func configure_weather_state(world_3d: World3D, settings: Dictionary) -> void:
    var state := _ensure_weather_state(world_3d)
    if state.is_empty():
        return

    if settings.has("air_temperature"):
        state["air_temperature"] = float(settings["air_temperature"])
    if settings.has("snow_fraction"):
        state["snow_target"] = clampf(float(settings["snow_fraction"]), 0.0, 1.0)
        # the weather a scene starts with falls as it is set, not coming on from rain
        if not bool(state.get("snow_settled", false)):
            state["snow_fraction"] = state["snow_target"]
            state["snow_settled"] = true
    for key in ["time_scale", "snow_change_seconds"]:
        if settings.has(key):
            state[key] = maxf(float(settings[key]), 0.0)
    get_ground_model(world_3d).configure(state, settings)
    for key in ["precipitation_intensity", "cloud_density", "cloud_overcast_intensity", "storm_intensity",
            "storm_fog_intensity", "sheltered_volumetric_emission_scale", "air_humidity"]:
        if settings.has(key):
            state[key] = clampf(float(settings[key]), 0.0, 1.0)
    if settings.has("precipitation_wind_strength"):
        state["precipitation_wind_strength"] = maxf(float(settings["precipitation_wind_strength"]), 0.0)
    if settings.has("lightning_enabled"):
        state["lightning_enabled"] = bool(settings["lightning_enabled"])
    for key in ["lightning_min_interval", "lightning_max_interval", "lightning_flash_decay"]:
        if settings.has(key):
            state[key] = maxf(float(settings[key]), 0.1)
    _refresh_weather_state(world_3d, state)
    _store_weather_state(world_3d, state)
    _apply_weather_controlled_wind(world_3d)


func set_weather_observer_sample(world_3d: World3D, world_position: Vector3) -> void:
    var state := _ensure_weather_state(world_3d)
    if state.is_empty():
        return
    state["observer_position"] = world_position
    state["has_observer_sample"] = true
    _active_precipitation_volumes_by_world.erase(world_3d.get_instance_id())
    _refresh_weather_state(world_3d, state)
    _store_weather_state(world_3d, state)


func clear_weather_observer_sample(world_3d: World3D) -> void:
    var state := _ensure_weather_state(world_3d)
    if state.is_empty():
        return
    state["observer_position"] = Vector3.ZERO
    state["has_observer_sample"] = false
    _active_precipitation_volumes_by_world.erase(world_3d.get_instance_id())
    _refresh_weather_state(world_3d, state)
    _store_weather_state(world_3d, state)


func update_weather_state(world_3d: World3D, delta: float) -> void:
    var state := _ensure_weather_state(world_3d)
    if state.is_empty():
        return
    _refresh_weather_state(world_3d, state)
    if delta > 0.0:
        state["wind_time"] = float(state.get("wind_time", 0.0)) + delta * _get_weather_controlled_wind_speed_for_state(state, 1.0)
        var world_seconds := delta * float(state.get("time_scale", 1.0))
        _advance_snow_fraction(state, world_seconds)
        get_ground_model(world_3d).advance(world_3d, state, world_seconds / SECONDS_PER_HOUR)
    _store_weather_state(world_3d, state)
    _apply_weather_controlled_wind(world_3d)
    _apply_ground_globals(state, get_ground_model(world_3d))


## Sets the ground's state, e.g. as a scenario starts, by whichever of its model's keys ground has
## (WeatherSimpleGround: "snow_depth" (metres), "snow_cover" (0 - 1: the depth that covers that much,
## a full cover keeping a deeper snow as it is), "wetness" (0 - 1))
func set_ground_state(world_3d: World3D, ground: Dictionary) -> void:
    var state := _ensure_weather_state(world_3d)
    if state.is_empty():
        return
    var model := get_ground_model(world_3d)
    model.set_ground(state, ground)
    _store_weather_state(world_3d, state)
    _apply_ground_globals(state, model)


## The falling snow's share comes round to the target over world_seconds
func _advance_snow_fraction(state: Dictionary, world_seconds: float) -> void:
    var target := float(state.get("snow_target", 0.0))
    var snow := float(state.get("snow_fraction", 0.0))
    var change_seconds := float(state.get("snow_change_seconds", 3.0))
    if change_seconds <= 0.0 or absf(target - snow) < 0.001:
        snow = target
    else:
        snow = lerpf(snow, target, 1.0 - exp(-world_seconds / change_seconds))
    state["snow_fraction"] = snow


func _apply_ground_globals(state: Dictionary, model: WeatherGroundModel) -> void:
    var globals := model.get_globals(state)
    for name: StringName in globals:
        set_ground_global(name, globals[name])


## A ground's shader global set (by its gnd_ name, as the project names it): added first, of its
## value's type, where the project does not have it
func set_ground_global(name: StringName, value: Variant) -> void:
    _ensure_ground_globals()
    var global_name: StringName = _ground_global_names.get(name, &"")
    if global_name.is_empty():
        global_name = get_ground_global_name(name)
        _ground_global_names[name] = global_name
        if not ProjectSettings.has_setting("shader_globals/" + String(global_name)):
            RenderingServer.global_shader_parameter_add(global_name, _get_global_types(value)[1], value)
    RenderingServer.global_shader_parameter_set(global_name, value)


## A ground's global by its gnd_ name as the project names it: with GROUND_GLOBALS_PREFIX_SETTING's
## prefix, the wind's as it is
func get_ground_global_name(default_name: StringName) -> StringName:
    var name := String(default_name)
    if name.begins_with("gnd_wind_"):
        return default_name
    var prefix := String(ProjectSettings.get_setting(GROUND_GLOBALS_PREFIX_SETTING, DEFAULT_GLOBALS_PREFIX))
    return StringName(prefix + name.trim_prefix(DEFAULT_GLOBALS_PREFIX))


## GROUND_GLOBAL_DEFAULTS' globals by their gnd_ names, as the project names them
func get_ground_global_names() -> Dictionary:
    var names := {}
    for default_name: StringName in GROUND_GLOBAL_DEFAULTS:
        names[default_name] = get_ground_global_name(default_name)
    return names


## The project setting's type and the RenderingServer's for a global's default value
func _get_global_types(value: Variant) -> Array:
    match typeof(value):
        TYPE_VECTOR2:
            return ["vec2", RenderingServer.GLOBAL_VAR_TYPE_VEC2]
        TYPE_PROJECTION:
            return ["mat4", RenderingServer.GLOBAL_VAR_TYPE_MAT4]
        TYPE_NIL, TYPE_OBJECT:
            return ["sampler2D", RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D]
    return ["float", RenderingServer.GLOBAL_VAR_TYPE_FLOAT]


var _ground_globals_ready := false
# the ground's globals by their gnd_ names, as the project names them (GROUND_GLOBALS_PREFIX_SETTING)
var _ground_global_names := {}


## The ground's shader globals, where the project does not have them (an exported game whose
## project.godot never got them): materials including weather_surface.gdshaderinc need them
func _ensure_ground_globals() -> void:
    if _ground_globals_ready:
        return
    _ground_global_names = get_ground_global_names()
    # by the project settings: asking the RenderingServer for its globals stalls it, and it says so
    for default_name: StringName in GROUND_GLOBAL_DEFAULTS:
        var global_name: StringName = _ground_global_names[default_name]
        if not ProjectSettings.has_setting("shader_globals/" + String(global_name)):
            var value: Variant = GROUND_GLOBAL_DEFAULTS[default_name]
            RenderingServer.global_shader_parameter_add(global_name, _get_global_types(value)[1], value)
    _ground_globals_ready = true


func get_weather_state(world_3d: World3D) -> Dictionary:
    if world_3d == null:
        return {}
    var state: Dictionary = _weather_state_by_world.get(world_3d.get_instance_id(), {})
    if state.is_empty():
        return {}
    var report := {
        "global_precipitation": float(state.get("global_precipitation", 0.0)),
        "snow_fraction": float(state.get("snow_fraction", 0.0)),
        "air_temperature": float(state.get("air_temperature", 10.0)),
        "cloud_density": float(state.get("cloud_density", 0.0)),
        "cloud_overcast_intensity_input": float(state.get("cloud_overcast_intensity", 0.0)),
        "storm_intensity_input": float(state.get("storm_intensity", 0.0)),
        "storm_fog_intensity_input": float(state.get("storm_fog_intensity", 0.0)),
        "local_precipitation": float(state.get("local_precipitation", 0.0)),
        "storm_factor": float(state.get("storm_factor", 0.0)),
        "lightning_flash": 0.0,
        "shelter_factor": float(state.get("shelter_factor", 0.0)),
        "local_emission_scale": float(state.get("local_emission_scale", 1.0)),
        "final_wind_speed": get_final_wind_speed(world_3d),
        "final_wind_direction": get_final_wind_direction(world_3d),
    }
    report.merge(get_ground_model(world_3d).get_report(state))
    return report


## Between the tropics the sun is high all the year round: no winter there
const TROPIC_LATITUDE := 23.44


## The season of a day (year, month 1 - 12, day of the month) at a latitude (degrees, south
## negative), as the Earth has it: by the sun's ecliptic longitude - spring from the March equinox,
## summer from the June solstice and so on - turned half a year round in the southern hemisphere,
## and always summer between the tropics
func get_season(latitude: float, year: int, month: int, day: int) -> WeatherNode.Season:
    if absf(latitude) < TROPIC_LATITUDE:
        return WeatherNode.Season.SUMMER
    var longitude := get_solar_ecliptic_longitude(year, month, day)
    if latitude < 0.0:
        longitude = fposmod(longitude + 180.0, 360.0)
    if longitude < 90.0:
        return WeatherNode.Season.SPRING
    if longitude < 180.0:
        return WeatherNode.Season.SUMMER
    if longitude < 270.0:
        return WeatherNode.Season.AUTUMN
    return WeatherNode.Season.WINTER


## The sun's apparent ecliptic longitude in degrees (0 at the March equinox) at noon UTC of a
## Gregorian date, within a few hundredths of a degree (Meeus, the low precision formula)
func get_solar_ecliptic_longitude(year: int, month: int, day: int) -> float:
    var a := (14 - month) / 12
    var y := year + 4800 - a
    var m := month + 12 * a - 3
    var julian_day := day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    var n := float(julian_day) - 2451545.0
    var mean_longitude := 280.460 + 0.9856474 * n
    var mean_anomaly := deg_to_rad(357.528 + 0.9856003 * n)
    return fposmod(mean_longitude + 1.915 * sin(mean_anomaly) + 0.020 * sin(2.0 * mean_anomaly), 360.0)


func ensure_wind_project_settings() -> void:
    var dirty := false

    if not ProjectSettings.has_setting(String(WIND_DIRECTION_SETTING)):
        ProjectSettings.set_setting(String(WIND_DIRECTION_SETTING), {
            "type": "vec2",
            "value": Vector2(0.8, 0.3),
        })
        dirty = true

    if not ProjectSettings.has_setting(String(WIND_SPEED_SETTING)):
        ProjectSettings.set_setting(String(WIND_SPEED_SETTING), {
            "type": "float",
            "value": 1.0,
        })
        dirty = true

    if not ProjectSettings.has_setting(String(WIND_STRENGTH_SETTING)):
        ProjectSettings.set_setting(String(WIND_STRENGTH_SETTING), {
            "type": "float",
            "value": 4.0,
        })
        dirty = true

    if not ProjectSettings.has_setting(String(WIND_TIME_SETTING)):
        ProjectSettings.set_setting(String(WIND_TIME_SETTING), {
            "type": "float",
            "value": 0.0,
        })
        dirty = true

    if not ProjectSettings.has_setting(String(WIND_TURBULENCE_SETTING)):
        ProjectSettings.set_setting(String(WIND_TURBULENCE_SETTING), {
            "type": "float",
            "value": 1.0,
        })
        dirty = true

    var ground_global_names := get_ground_global_names()
    for default_name: StringName in GROUND_GLOBAL_DEFAULTS:
        var setting := "shader_globals/" + String(ground_global_names[default_name])
        if not ProjectSettings.has_setting(setting):
            var value: Variant = GROUND_GLOBAL_DEFAULTS[default_name]
            ProjectSettings.set_setting(setting, {"type": _get_global_types(value)[0], "value": "" if value == null else value})
            dirty = true

    if not ProjectSettings.has_setting(String(WIND_PATTERN_SETTING)):
        ProjectSettings.set_setting(String(WIND_PATTERN_SETTING), {
            "type": "sampler2D",
            "value": "res://grass/wind_pattern.png",
        })
        dirty = true

    if dirty and Engine.is_editor_hint():
        ProjectSettings.save()


func configure_global_wind(direction: Vector2, speed: float, strength: float, turbulence: float, gust_size: float = 40.0) -> void:
    _global_wind_direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector2(0.8, 0.3)
    _global_wind_speed = maxf(speed, 0.0)
    _global_wind_strength = maxf(strength, 0.0)
    _global_wind_turbulence = maxf(turbulence, 0.0)
    _global_wind_gust_size = maxf(gust_size, 2.0)
    RenderingServer.global_shader_parameter_set(StringName(WIND_STRENGTH_GLOBAL), _global_wind_strength)
    RenderingServer.global_shader_parameter_set(StringName(WIND_TURBULENCE_GLOBAL), _global_wind_turbulence)


## How far a full gust sweeping across the scene shoves what the wind blows about, in metres - the
## rain's and the snow's shaders' gust_strength: none, the wind steady across the scene; a server of
## more has gusts
func get_wind_gust_strength(_world_3d: World3D) -> float:
    return 0.0


func get_global_wind_gust_size() -> float:
    return _global_wind_gust_size


func get_global_wind_direction(_fallback: Vector2 = Vector2(0.8, 0.3)) -> Vector2:
    return _global_wind_direction


func get_global_wind_speed(_fallback: float = 1.0) -> float:
    return _global_wind_speed


## How much a full precipitation adds to the wind speed in world_3d's weather (it returned the global
## wind's gust strength instead)
func get_precipitation_wind_strength(world_3d: World3D, fallback: float = 2.0) -> float:
    if world_3d == null:
        return fallback
    var state: Dictionary = _weather_state_by_world.get(world_3d.get_instance_id(), {})
    return float(state.get("precipitation_wind_strength", fallback))


func get_global_wind_turbulence(_fallback: float = 1.0) -> float:
    return _global_wind_turbulence


func get_weather_controlled_wind_speed(world_3d: World3D, fallback: float = 1.0) -> float:
    if world_3d == null:
        return get_global_wind_speed(fallback)
    return _get_weather_controlled_wind_speed_for_state(
        _weather_state_by_world.get(world_3d.get_instance_id(), {}),
        fallback
    )


func get_final_wind_speed(world_3d: World3D, fallback: float = 1.0) -> float:
    var base_speed := get_weather_controlled_wind_speed(world_3d, fallback)
    if base_speed <= 0.0001:
        return 0.0

    var wind_time := get_weather_controlled_wind_time(world_3d)
    var turbulence := get_global_wind_turbulence(1.0)
    var strength_ratio := clampf(base_speed / 6.0, 0.0, 1.0)
    var modulation_depth := turbulence * lerpf(0.05, 0.26, strength_ratio)

    var primary_noise := _sample_wind_noise_1d(wind_time * WIND_GUST_PRIMARY_RATE)
    var secondary_noise := _sample_wind_noise_1d(wind_time * WIND_GUST_SECONDARY_RATE + 13.7)
    var macro_noise := _sample_wind_noise_1d(wind_time * WIND_GUST_MACRO_RATE + 47.3)

    var gust := pow(maxf(primary_noise, 0.0), 1.7) * 0.7 + pow(maxf(secondary_noise, 0.0), 2.1) * 0.3
    var lull := pow(maxf(-macro_noise, 0.0), 1.35)
    var wind_factor := 1.0 + gust * modulation_depth - lull * modulation_depth * 0.55

    return maxf(base_speed * maxf(wind_factor, 0.1), 0.0)


func get_final_wind_direction(world_3d: World3D, fallback: Vector2 = Vector2(0.8, 0.3)) -> Vector2:
    return get_global_wind_direction(fallback)


func get_weather_controlled_wind_time(world_3d: World3D) -> float:
    if world_3d == null:
        return 0.0
    var state: Dictionary = _weather_state_by_world.get(world_3d.get_instance_id(), {})
    if state.is_empty():
        return 0.0
    return float(state.get("wind_time", 0.0))


func _sample_wind_noise_1d(position: float) -> float:
    var cell := floori(position)
    var local := position - float(cell)
    var smooth := local * local * (3.0 - 2.0 * local)
    return lerpf(_hash_wind_noise(cell), _hash_wind_noise(cell + 1), smooth)


func _hash_wind_noise(index: int) -> float:
    var value := sin(float(index) * 12.9898 + 78.233) * 43758.5453
    return (value - floor(value)) * 2.0 - 1.0


func get_configured_visible_precipitation_probe_field_layout(
    world_3d: World3D,
    cache_key: int,
    camera: Camera3D
) -> Dictionary:
    if world_3d == null or cache_key < 0:
        return {}

    var world_id := world_3d.get_instance_id()
    var world_bucket: Dictionary = _visible_precipitation_probe_configs_by_world.get(world_id, {})
    var config: Dictionary = world_bucket.get(cache_key, {})
    if config.is_empty():
        return {}

    return _build_visible_precipitation_probe_field_layout(
        camera,
        int(config.get("max_probes", 24)),
        float(config.get("distance", 8.0))
    )


func get_configured_visible_precipitation_probe_spacing(
    world_3d: World3D,
    cache_key: int,
    camera: Camera3D
) -> float:
    var layout: Dictionary = get_configured_visible_precipitation_probe_field_layout(world_3d, cache_key, camera)
    return _get_visible_precipitation_probe_layout_spacing(layout)


func get_registered_visible_precipitation_probe_positions(
    world_3d: World3D,
    view_transform: Transform3D,
    camera: Camera3D
) -> PackedVector3Array:
    if world_3d == null:
        return PackedVector3Array()

    var world_id := world_3d.get_instance_id()
    var world_bucket: Dictionary = _visible_precipitation_probe_configs_by_world.get(world_id, {})
    if world_bucket.is_empty():
        return PackedVector3Array()

    var positions := PackedVector3Array()
    for cache_key in world_bucket.keys():
        var layout: Dictionary = get_configured_visible_precipitation_probe_field_layout(world_3d, int(cache_key), camera)
        if layout.is_empty():
            continue

        var field_positions := get_visible_precipitation_probe_positions(
            view_transform,
            camera,
            int(layout.get("probe_columns", 1)),
            int(layout.get("probe_rows", 1)),
            int(layout.get("probe_depth_slices", 1)),
            float(layout.get("near_depth", 0.5)),
            float(layout.get("far_depth", 1.0)),
            float(layout.get("field_scale", 1.0))
        )
        positions.append_array(field_positions)

    return positions


func get_precipitation_participation_strength(
    world_3d: World3D,
    world_position: Vector3,
    base_strength: float
) -> float:
    return get_precipitation_participation_strength_for_volumes(
        _get_active_precipitation_volumes(world_3d),
        world_position,
        base_strength
    )


func get_precipitation_lightning_multiplier(
    world_3d: World3D,
    world_position: Vector3
) -> float:
    return get_precipitation_lightning_multiplier_for_volumes(
        _get_active_precipitation_volumes(world_3d),
        world_position
    )


func get_precipitation_lightning_multiplier_for_volumes(
    volumes: Array,
    world_position: Vector3
) -> float:
    return _get_precipitation_lightning_multiplier_for_sorted_volumes(_sort_precipitation_volumes(volumes), world_position)


func _get_precipitation_lightning_multiplier_for_sorted_volumes(
    sorted_volumes: Array,
    world_position: Vector3
) -> float:
    var multiplier := 1.0
    for volume in sorted_volumes:
        var blend: float = volume.get_precipitation_blend(world_position)
        if blend <= 0.0:
            continue

        multiplier *= lerpf(1.0, volume.get_lightning_multiplier(), blend)
    return maxf(multiplier, 0.0)


func get_precipitation_participation_strength_for_volumes(
    volumes: Array,
    world_position: Vector3,
    base_strength: float
) -> float:
    return _get_precipitation_participation_strength_for_sorted_volumes(_sort_precipitation_volumes(volumes), world_position, base_strength)


func _get_precipitation_participation_strength_for_sorted_volumes(
    sorted_volumes: Array,
    world_position: Vector3,
    base_strength: float
) -> float:
    var intensity: float = clampf(base_strength, 0.0, 1.0)
    for volume in sorted_volumes:
        var blend: float = volume.get_precipitation_blend(world_position)
        if blend <= 0.0:
            continue

        var precipitation_delta: float = volume.get_precipitation_delta() * blend
        var precipitation_multiplier: float = lerpf(1.0, volume.get_precipitation_multiplier(), blend)
        intensity = clampf((intensity + precipitation_delta) * precipitation_multiplier, 0.0, 1.0)
    return intensity


func _get_precipitation_probe_render_strength_for_sorted_volumes(
    sorted_volumes: Array,
    world_position: Vector3,
    base_strength: float
) -> float:
    var intensity: float = clampf(base_strength, 0.0, 1.0)
    for volume in sorted_volumes:
        var blend: float = volume.get_precipitation_blend(world_position)
        if blend <= 0.0:
            continue

        var precipitation_multiplier: float = volume.get_precipitation_multiplier()
        var full_intensity: float = clampf(
            (intensity + volume.get_precipitation_delta()) * precipitation_multiplier,
            0.0,
            1.0
        )
        var effective_blend: float = blend
        if full_intensity < intensity - 0.0001 and blend < 1.0:
            effective_blend = _remap_probe_render_suppressive_blend(blend)

        var precipitation_delta: float = volume.get_precipitation_delta() * effective_blend
        var blended_multiplier: float = lerpf(1.0, precipitation_multiplier, effective_blend)
        intensity = clampf((intensity + precipitation_delta) * blended_multiplier, 0.0, 1.0)
    return intensity


func get_visible_precipitation_participation_strength(
    world_3d: World3D,
    cache_key: int,
    view_transform: Transform3D,
    camera: Camera3D,
    base_strength: float,
    probe_columns: int,
    probe_rows: int,
    probe_depth_slices: int,
    near_depth: float,
    far_depth: float,
    field_scale: float,
    refresh_budget: int
) -> float:
    var state: Dictionary = get_visible_precipitation_probe_field_state(
        world_3d,
        cache_key,
        view_transform,
        camera,
        base_strength,
        probe_columns,
        probe_rows,
        probe_depth_slices,
        near_depth,
        far_depth,
        field_scale,
        refresh_budget
    )
    return float(state.get("strength", 0.0))


func get_configured_visible_precipitation_participation_strength(
    world_3d: World3D,
    cache_key: int,
    view_transform: Transform3D,
    camera: Camera3D,
    base_strength: float
) -> float:
    var state := get_configured_visible_precipitation_probe_field_state(
        world_3d,
        cache_key,
        view_transform,
        camera,
        base_strength
    )
    return float(state.get("strength", 0.0))


func get_visible_precipitation_probe_field_state(
    world_3d: World3D,
    cache_key: int,
    view_transform: Transform3D,
    camera: Camera3D,
    base_strength: float,
    probe_columns: int,
    probe_rows: int,
    probe_depth_slices: int,
    near_depth: float,
    far_depth: float,
    field_scale: float,
    refresh_budget: int
) -> Dictionary:
    if world_3d == null or cache_key < 0:
        return {
            "strength": 0.0,
            "nearest_depth": 0.0,
            "has_visible_precipitation": false,
        }

    var clamped_strength: float = clampf(base_strength, 0.0, 1.0)
    var active_volumes: Array = _get_active_precipitation_volumes(world_3d)
    if clamped_strength <= 0.001 and active_volumes.is_empty():
        clear_visible_precipitation_participation_cache(world_3d, cache_key)
        return {
            "strength": 0.0,
            "nearest_depth": 0.0,
            "has_visible_precipitation": false,
        }

    var columns: int = maxi(probe_columns, 1)
    var rows: int = maxi(probe_rows, 1)
    var depth_slices: int = maxi(probe_depth_slices, 1)
    var probe_count: int = columns * rows * depth_slices
    var budget: int = clampi(refresh_budget, 1, probe_count)
    var cache: Dictionary = _ensure_visible_precipitation_probe_field_cache(world_3d, cache_key, probe_count)
    var values: PackedFloat32Array = cache.get("values", PackedFloat32Array())
    var cursor: int = int(cache.get("cursor", 0))
    var ready: bool = bool(cache.get("ready", false))

    if not ready:
        budget = probe_count

    for offset in range(budget):
        var probe_index: int = (cursor + offset) % probe_count
        var probe_position: Vector3 = _get_visible_precipitation_probe_world_position(
            view_transform,
            camera,
            columns,
            rows,
            depth_slices,
            near_depth,
            far_depth,
            field_scale,
            probe_index
        )
        values[probe_index] = _get_precipitation_probe_render_strength_for_sorted_volumes(
            active_volumes,
            probe_position,
            clamped_strength
        )

    cache["values"] = values
    cache["cursor"] = (cursor + budget) % probe_count
    cache["ready"] = true
    _store_visible_precipitation_probe_field_cache(world_3d, cache_key, cache)
    return _get_visible_precipitation_probe_field_state(
        values,
        columns * rows,
        depth_slices,
        near_depth,
        far_depth
    )


func get_configured_visible_precipitation_probe_field_state(
    world_3d: World3D,
    cache_key: int,
    view_transform: Transform3D,
    camera: Camera3D,
    base_strength: float
) -> Dictionary:
    var layout: Dictionary = get_configured_visible_precipitation_probe_field_layout(world_3d, cache_key, camera)
    if layout.is_empty():
        return {
            "strength": 0.0,
            "nearest_depth": 0.0,
            "has_visible_precipitation": false,
        }

    return get_visible_precipitation_probe_field_state(
        world_3d,
        cache_key,
        view_transform,
        camera,
        base_strength,
        int(layout.get("probe_columns", 1)),
        int(layout.get("probe_rows", 1)),
        int(layout.get("probe_depth_slices", 1)),
        float(layout.get("near_depth", 0.5)),
        float(layout.get("far_depth", 1.0)),
        float(layout.get("field_scale", 1.0)),
        int(layout.get("refresh_budget", 1))
    )


func get_visible_precipitation_probe_positions(
    view_transform: Transform3D,
    camera: Camera3D,
    probe_columns: int,
    probe_rows: int,
    probe_depth_slices: int,
    near_depth: float,
    far_depth: float,
    field_scale: float
) -> PackedVector3Array:
    var columns: int = maxi(probe_columns, 1)
    var rows: int = maxi(probe_rows, 1)
    var depth_slices: int = maxi(probe_depth_slices, 1)
    var probe_count: int = columns * rows * depth_slices
    var positions := PackedVector3Array()
    positions.resize(probe_count)

    for probe_index in range(probe_count):
        positions[probe_index] = _get_visible_precipitation_probe_world_position(
            view_transform,
            camera,
            columns,
            rows,
            depth_slices,
            near_depth,
            far_depth,
            field_scale,
            probe_index
        )

    return positions


func clear_visible_precipitation_participation_cache(world_3d: World3D, cache_key: int) -> void:
    if world_3d == null or cache_key < 0:
        return

    var world_id: int = world_3d.get_instance_id()
    var world_fields: Dictionary = _visible_precipitation_probe_fields_by_world.get(world_id, {})
    if world_fields.is_empty():
        return

    world_fields.erase(cache_key)
    if world_fields.is_empty():
        _visible_precipitation_probe_fields_by_world.erase(world_id)
    else:
        _visible_precipitation_probe_fields_by_world[world_id] = world_fields


func _get_active_precipitation_volumes(world_3d: World3D) -> Array:
    if world_3d == null:
        return []

    var world_id: int = world_3d.get_instance_id()
    var world_bucket: Dictionary = _precipitation_volumes_by_world.get(world_id, {})
    if world_bucket.is_empty():
        return []

    # Resolved once per frame; every rain query in the same frame reuses the list.
    var frame: int = Engine.get_process_frames()
    var cached: Dictionary = _active_precipitation_volumes_by_world.get(world_id, {})
    if int(cached.get("frame", -1)) == frame:
        return cached["volumes"]

    var state: Dictionary = _weather_state_by_world.get(world_id, {})
    var has_observer: bool = bool(state.get("has_observer_sample", false))
    var observer_position: Vector3 = state.get("observer_position", Vector3.ZERO)
    var active_distance: float = float(state.get("precipitation_volume_active_distance", INF))
    var stale_ids: Array[int] = []
    var volumes: Array = []
    for volume_id in world_bucket.keys():
        var volume := world_bucket[volume_id] as PrecipitationVolume
        if not is_instance_valid(volume):
            stale_ids.append(volume_id)
            continue
        if not volume.is_inside_tree() or volume.get_world_3d() != world_3d:
            stale_ids.append(volume_id)
            continue
        if not volume.is_precipitation_volume_enabled():
            continue
        if has_observer and volume.get_distance_to(observer_position) > active_distance:
            continue
        volumes.append(volume)

    if not stale_ids.is_empty():
        for volume_id in stale_ids:
            world_bucket.erase(volume_id)
        if world_bucket.is_empty():
            _precipitation_volumes_by_world.erase(world_id)
        else:
            _precipitation_volumes_by_world[world_id] = world_bucket

    var sorted_volumes: Array = _sort_precipitation_volumes(volumes)
    _active_precipitation_volumes_by_world[world_id] = {"frame": frame, "volumes": sorted_volumes}
    return sorted_volumes


func _notify_precipitation_volumes_changed(world_3d: World3D) -> void:
    if world_3d == null:
        return

    var world_id := world_3d.get_instance_id()
    _precipitation_volume_revision_by_world[world_id] = int(_precipitation_volume_revision_by_world.get(world_id, 0)) + 1
    _active_precipitation_volumes_by_world.erase(world_id)
    _visible_precipitation_probe_fields_by_world.erase(world_id)
    precipitation_volumes_moved.emit(world_3d)


func _sort_precipitation_volumes(volumes: Array) -> Array:
    var sorted_volumes: Array = []
    for volume in volumes:
        var precipitation_volume := volume as PrecipitationVolume
        if precipitation_volume == null:
            continue
        if not is_instance_valid(precipitation_volume):
            continue
        if not precipitation_volume.is_precipitation_volume_enabled():
            continue
        sorted_volumes.append(precipitation_volume)

    sorted_volumes.sort_custom(func(a: PrecipitationVolume, b: PrecipitationVolume) -> bool:
        if a.volume_priority == b.volume_priority:
            return a.get_instance_id() < b.get_instance_id()
        return a.volume_priority < b.volume_priority
    )
    return sorted_volumes


func _ensure_visible_precipitation_probe_field_cache(world_3d: World3D, cache_key: int, probe_count: int) -> Dictionary:
    var world_id: int = world_3d.get_instance_id()
    var world_fields: Dictionary = _visible_precipitation_probe_fields_by_world.get(world_id, {})
    var cache: Dictionary = world_fields.get(cache_key, {})
    var current_count: int = int(cache.get("count", -1))
    var values: PackedFloat32Array = cache.get("values", PackedFloat32Array())

    if current_count != probe_count or values.size() != probe_count:
        values = PackedFloat32Array()
        values.resize(probe_count)
        cache = {
            "count": probe_count,
            "cursor": 0,
            "ready": false,
            "values": values,
        }
        world_fields[cache_key] = cache
        _visible_precipitation_probe_fields_by_world[world_id] = world_fields

    return cache


func _apply_weather_controlled_wind(world_3d: World3D) -> void:
    _ensure_ground_globals()
    RenderingServer.global_shader_parameter_set(StringName(WIND_DIRECTION_GLOBAL), get_final_wind_direction(world_3d))
    RenderingServer.global_shader_parameter_set(
        StringName(WIND_SPEED_GLOBAL),
        get_final_wind_speed(world_3d)
    )
    RenderingServer.global_shader_parameter_set(
        StringName(WIND_TIME_GLOBAL),
        get_weather_controlled_wind_time(world_3d)
    )


func _store_visible_precipitation_probe_field_cache(world_3d: World3D, cache_key: int, cache: Dictionary) -> void:
    var world_id: int = world_3d.get_instance_id()
    var world_fields: Dictionary = _visible_precipitation_probe_fields_by_world.get(world_id, {})
    world_fields[cache_key] = cache
    _visible_precipitation_probe_fields_by_world[world_id] = world_fields


func _build_visible_precipitation_probe_field_layout(
    camera: Camera3D,
    max_probes: int,
    distance: float
) -> Dictionary:
    var safe_max_probes: int = maxi(max_probes, 1)
    var safe_far_depth: float = maxf(distance, 0.1)
    var near_depth: float = minf(0.1, safe_far_depth)
    var axis_count: int = maxi(int(ceil(pow(float(safe_max_probes), 1.0 / 3.0))), 1)
    var probe_columns: int = axis_count
    var probe_rows: int = axis_count
    var probe_depth_slices: int = axis_count
    var probe_count: int = probe_columns * probe_rows * probe_depth_slices

    while probe_count > safe_max_probes:
        if probe_columns >= probe_rows and probe_columns >= probe_depth_slices and probe_columns > 1:
            probe_columns -= 1
        elif probe_rows >= probe_depth_slices and probe_rows > 1:
            probe_rows -= 1
        elif probe_depth_slices > 1:
            probe_depth_slices -= 1
        else:
            break
        probe_count = probe_columns * probe_rows * probe_depth_slices

    return {
        "max_probes": safe_max_probes,
        "distance": safe_far_depth,
        "probe_columns": probe_columns,
        "probe_rows": probe_rows,
        "probe_depth_slices": probe_depth_slices,
        "near_depth": near_depth,
        "far_depth": safe_far_depth,
        "field_scale": 1.0,
        "refresh_budget": probe_columns * probe_rows * probe_depth_slices,
    }


func _get_visible_precipitation_probe_layout_spacing(layout: Dictionary) -> float:
    if layout.is_empty():
        return -1.0

    var distance: float = maxf(float(layout.get("distance", 0.1)), 0.1)
    var near_depth: float = clampf(float(layout.get("near_depth", 0.1)), 0.0, distance)
    var depth_span: float = maxf(distance - near_depth, 0.1)
    var field_scale: float = maxf(float(layout.get("field_scale", 1.0)), 0.01)
    var half_extent: float = maxf(distance * field_scale * 0.5, 0.05)
    var columns: int = maxi(int(layout.get("probe_columns", 1)), 1)
    var rows: int = maxi(int(layout.get("probe_rows", 1)), 1)
    var depth_slices: int = maxi(int(layout.get("probe_depth_slices", 1)), 1)
    var lateral_spacing: float = (half_extent * 2.0) / maxf(float(columns - 1), 1.0)
    var vertical_spacing: float = (half_extent * 2.0) / maxf(float(rows - 1), 1.0)
    var depth_spacing: float = depth_span / maxf(float(depth_slices - 1), 1.0)
    return maxf(minf(lateral_spacing, minf(vertical_spacing, depth_spacing)), 0.1)


func _get_visible_precipitation_probe_world_position(
    view_transform: Transform3D,
    camera: Camera3D,
    probe_columns: int,
    probe_rows: int,
    probe_depth_slices: int,
    near_depth: float,
    far_depth: float,
    field_scale: float,
    probe_index: int
) -> Vector3:
    var slice_index: int = probe_index / (probe_columns * probe_rows)
    var plane_index: int = probe_index % (probe_columns * probe_rows)
    var row_index: int = plane_index / probe_columns
    var column_index: int = plane_index % probe_columns

    var depth_t: float = 0.0 if probe_depth_slices <= 1 else float(slice_index) / float(probe_depth_slices - 1)
    var u: float = 0.0 if probe_columns <= 1 else lerpf(-1.0, 1.0, float(column_index) / float(probe_columns - 1))
    var v: float = 0.0 if probe_rows <= 1 else lerpf(1.0, -1.0, float(row_index) / float(probe_rows - 1))

    var safe_near_depth: float = minf(maxf(near_depth, 0.0), far_depth)
    var depth_span: float = maxf(far_depth - safe_near_depth, 0.1)
    var center_depth: float = safe_near_depth + depth_span * 0.5
    var half_extent: float = maxf(far_depth * field_scale * 0.5, 0.05)
    var forward: Vector3 = -view_transform.basis.z
    var right: Vector3 = view_transform.basis.x
    var up: Vector3 = view_transform.basis.y
    return (
        view_transform.origin
        + forward * center_depth
        + right * (u * half_extent)
        + up * (v * half_extent)
        + forward * ((depth_t - 0.5) * depth_span)
    )


func _remap_probe_render_suppressive_blend(blend: float) -> float:
    return _smoothstepf(
        clampf(blend, 0.0, 1.0),
        PRECIPITATION_PROBE_SUPPRESSIVE_FEATHER_BLEND_START,
        PRECIPITATION_PROBE_SUPPRESSIVE_FEATHER_BLEND_END
    )


func _get_visible_precipitation_probe_field_state(
    values: PackedFloat32Array,
    plane_probe_count: int,
    probe_depth_slices: int,
    near_depth: float,
    far_depth: float
) -> Dictionary:
    var visible_intensity: float = 0.0
    var nearest_visible_depth: float = 0.0
    var has_visible_precipitation: bool = false

    for probe_index in range(values.size()):
        var value: float = values[probe_index]
        if value <= 0.001:
            continue

        visible_intensity = maxf(visible_intensity, value)
        var depth: float = _get_visible_precipitation_probe_depth(
            plane_probe_count,
            probe_depth_slices,
            near_depth,
            far_depth,
            probe_index
        )
        if not has_visible_precipitation or depth < nearest_visible_depth:
            nearest_visible_depth = depth
            has_visible_precipitation = true

    return {
        "strength": visible_intensity,
        "nearest_depth": nearest_visible_depth,
        "has_visible_precipitation": has_visible_precipitation,
    }


func _get_visible_precipitation_probe_depth(
    plane_probe_count: int,
    probe_depth_slices: int,
    near_depth: float,
    far_depth: float,
    probe_index: int
) -> float:
    var safe_plane_probe_count: int = maxi(plane_probe_count, 1)
    var safe_depth_slices: int = maxi(probe_depth_slices, 1)
    var slice_index: int = 0 if safe_depth_slices <= 1 else probe_index / safe_plane_probe_count
    slice_index = clampi(slice_index, 0, safe_depth_slices - 1)
    var depth_t: float = 0.0 if safe_depth_slices <= 1 else float(slice_index) / float(safe_depth_slices - 1)
    return lerpf(maxf(near_depth, 0.1), maxf(far_depth, near_depth), depth_t)


func _smoothstepf(value: float, start: float, end: float) -> float:
    var t := clampf((value - start) / maxf(end - start, 0.0001), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)

