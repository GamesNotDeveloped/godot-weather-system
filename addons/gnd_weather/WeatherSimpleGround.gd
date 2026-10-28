class_name WeatherSimpleGround
extends WeatherGroundModel

## The ground as gnd-weather has it of its own: the snow lying deeper and deeper below freezing and
## melting above it, the surfaces wetted by the rain and the melt, drying the faster the warmer and
## the drier the air, and the water past wetting them running off into the hollows - the puddles -
## soaking away and drying. A model of more (drifts, the walls' snow, ice) extends this one.

## The standing water, millimetres over the ground, that fills the hollows to the brim (puddles 1),
## and the deepest it gets before it runs away
const PUDDLES_FULL_MM := 5.0
const STANDING_WATER_MAX_MM := 15.0


func get_state_defaults() -> Dictionary:
    return {
        "snow_depth": 0.0,
        # the snow as millimetres of water, how dense it lies (of the water's) and how wet it is:
        # its depth is the water over the density
        "snow_water": 0.0,
        "snow_density": WeatherServer.SETTLED_SNOW_DENSITY,
        "snow_wetness": 0.0,
        "snow_cover": 0.0,
        "wetness": 0.0,
        # millimetres of water in the hollows, and how full they are (1 to the brim, past it flooding)
        "standing_water": 0.0,
        "puddles": 0.0,
        "snow_cover_enabled": true,
        "snowfall_depth_per_hour": 0.06,
        "snow_melt_rate": 0.17,
        "rain_mm_per_hour": 50.0,
        "drying_mm_per_hour": 0.3,
        # how fast the ground soaks the standing water up, unfrozen
        "drainage_mm_per_hour": 2.0,
    }


func configure(state: Dictionary, settings: Dictionary) -> void:
    if settings.has("snow_cover_enabled"):
        state["snow_cover_enabled"] = bool(settings["snow_cover_enabled"])
    for key in ["snowfall_depth_per_hour", "snow_melt_rate", "rain_mm_per_hour", "drying_mm_per_hour", "drainage_mm_per_hour"]:
        if settings.has(key):
            state[key] = maxf(float(settings[key]), 0.0)


## hours of the weather on the ground: the snow (advance_snow()); the rain and the melt, in
## millimetres of water, wet the surfaces through with the first millimetre and run off into the
## hollows with the rest, the puddles; the ground soaks them up (hardly at all frozen) and they dry
## the faster the warmer
func advance(_world_3d: World3D, state: Dictionary, hours: float) -> void:
    if hours <= 0.0:
        return
    var precipitation := clampf(float(state.get("global_precipitation", 0.0)), 0.0, 1.0)
    var snow := clampf(float(state.get("snow_fraction", 0.0)), 0.0, 1.0)
    var temperature := float(state.get("air_temperature", 10.0))
    var rainfall := precipitation * (1.0 - snow)
    var rain_mm := get_rain_mm(state, rainfall)
    var melt := advance_snow(state, hours, precipitation * snow, rain_mm, temperature)
    state["snow_cover"] = clampf(float(state["snow_depth"]) / WeatherServer.SNOW_COVER_DEPTH, 0.0, 1.0)
    var film := float(state.get("wetness", 0.0)) * WeatherServer.WET_FILM_MM + rain_mm * hours + melt
    var standing := float(state.get("standing_water", 0.0)) + maxf(film - WeatherServer.WET_FILM_MM, 0.0)
    film = minf(film, WeatherServer.WET_FILM_MM)
    var drying := get_drying(state, hours, temperature)
    if rainfall < 0.01:
        film -= drying
    var soaking := float(state.get("drainage_mm_per_hour", 2.0)) * (1.0 if temperature > 0.0 else 0.1) * hours
    standing -= soaking + drying
    state["wetness"] = clampf(film / WeatherServer.WET_FILM_MM, 0.0, 1.0)
    state["standing_water"] = clampf(standing, 0.0, STANDING_WATER_MAX_MM)
    state["puddles"] = float(state["standing_water"]) / PUDDLES_FULL_MM


func set_ground(state: Dictionary, ground: Dictionary) -> void:
    if ground.has("snow_depth") or ground.has("snow_cover"):
        var depth := maxf(float(ground.get("snow_depth", state.get("snow_depth", 0.0))), 0.0)
        if ground.has("snow_cover"):
            var cover := clampf(float(ground["snow_cover"]), 0.0, 1.0)
            if cover < 1.0 or depth < WeatherServer.SNOW_COVER_DEPTH:
                depth = cover * WeatherServer.SNOW_COVER_DEPTH
        # a scenario's snow has lain a while
        state["snow_density"] = WeatherServer.SETTLED_SNOW_DENSITY
        state["snow_wetness"] = 0.0
        state["snow_water"] = depth * WeatherServer.SETTLED_SNOW_DENSITY * 1000.0
        state["snow_depth"] = depth
    if ground.has("wetness"):
        state["wetness"] = clampf(float(ground["wetness"]), 0.0, 1.0)
    # millimetres in the hollows: the puddles
    if ground.has("standing_water"):
        state["standing_water"] = clampf(float(ground["standing_water"]), 0.0, STANDING_WATER_MAX_MM)
    state["puddles"] = float(state.get("standing_water", 0.0)) / PUDDLES_FULL_MM
    state["snow_cover"] = clampf(float(state.get("snow_depth", 0.0)) / WeatherServer.SNOW_COVER_DEPTH, 0.0, 1.0)


func get_globals(state: Dictionary) -> Dictionary:
    var rain := clampf(float(state.get("global_precipitation", 0.0)), 0.0, 1.0) \
            * (1.0 - clampf(float(state.get("snow_fraction", 0.0)), 0.0, 1.0))
    return {
        WeatherServer.SNOW_COVER_GLOBAL: float(state.get("snow_cover", 0.0)),
        WeatherServer.SNOW_DEPTH_GLOBAL: float(state.get("snow_depth", 0.0)),
        WeatherServer.SNOW_WETNESS_GLOBAL: float(state.get("snow_wetness", 0.0)),
        WeatherServer.WETNESS_GLOBAL: float(state.get("wetness", 0.0)),
        WeatherServer.AIR_TEMPERATURE_GLOBAL: float(state.get("air_temperature", 10.0)),
        WeatherServer.RAIN_GLOBAL: rain,
        WeatherServer.PUDDLES_GLOBAL: float(state.get("puddles", 0.0)),
    }


func get_report(state: Dictionary) -> Dictionary:
    return {
        "snow_cover": float(state.get("snow_cover", 0.0)),
        "snow_depth": float(state.get("snow_depth", 0.0)),
        "snow_water": float(state.get("snow_water", 0.0)),
        "snow_density": float(state.get("snow_density", WeatherServer.SETTLED_SNOW_DENSITY)),
        "snow_wetness": float(state.get("snow_wetness", 0.0)),
        "wetness": float(state.get("wetness", 0.0)),
        "standing_water": float(state.get("standing_water", 0.0)),
        "puddles": float(state.get("puddles", 0.0)),
    }


## A rain's millimetres an hour: a drizzle's couple, a downpour's rain_mm_per_hour (50) at the full
func get_rain_mm(state: Dictionary, rainfall: float) -> float:
    return rainfall * rainfall * float(state.get("rain_mm_per_hour", 50.0))


## The water that dries off over hours at a temperature: drying_mm_per_hour as far as the air's
## vapour pressure falls short of the saturated, against a mild day's (WeatherServer.DRYING_*) - the
## warmer and the drier the air the faster, none in a saturated one - and the faster in a wind
func get_drying(state: Dictionary, hours: float, temperature: float) -> float:
    var humidity := float(state.get("air_humidity", WeatherServer.DRYING_HUMIDITY))
    var deficit := WeatherServer.get_vapour_deficit(temperature, humidity) \
            / WeatherServer.get_vapour_deficit(WeatherServer.DRYING_TEMPERATURE, WeatherServer.DRYING_HUMIDITY)
    var wind := 1.0 + WeatherServer.get_state_wind_speed(state) / 4.0
    return float(state.get("drying_mm_per_hour", 0.3)) * deficit * wind * hours


## The snowfall's water settling on the ground in an hour (mm): a sleet's melts as it lands above
## freezing
func get_snowfall_water(state: Dictionary, snowfall: float, temperature: float) -> float:
    var settling := 1.0 - clampf((temperature - 1.0) / 2.0, 0.0, 1.0)
    return snowfall * settling * float(state.get("snowfall_depth_per_hour", 0.06)) * WeatherServer.REFERENCE_SNOW_DENSITY * 1000.0


## The snow's water a degree of the air's warmth melts in an hour (mm): snow_melt_rate, more in a wind
func get_snow_melt_per_degree(state: Dictionary) -> float:
    return float(state.get("snow_melt_rate", 0.17)) * (1.0 + WeatherServer.get_state_wind_speed(state) / 4.0)


func get_probe_rates(state: Dictionary) -> Dictionary:
    var precipitation := clampf(float(state.get("global_precipitation", 0.0)), 0.0, 1.0)
    var snow := clampf(float(state.get("snow_fraction", 0.0)), 0.0, 1.0)
    var temperature := float(state.get("air_temperature", 10.0))
    var density := float(state.get("snow_density", WeatherServer.SETTLED_SNOW_DENSITY))
    return {
        "rain_mm": get_rain_mm(state, precipitation * (1.0 - snow)),
        "snow_fall": get_snowfall_water(state, precipitation * snow, temperature) / (get_fresh_snow_density(temperature) * 1000.0),
        "melt_per_degree": get_snow_melt_per_degree(state) / (density * 1000.0),
        "drying_mm": get_drying(state, 1.0, temperature),
        "wet": float(state.get("wetness", 0.0)),
        "snow": float(state.get("snow_depth", 0.0)),
        "water": float(state.get("standing_water", 0.0)),
    }


## How dense a snowfall lies as it settles, of the water's: a frost's dry powder some 0.07, a snow
## falling about freezing twice that (Hedstrom and Pomeroy), a wet one above it heavier still
static func get_fresh_snow_density(temperature: float) -> float:
    if temperature <= 0.0:
        return (67.9 + 51.3 * exp(temperature / 2.6)) / 1000.0
    return minf(0.119 + temperature * 0.04, 0.2)


## The lying snow over hours: it falls at the density the frost gives it and settles over a couple
## of days; a rain soaks it, and soaked it sinks to slush within the hour; it melts with the warmth
## of the air (snow_melt_rate, more in a wind) and of the rain falling on it (as warm as the air, a
## degree of a millimetre of it melting an eightieth of a millimetre). Returns the melt, mm of water
func advance_snow(state: Dictionary, hours: float, snowfall: float, rain_mm: float, temperature: float) -> float:
    # no snow cover: none lies, and what lay is gone (WeatherNode.snow_cover_enabled)
    if not bool(state.get("snow_cover_enabled", true)):
        state["snow_water"] = 0.0
        state["snow_depth"] = 0.0
        state["snow_cover"] = 0.0
        state["snow_wetness"] = 0.0
        return 0.0
    var water := float(state.get("snow_water", 0.0))
    var density := float(state.get("snow_density", WeatherServer.SETTLED_SNOW_DENSITY))
    var wetness := float(state.get("snow_wetness", 0.0))
    var depth := water / (density * 1000.0) if water > 0.0 else 0.0

    # the new snow on the old
    var fallen := get_snowfall_water(state, snowfall, temperature) * hours
    if fallen > 0.0:
        depth += fallen / (get_fresh_snow_density(temperature) * 1000.0)
        water += fallen
        density = water / (depth * 1000.0)

    # the rain and the melt soak it, a frost freezes it again and it drains
    wetness += (rain_mm * hours) / 3.0
    wetness -= hours * (0.3 + maxf(-temperature, 0.0) * 0.5)
    var melt := 0.0
    if temperature > 0.0 and water > 0.0:
        var air := get_snow_melt_per_degree(state) * temperature
        var rain_heat := rain_mm * temperature / 80.0
        melt = minf(water, (air + rain_heat) * hours)
        water -= melt
        wetness += melt / 3.0
    wetness = clampf(wetness, 0.0, 1.0)

    # it settles to some 0.3 over a couple of days, the faster the warmer, and soaked sinks to slush
    if water > 0.0:
        var warmth := 1.0 + maxf(temperature + 5.0, 0.0) / 5.0
        density += (0.3 - density) * (1.0 - exp(-hours * warmth / 48.0)) if density < 0.3 else 0.0
        density += (WeatherServer.WET_SNOW_DENSITY - density) * (1.0 - exp(-hours * wetness * 2.0)) if density < WeatherServer.WET_SNOW_DENSITY else 0.0
        state["snow_depth"] = water / (density * 1000.0)
    else:
        water = 0.0
        density = WeatherServer.SETTLED_SNOW_DENSITY
        wetness = 0.0
        state["snow_depth"] = 0.0
    state["snow_water"] = water
    state["snow_density"] = density
    state["snow_wetness"] = wetness
    return melt
