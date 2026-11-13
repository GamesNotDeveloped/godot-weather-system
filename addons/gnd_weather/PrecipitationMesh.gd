@tool
class_name PrecipitationMesh
extends MultiMeshInstance3D

## One layer of falling precipitation - the rain's streaks or the snow's flakes, near the camera or
## further off: instances on a lattice fixed in the world, which the shader wraps round in a box about
## the camera - so nothing is done for the camera moving. WeatherNode makes them as its children and
## sets their lattice and parameters as the weather changes; the shader is the kind's own.

enum Kind { RAIN, SNOW }
enum Layer { NEAR, MID, FAR }

## Flakes one snow instance draws (the shader shows as many of them as its flake_count)
const SNOW_FLAKES_PER_CARD := 320

## The precipitation's material is drawn after the scene's transparent surfaces (water, glass - the
## default priority 0): its node stands at the world's origin (top_level, the shader wraps it round
## the camera), so sorted by its distance it went before a lake by the camera, which covered it
const RENDER_PRIORITY := 1

var kind: Kind = Kind.RAIN
var layer: Layer = Layer.NEAR

var _pushed_exclusion_count: int = 0


## Builds the layer's MultiMesh, card and material once; returns the node for chaining
func setup(p_kind: Kind, p_layer: Layer, shader: Shader) -> PrecipitationMesh:
    kind = p_kind
    layer = p_layer
    cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    # its instances stand fixed in the world, the shader wraps them round the camera: always drawn
    # about it
    top_level = true
    global_transform = Transform3D.IDENTITY
    custom_aabb = AABB(Vector3(-1.0e6, -1.0e6, -1.0e6), Vector3(2.0e6, 2.0e6, 2.0e6))
    if multimesh != null and get_card() != null and get_material() != null:
        if get_material().shader != shader:
            get_material().shader = shader
        return self

    var new_multimesh := MultiMesh.new()
    new_multimesh.transform_format = MultiMesh.TRANSFORM_3D
    new_multimesh.use_custom_data = true
    new_multimesh.instance_count = 0
    new_multimesh.visible_instance_count = 0

    var material := ShaderMaterial.new()
    material.shader = shader
    material.render_priority = RENDER_PRIORITY
    # the shaders take the camera's place from INV_VIEW_MATRIX, negated in a double precision build
    # (precipitation_camera.gdshaderinc) - one whose Vector3 holds half a metre at 1e8 m
    material.set_shader_parameter(&"view_origin_negated", Vector3(1.0e8, 0.0, 0.0) + Vector3(0.5, 0.0, 0.0) != Vector3(1.0e8, 0.0, 0.0))
    var card: Mesh
    if kind == Kind.SNOW:
        card = _make_flakes_mesh(SNOW_FLAKES_PER_CARD)
        card.surface_set_material(0, material)
    else:
        var quad := QuadMesh.new()
        quad.size = Vector2(0.01, 3.5)
        quad.material = material
        card = quad

    new_multimesh.mesh = card
    multimesh = new_multimesh
    return self



func is_mid() -> bool:
    return layer == Layer.MID


func get_card() -> Mesh:
    if multimesh == null:
        return null
    return multimesh.mesh


func get_material() -> ShaderMaterial:
    var card := get_card()
    if card is PrimitiveMesh:
        return (card as PrimitiveMesh).material as ShaderMaterial
    if card != null and card.get_surface_count() > 0:
        return card.surface_get_material(0) as ShaderMaterial
    return null


## Only a value that changed: a parameter set again has the material sent to the GPU again
func set_shader_parameter(parameter: StringName, value: Variant) -> void:
    var material := get_material()
    if material != null and material.get_shader_parameter(parameter) != value:
        material.set_shader_parameter(parameter, value)


func clear() -> void:
    if multimesh != null:
        multimesh.visible_instance_count = 0



## Puts an instance on every cell of field_state, at its place in the world: the lattice the shader
## wraps round the camera
func fill(field_state: Dictionary) -> void:
    if multimesh == null:
        return
    var positions: PackedVector3Array = field_state.get("positions", PackedVector3Array())
    var custom_data: PackedColorArray = field_state.get("custom_data", PackedColorArray())
    var visible_count: int = int(field_state.get("count", 0))
    if visible_count <= 0:
        multimesh.visible_instance_count = 0
        return
    if multimesh.instance_count != positions.size():
        multimesh.instance_count = positions.size()

    for index in range(visible_count):
        multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, positions[index]))
        multimesh.set_instance_custom_data(index, custom_data[index])
    multimesh.visible_instance_count = visible_count


## The rain's card's size, only as it changed
func set_card(width: float, height: float) -> void:
    var card := get_card() as QuadMesh
    if card != null and card.size != Vector2(width, height):
        card.size = Vector2(width, height)


## The boxes the shader discards the precipitation in (WeatherServer.get_precipitation_exclusion_volumes());
## enclosed_mask - a bit for each box closed all round (PrecipitationVolume.enclosed)
func set_exclusions(
    count: int, inverse_transforms: Array[Projection], half_sizes: PackedVector3Array, enclosed_mask: int = 0
) -> void:
    if count == 0 and _pushed_exclusion_count == 0:
        return
    set_shader_parameter(&"exclusion_count", count)
    set_shader_parameter(&"exclusion_inverse_transforms", inverse_transforms)
    set_shader_parameter(&"exclusion_half_sizes", half_sizes)
    set_shader_parameter(&"exclusion_enclosed_mask", enclosed_mask)
    _pushed_exclusion_count = count


## count unit quads in one mesh, each with its index in UV2.x: one instance of it draws that many
## snowflakes, which the shader scatters about the instance's cell
static func _make_flakes_mesh(count: int) -> ArrayMesh:
    var vertices := PackedVector3Array()
    var uvs := PackedVector2Array()
    var uv2s := PackedVector2Array()
    var indices := PackedInt32Array()
    var corners := [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]
    for flake in count:
        var base := vertices.size()
        for corner: Vector2 in corners:
            vertices.append(Vector3(corner.x, corner.y, 0.0))
            uvs.append(corner + Vector2(0.5, 0.5))
            uv2s.append(Vector2(float(flake), 0.0))
        indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_TEX_UV2] = uv2s
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh


## Draws the cards flat in a tint instead (the editor's "Precipitation Meshes"), or normally again
func set_debug_override(material: Material) -> void:
    material_override = material
