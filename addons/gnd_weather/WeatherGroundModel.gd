@abstract
class_name WeatherGroundModel
extends RefCounted

## What the weather leaves on the ground, over the world's time: a world's model of it
## (WeatherServer.set_ground_model(); WeatherSimpleGround by default). It keeps its part of the
## world's weather state - the inputs it reads there are the weather's ("global_precipitation",
## "snow_fraction", "air_temperature", "air_humidity", the global wind) - and tells the ground's
## shader globals what it has of them, by their gnd_ names (WeatherServer.set_ground_global()).


## Its keys of the state, the bare ground's and its rates'
@abstract func get_state_defaults() -> Dictionary


## Its rates out of the weather's inputs (WeatherServer.configure_weather_state()), those it has
func configure(_state: Dictionary, _settings: Dictionary) -> void:
    pass


## hours of the world's time of the weather on the ground
@abstract func advance(world_3d: World3D, state: Dictionary, hours: float) -> void


## The ground set, by whichever of its keys `ground` has (WeatherServer.set_ground_state())
@abstract func set_ground(state: Dictionary, ground: Dictionary) -> void


## The ground's shader globals it sets, by their gnd_ names, and their values now
@abstract func get_globals(state: Dictionary) -> Dictionary


## What it tells of the ground (WeatherServer.get_weather_state()), by the state's keys
@abstract func get_report(state: Dictionary) -> Dictionary


## On each tick of a WeatherNode drawing the weather in the world: what the ground needs of how it
## falls there
func process(_weather: WeatherNode, _delta: float) -> void:
    pass


## What the weather probes need of the ground now (WeatherProbes), by its own reckoning: "rain_mm" -
## the rain falling (mm an hour), "snow_fall" - the snow settling (m an hour), "melt_per_degree" - how
## deep a degree of warmth melts its snow (m an hour), "drying_mm" - the water it dries off (mm an
## hour), and the open ground's "wet" (0 - 1), "snow" (m) and "water" (standing, mm); a model without
## one leaves it out (none of it then)
func get_probe_rates(_state: Dictionary) -> Dictionary:
    return {}


## Let go as the world's weather is cleared
func clear() -> void:
    pass
