@tool
class_name WeatherHeatSource3D
extends Node3D

## A warm (or a cold) place in the scene: a sphere or a box, 1 inside and smoothly nothing falloff
## metres out of it, warming the air, the ground and what stands about it to temperature at the full
## level. The weather probes
## lay it (WeatherServer.add_heat_source_node()): no snow lies where it is warm, the wet dries faster.
## For a scene of its own; a game's models and vehicles give theirs through a WeatherHeatProvider.

enum Shape { SPHERE, BOX }

@export var shape: Shape = Shape.BOX:
    set(value):
        shape = value
        _changed()
## The sphere's radius, in metres
@export_range(0.0, 100.0, 0.01, "or_greater", "suffix:m") var radius: float = 2.0:
    set(value):
        radius = maxf(value, 0.0)
        _changed()
## The box's whole size along the node's axes, in metres
@export var size: Vector3 = Vector3(4.0, 3.0, 4.0):
    set(value):
        size = value.abs()
        _changed()
## How wide its soft edge is, in metres
@export_range(0.0, 50.0, 0.01, "or_greater", "suffix:m") var falloff: float = 1.0:
    set(value):
        falloff = maxf(value, 0.0)
        _changed()
## Its temperature at the full level, °C: below the air's, a cold place
@export_range(-50.0, 200.0, 0.1, "suffix:°C") var temperature: float = 25.0:
    set(value):
        temperature = value
        _changed()
## How far it is heated now, 0 - 1 (the heat_source's channel)
@export_range(0.0, 1.0, 0.01) var level: float = 1.0:
    set(value):
        level = clampf(value, 0.0, 1.0)
        _changed()

var _registered_world: World3D


func _notification(what: int) -> void:
    if what == NOTIFICATION_ENTER_WORLD:
        _registered_world = get_world_3d()
        WeatherServer.add_heat_source_node(_registered_world, self)
    elif what == NOTIFICATION_EXIT_WORLD and _registered_world != null:
        WeatherServer.remove_heat_source_node(_registered_world, self)
        _registered_world = null


## Packed as a WeatherHeatProvider gives a source
func pack_into(into: PackedFloat32Array) -> void:
    var extent := Vector3(radius, radius, radius) if shape == Shape.SPHERE else size * 0.5
    WeatherHeatProvider.pack(into, global_transform,
        WeatherHeatProvider.SHAPE_SPHERE if shape == Shape.SPHERE else WeatherHeatProvider.SHAPE_BOX,
        extent, falloff, temperature, level)


## How far out of its centre it reaches, for the probes' window
func get_reach() -> float:
    return (radius if shape == Shape.SPHERE else size.length() * 0.5) + falloff


func _changed() -> void:
    if _registered_world != null:
        WeatherServer.mark_heat_sources_changed(_registered_world)
