@tool
class_name WeatherSettings

## Project settings (PREFIX + property) with the rain look of every WeatherNode that has
## apply_project_settings enabled. Registered by the plugin with WeatherNode's own defaults.

const PREFIX := "gnd_weather/"
const PROPERTIES: Array[StringName] = [
    &"precipitation_wind_strength",
    &"wind_influence",
    &"follow_height",
    &"rain_mesh_density",
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
    &"rain_probe_max_count",
    &"rain_probe_distance",
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


## Project setting value, or the WeatherNode property default when it isn't set.
static func get_value(property: StringName) -> Variant:
    var weather_script: Script = load("res://addons/gnd_weather/WeatherNode.gd")
    return ProjectSettings.get_setting(PREFIX + property, weather_script.get_property_default_value(property))
