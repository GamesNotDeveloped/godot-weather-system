@tool
class_name WeatherSettings

## Project settings (PREFIX + property) with the precipitation look of every WeatherNode that has
## apply_project_settings enabled. Registered by the plugin with WeatherNode's own defaults.

const PREFIX := "gnd_weather/"
const PROPERTIES: Array[StringName] = [
    &"precipitation_wind_strength",
    &"wind_influence",
    &"follow_height",
    &"precipitation_mesh_density",
    &"near_layer_speed_multiplier",
    &"near_rain_blur",
    &"near_rain_glow",
    &"mid_rain_blur",
    &"near_rain_color",
    &"mid_rain_color",
    &"visual_intensity",
    &"rain_roughness",
    &"rain_specular_fade_start",
    &"rain_specular_fade_end",
    &"near_snow_color",
    &"mid_snow_color",
    &"snow_flake_size",
    &"snow_fall_speed",
    &"snow_sway",
    &"snow_wind_drift",
    &"snow_density",
    &"weather_probe_cell",
    &"weather_probe_extent",
    &"weather_probe_seconds",
]


static func register() -> void:
    var weather_script: Script = load("res://addons/gnd_weather/WeatherNode.gd")
    for property in PROPERTIES:
        var setting := PREFIX + property
        var default_value: Variant = weather_script.get_property_default_value(property)
        if not ProjectSettings.has_setting(setting):
            ProjectSettings.set_setting(setting, default_value)
        ProjectSettings.add_property_info({"name": setting, "type": typeof(default_value)})
        ProjectSettings.set_initial_value(setting, default_value)


## Project setting value, or [param fallback] when it isn't set.
##
## The settings only exist where register() has run, which is the editor - an EditorPlugin is the
## only kind Godot loads, so an exported game has none of them unless they were written into
## project.godot, and set_initial_value() deliberately keeps the untouched ones out of that file.
## The fallback must therefore not come from Script.get_property_default_value(): that returns
## **null** for every property of a script compiled into an exported pck, because the default only
## exists in the source. Callers pass their own current value, which is the property's initialiser.
static func get_value(property: StringName, fallback: Variant = null) -> Variant:
    return ProjectSettings.get_setting(PREFIX + property, fallback)
