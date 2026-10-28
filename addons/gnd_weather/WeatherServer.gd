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
## world_3d's heat sources changed (WeatherHeatSource3D, a WeatherHeatProvider): its probes are
## worked out again then
signal heat_sources_changed(world_3d: World3D)
## world_3d's ground was set (set_ground_state()): a scenario's, a jump of its snow or its water - the
## ground at the probes is laid anew from it, not gathered over time towards it
signal ground_state_set(world_3d: World3D)

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
## How full the ground's hollows are of standing water (1 to the brim, up to 3 flooding over): the
## puddles
const PUDDLES_GLOBAL := &"gnd_puddles"
## The weather probes' (WeatherNode, WeatherProbes): the ground at them, their window's corner and
## size in the world, whether there are any
const WEATHER_GROUND_GLOBAL := &"gnd_weather_ground"
## The probes themselves: how much of the precipitation reaches each (r), its temperature, humidity,
## the lightning's multiplier (WeatherProbes.probes_texture)
const WEATHER_PROBES_GLOBAL := &"gnd_weather_probes"
const WEATHER_PROBE_ORIGIN_GLOBAL := &"gnd_weather_probe_origin"
const WEATHER_PROBE_SIZE_GLOBAL := &"gnd_weather_probe_size"
const WEATHER_PROBES_ENABLED_GLOBAL := &"gnd_weather_probes_enabled"
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
    &"gnd_puddles": 0.0,
    # the weather probes' (WeatherNode): the ground at them - the open ground's share of its snow, wet
    # and standing water, its temperature (WeatherProbes.ground_texture) - the window's corner and size
    # in the world, and whether there are any (0 - none: the open ground's weather everywhere)
    &"gnd_weather_ground": null,
    &"gnd_weather_probes": null,
    &"gnd_weather_probe_origin": Vector3.ZERO,
    &"gnd_weather_probe_size": Vector3.ONE,
    &"gnd_weather_probes_enabled": 0.0,
}
## The globals whose type their value does not tell (a texture none yet)
const GROUND_GLOBAL_TYPES := {
    &"gnd_weather_ground": ["sampler3D", RenderingServer.GLOBAL_VAR_TYPE_SAMPLER3D],
    &"gnd_weather_probes": ["sampler3D", RenderingServer.GLOBAL_VAR_TYPE_SAMPLER3D],
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
const WIND_GUST_PRIMARY_RATE := 0.055
const WIND_GUST_SECONDARY_RATE := 0.11
const WIND_GUST_MACRO_RATE := 0.21

var _precipitation_volumes_by_world: Dictionary = {}
var _precipitation_volume_revision_by_world: Dictionary = {}
# the heat sources of each world: its providers (WeatherHeatProvider) and its WeatherHeatSource3D nodes
var _heat_providers_by_world: Dictionary = {}
var _heat_source_nodes_by_world: Dictionary = {}
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


## Who tells where world_3d's warm (or cold) things are, for the weather probes - a game's vehicles,
## its buildings (WeatherHeatProvider)
func add_heat_provider(world_3d: World3D, provider: WeatherHeatProvider) -> void:
    if world_3d == null or provider == null:
        return
    var providers: Array = _heat_providers_by_world.get(world_3d.get_instance_id(), [])
    if not providers.has(provider):
        providers.append(provider)
        provider.heat_sources_changed.connect(mark_heat_sources_changed.bind(world_3d))
    _heat_providers_by_world[world_3d.get_instance_id()] = providers
    mark_heat_sources_changed(world_3d)


func remove_heat_provider(world_3d: World3D, provider: WeatherHeatProvider) -> void:
    if world_3d == null or provider == null:
        return
    var providers: Array = _heat_providers_by_world.get(world_3d.get_instance_id(), [])
    if providers.has(provider):
        providers.erase(provider)
        provider.heat_sources_changed.disconnect(mark_heat_sources_changed)
    mark_heat_sources_changed(world_3d)


## A heat source of the scene's own (WeatherHeatSource3D), as it enters the world and leaves it
func add_heat_source_node(world_3d: World3D, node: WeatherHeatSource3D) -> void:
    if world_3d == null or node == null:
        return
    var nodes: Array = _heat_source_nodes_by_world.get(world_3d.get_instance_id(), [])
    if not nodes.has(node):
        nodes.append(node)
    _heat_source_nodes_by_world[world_3d.get_instance_id()] = nodes
    mark_heat_sources_changed(world_3d)


func remove_heat_source_node(world_3d: World3D, node: WeatherHeatSource3D) -> void:
    if world_3d == null:
        return
    var nodes: Array = _heat_source_nodes_by_world.get(world_3d.get_instance_id(), [])
    nodes.erase(node)
    mark_heat_sources_changed(world_3d)


## world_3d's heat sources changed: its probes worked out again now, not on their next tick
func mark_heat_sources_changed(world_3d: World3D) -> void:
    if world_3d != null:
        heat_sources_changed.emit(world_3d)


## world_3d's heat sources near region (world space), as WeatherHeatProvider packs them: its nodes' and
## every provider's
func get_heat_sources(world_3d: World3D, region: AABB) -> PackedFloat32Array:
    var sources := PackedFloat32Array()
    if world_3d == null:
        return sources
    var world_id := world_3d.get_instance_id()
    for node: WeatherHeatSource3D in _heat_source_nodes_by_world.get(world_id, []):
        if is_instance_valid(node) and node.is_visible_in_tree() \
                and region.grow(node.get_reach()).has_point(node.global_position):
            node.pack_into(sources)
    for provider: WeatherHeatProvider in _heat_providers_by_world.get(world_id, []):
        sources.append_array(provider.get_heat_sources(world_3d, region))
    return sources


## world_3d's precipitation volumes about region (world space), in the order they apply (by their
## priority), for the weather probes (WeatherProbes.VOLUME_STRIDE floats each): the world-to-volume
## transform's rows, the half size, the edge feather, the delta, the multipliers and whether it is
## enclosed - every one of them there, not only the observer's nearest
func get_precipitation_volumes_packed(world_3d: World3D, region: AABB) -> PackedFloat32Array:
    var packed := PackedFloat32Array()
    if world_3d == null:
        return packed
    var volumes: Array = []
    for volume in _precipitation_volumes_by_world.get(world_3d.get_instance_id(), {}).values():
        var precipitation_volume := volume as PrecipitationVolume
        if is_instance_valid(precipitation_volume) and precipitation_volume.is_inside_tree() \
                and precipitation_volume.is_precipitation_volume_enabled() \
                and region.intersects(precipitation_volume.get_world_bounds()):
            volumes.append(precipitation_volume)
    for volume: PrecipitationVolume in _sort_precipitation_volumes(volumes):
        var inverse := volume.global_transform.affine_inverse()
        for row in 3:
            packed.append_array([inverse.basis[0][row], inverse.basis[1][row], inverse.basis[2][row], inverse.origin[row]])
        var half_size := volume.get_half_size()
        packed.append_array([half_size.x, half_size.y, half_size.z, volume.edge_feather,
            volume.get_precipitation_delta(), volume.get_precipitation_multiplier(), volume.get_lightning_multiplier(),
            1.0 if volume.enclosed else 0.0, 0.0, 0.0, 0.0, 0.0])
    return packed


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
    ground_state_set.emit(world_3d)


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
            RenderingServer.global_shader_parameter_add(global_name, _get_global_types(value, name)[1], value)
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
func _get_global_types(value: Variant, global_name: StringName = &"") -> Array:
    if GROUND_GLOBAL_TYPES.has(global_name):
        return GROUND_GLOBAL_TYPES[global_name]
    match typeof(value):
        TYPE_VECTOR3:
            return ["vec3", RenderingServer.GLOBAL_VAR_TYPE_VEC3]
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
            RenderingServer.global_shader_parameter_add(global_name, _get_global_types(value, default_name)[1], value)
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
            ProjectSettings.set_setting(setting, {"type": _get_global_types(value, default_name)[0], "value": "" if value == null else value})
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

