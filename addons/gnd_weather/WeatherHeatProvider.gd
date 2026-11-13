@tool
class_name WeatherHeatProvider
extends RefCounted

## Where a world's heat sources are, for the weather probes: whoever knows the world's warm things -
## a game's vehicles, its buildings - tells them through one of these (WeatherServer.add_heat_provider()),
## asked as the probes are worked out (on the WeatherNode's tick, never every frame). gnd-weather knows
## nothing of models: a source is a sphere or a box in its own frame, its soft edge, its temperature
## at the full, and its level now (0 - 1) - for the world to lay on its own lattice.
## WeatherHeatSource3D nodes need none of it: the server lays them itself.

## Floats a source takes: the world-to-source transform's rows (12), its shape (SHAPE_*), its radius
## or half size (3), its falloff (m), its temperature at the full (°C), its level (0 - 1), unused
const STRIDE := 20
const SHAPE_SPHERE := 0
const SHAPE_BOX := 1

## A provider's sources changed between its asks - one came or went, or a level jumped - for the
## probes to be worked out again now, not on their next tick
signal heat_sources_changed


## The sources near region (world space), each by pack(): those that warm or cool what is in it
func get_heat_sources(_world_3d: World3D, _region: AABB) -> PackedFloat32Array:
    return PackedFloat32Array()


## A source added to into: transform its frame in the world, shape SHAPE_*, extent its radius (x) or
## half size, falloff the width of its soft edge, temperature at its full level, level 0 - 1
static func pack(into: PackedFloat32Array, transform: Transform3D, shape: int, extent: Vector3, falloff: float,
        temperature: float, level: float) -> void:
    var inverse := transform.affine_inverse()
    for row in 3:
        into.append(inverse.basis[0][row])
        into.append(inverse.basis[1][row])
        into.append(inverse.basis[2][row])
        into.append(inverse.origin[row])
    into.append(float(shape))
    into.append(extent.x)
    into.append(extent.y)
    into.append(extent.z)
    into.append(maxf(falloff, 0.0))
    into.append(temperature)
    into.append(clampf(level, 0.0, 1.0))
    into.append(0.0)
