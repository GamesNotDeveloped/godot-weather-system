extends PanelContainer

## The demo's controls: the weather's inputs as sliders, and what it makes of them

## How deep the ground's basin under the pond is (m)
const POND_DEPTH := 0.6

@export var weather_path: NodePath

@onready var _weather: WeatherNode = get_node(weather_path)

var _readout: Label
var _temperature_row: Control
var _snow_row: Control
var _from_temperature: CheckBox
var _snow_cover: CheckBox
# a warm place in the ground before the camera (a boiler room's pit): no snow lies on it
var _warm_ground: WeatherHeatSource3D
# [slider, number label, step, getter]: the panel follows the weather, whatever changed it
var _sliders: Array = []


func _ready() -> void:
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 4)
    add_child(box)
    var title := Label.new()
    title.text = "Weather  (right mouse: look, WASD/QE: move)"
    box.add_child(title)

    _add_slider(box, "Precipitation", 0.0, 1.0, 0.01, func() -> float: return _weather.precipitation_intensity,
        func(v: float) -> void: _weather.precipitation_intensity = v)
    _from_temperature = CheckBox.new()
    _from_temperature.text = "Snow from the temperature"
    _from_temperature.button_pressed = _weather.snow_from_temperature
    _from_temperature.toggled.connect(_on_snow_from_temperature)
    box.add_child(_from_temperature)
    _snow_row = _add_slider(box, "Snow share", 0.0, 1.0, 0.01, func() -> float: return _weather.precipitation_snow,
        func(v: float) -> void: _weather.precipitation_snow = v)
    _temperature_row = _add_slider(box, "Temperature °C", -40.0, 40.0, 0.1, _weather.get_air_temperature_celsius,
        func(v: float) -> void: _weather.set_air_temperature_celsius(v))
    _add_slider(box, "Wind m/s", 0.0, 20.0, 0.1, func() -> float: return _weather.global_wind_speed,
        func(v: float) -> void: _weather.global_wind_speed = v)
    _add_slider(box, "Wind towards °", 0.0, 360.0, 1.0, func() -> float: return fposmod(rad_to_deg(_weather.global_wind_direction.angle()), 360.0),
        func(v: float) -> void: _weather.global_wind_direction = Vector2.from_angle(deg_to_rad(v)))
    _add_slider(box, "Gustiness", 0.0, 3.0, 0.01, func() -> float: return _weather.global_wind_turbulence,
        func(v: float) -> void: _weather.global_wind_turbulence = v)
    _snow_cover = CheckBox.new()
    _snow_cover.text = "Snow lies on the ground"
    _snow_cover.button_pressed = _weather.snow_cover_enabled
    _snow_cover.toggled.connect(func(pressed: bool) -> void: _weather.snow_cover_enabled = pressed)
    box.add_child(_snow_cover)
    _warm_ground = WeatherHeatSource3D.new()
    _warm_ground.name = "WarmGround"
    _warm_ground.size = Vector3(3.0, 1.0, 3.0)
    _warm_ground.falloff = 2.0
    _warm_ground.position = Vector3(-4.0, 0.5, 3.0)
    _weather.get_parent().add_child.call_deferred(_warm_ground)
    _sink_pond_basin()
    _add_slider(box, "Warm ground °C", -20.0, 80.0, 0.5, func() -> float: return _warm_ground.temperature,
        func(v: float) -> void: _warm_ground.temperature = v)
    _add_slider(box, "Snow density", 0.1, 4.0, 0.01, func() -> float: return _weather.snow_density,
        func(v: float) -> void: _weather.snow_density = v)
    _add_slider(box, "Time x", 1.0, 3600.0, 1.0, func() -> float: return _weather.weather_time_scale,
        func(v: float) -> void: _weather.weather_time_scale = v, true)
    _add_slider(box, "Month", 1.0, 12.0, 1.0, func() -> float: return _weather.date_month,
        func(v: float) -> void: _weather.set_date(_weather.date_year, int(v), 15))
    _add_slider(box, "Latitude °", -90.0, 90.0, 0.5, func() -> float: return _weather.latitude,
        func(v: float) -> void: _weather.latitude = v)

    var buttons := HBoxContainer.new()
    box.add_child(buttons)
    # the snow's depth, how far the wind has drifted it
    for preset in [["Clear", 0.0, 0.0], ["Snowed in", 0.4, 0.8]]:
        var button := Button.new()
        button.text = preset[0]
        var depth: float = preset[1]
        button.pressed.connect(func() -> void:
            _weather.snow_depth = depth
            _weather.wetness = 0.0)
        buttons.add_child(button)
    var blizzard := Button.new()
    blizzard.text = "Blizzard"
    blizzard.pressed.connect(_on_blizzard)
    buttons.add_child(blizzard)

    _readout = Label.new()
    box.add_child(_readout)
    _on_snow_from_temperature(_weather.snow_from_temperature)


func _process(_delta: float) -> void:
    for entry in _sliders:
        var slider: HSlider = entry[0]
        # not while it is being dragged
        if not slider.has_focus():
            var value: float = entry[3].call()
            slider.set_value_no_signal(value)
            entry[1].text = str(snappedf(value, entry[2]))
    if _snow_cover.button_pressed != _weather.snow_cover_enabled:
        _snow_cover.set_pressed_no_signal(_weather.snow_cover_enabled)
    if _from_temperature.button_pressed != _weather.snow_from_temperature:
        _from_temperature.set_pressed_no_signal(_weather.snow_from_temperature)
        _on_snow_from_temperature(_weather.snow_from_temperature)
    var seasons := ["winter", "spring", "summer", "autumn"]
    var puddles := float(WeatherServer.get_weather_state(_weather.get_world_3d()).get("puddles", 0.0))
    _readout.text = "falling: %d%% snow, wind %.1f m/s\nground: snow %d cm, wet %d%%, puddles %d%%   season: %s" % [
        roundi(_weather.get_falling_snow_fraction() * 100.0),
        WeatherServer.get_final_wind_speed(_weather.get_world_3d()),
        roundi(_weather.snow_depth * 100.0),
        roundi(_weather.wetness * 100.0),
        roundi(puddles * 100.0),
        seasons[_weather.season],
    ]


## A heavy snow in a gusty gale: a frost, the snow from it, so warming the air turns it to rain
func _on_blizzard() -> void:
    _weather.precipitation_intensity = 1.0
    _weather.snow_from_temperature = true
    _weather.set_air_temperature_celsius(-8.0)
    _weather.global_wind_speed = 12.0
    _weather.global_wind_turbulence = 2.0
    _weather.snow_density = 2.5


func _on_snow_from_temperature(pressed: bool) -> void:
    _weather.snow_from_temperature = pressed
    # the one that decides what falls
    _snow_row.modulate.a = 0.4 if pressed else 1.0
    _temperature_row.modulate.a = 1.0 if pressed else 0.7


## A labelled slider showing what getter gives and calling on_change; logarithmic for the time scale
func _add_slider(parent: Control, text: String, min_value: float, max_value: float, step: float,
        getter: Callable, on_change: Callable, exponential: bool = false) -> Control:
    var value: float = getter.call()
    var row := HBoxContainer.new()
    var label := Label.new()
    label.text = text
    label.custom_minimum_size.x = 120
    row.add_child(label)
    var slider := HSlider.new()
    slider.min_value = min_value
    slider.max_value = max_value
    slider.step = step
    slider.exp_edit = exponential
    slider.value = value
    slider.custom_minimum_size.x = 300
    slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(slider)
    var number := Label.new()
    number.custom_minimum_size.x = 48
    number.text = str(snappedf(value, step))
    row.add_child(number)
    slider.value_changed.connect(func(v: float) -> void:
        number.text = str(snappedf(v, step))
        on_change.call(v))
    # let go, it follows the weather again
    slider.drag_ended.connect(func(_changed: bool) -> void: slider.release_focus())
    _sliders.append([slider, number, step, getter])
    parent.add_child(row)
    return row


## The ground sunk in a basin under the pond (weather_lit's), where the pond lies and as wide as it is
func _sink_pond_basin() -> void:
    var pond := _weather.get_parent().get_node_or_null(^"Pond") as PuddleSurface3D
    var ground := _weather.get_parent().get_node_or_null(^"Ground") as MeshInstance3D
    if pond == null or ground == null or not (pond.mesh is PlaneMesh):
        return
    var material := ground.mesh.surface_get_material(0) as ShaderMaterial
    var half_size := (pond.mesh as PlaneMesh).size * 0.5
    var scale := pond.global_basis.get_scale()
    material.set_shader_parameter(&"basin_centre", Vector2(pond.global_position.x, pond.global_position.z))
    material.set_shader_parameter(&"basin_radii", Vector2(half_size.x * scale.x, half_size.y * scale.z))
    material.set_shader_parameter(&"basin_depth", POND_DEPTH)
