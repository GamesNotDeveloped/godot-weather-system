@tool
class_name WeatherProbes
extends RefCounted

## The weather probes on the GPU (weather_probes.glsl): a lattice of them fixed in the world about the
## camera, `dims` of them `cell` metres apart, held in 3D textures addressed round in it. The probes
## (probes_texture: how much of the precipitation reaches each, its temperature, its humidity, the
## lightning's multiplier) and the ground at them over time (ground_texture: the open ground's share
## of its snow, wet and standing water, and the temperature) are worked out by a compute shader as
## the WeatherNode asks - on its tick, never every frame. Without a RenderingDevice (the Compatibility
## renderer) there are none: is_supported() false, and the materials take the open ground's weather.

const SHADER: RDShaderFile = preload("weather_probes.glsl")
## Floats a volume takes in the shader's buffer
const VOLUME_STRIDE := 24
## weather_probes.glsl's parameters, by their index
enum Param {
    BASE_X, BASE_Y, BASE_Z, MODE,
    DIMS_X, DIMS_Y, DIMS_Z, CELL,
    OLD_BASE_X, OLD_BASE_Y, OLD_BASE_Z, RESET,
    FALL_X, FALL_Y, FALL_Z, AIR_TEMPERATURE,
    HUMIDITY, UNUSED, VOLUME_COUNT, HEAT_COUNT,
    HOURS, RAIN_MM, SNOW_FALL, OPEN_WET,
    OPEN_SNOW, OPEN_WATER, WET_FILM, MELT_PER_DEGREE,
    DRYING_MM, COUNT,
}
const GROUP_SIZE := 4

## The textures stand on the GPU (setup() made them on the rendering thread): only now are they
## for the materials - before, a texture with nothing under it
signal textures_created

## How much of the precipitation reaches each probe (r), its temperature (g, °C), its humidity (b),
## the lightning's multiplier (a)
var probes_texture: Texture3DRD
## The open ground's share of the snow (r), the wet (g) and the standing water (b) at each probe,
## and its temperature (a, °C)
var ground_texture: Texture3DRD

var _rd: RenderingDevice
var _shader := RID()
var _pipeline := RID()
var _probes := RID()
var _ground_state := RID()
var _ground := RID()
var _params := RID()
var _volumes := RID()
var _heat := RID()
var _volume_bytes := 0
var _heat_bytes := 0
var _uniform_set := RID()
var _dims := Vector3i.ZERO
# the window's corner (its world cell) the textures hold, and the one they held before
var _base := Vector3i.ZERO
var _old_base := Vector3i.ZERO
var _reset := true


static func is_supported() -> bool:
    return RenderingServer.get_rendering_device() != null


## The textures for dims probes a side, made anew (their contents worked out again)
func setup(dims: Vector3i) -> void:
    if probes_texture == null:
        probes_texture = Texture3DRD.new()
        ground_texture = Texture3DRD.new()
    _dims = dims
    _reset = true
    RenderingServer.call_on_render_thread(_create.bind(dims))


## Lets go of what it holds on the GPU: the textures first (whoever was given them has let go of
## them by now), so no material is left with one whose GPU texture is gone
func release() -> void:
    probes_texture = null
    ground_texture = null
    RenderingServer.call_on_render_thread(_free_all)


## The ground at the probes laid anew on the next update, as if the weather had always been as it is
## (the open ground's set: a scenario's, a jump of its snow or its water)
func reset_ground() -> void:
    _reset = true


## The window moved: its corner's world cell now
func set_base(base: Vector3i) -> void:
    if base != _base:
        _old_base = _base
        _base = base


func get_base() -> Vector3i:
    return _base


## The probes worked out, then the ground at them over params[HOURS]: params by Param (BASE*, MODE,
## OLD_BASE* and RESET are set here), the volumes (VOLUME_STRIDE floats each, as they apply) and the
## heat sources (WeatherHeatProvider.STRIDE floats each), in the world-to-their-space rows
func update(params: PackedFloat32Array, volumes: PackedFloat32Array, heat: PackedFloat32Array) -> void:
    params.resize(Param.COUNT)
    params[Param.BASE_X] = _base.x
    params[Param.BASE_Y] = _base.y
    params[Param.BASE_Z] = _base.z
    params[Param.DIMS_X] = _dims.x
    params[Param.DIMS_Y] = _dims.y
    params[Param.DIMS_Z] = _dims.z
    params[Param.OLD_BASE_X] = _old_base.x
    params[Param.OLD_BASE_Y] = _old_base.y
    params[Param.OLD_BASE_Z] = _old_base.z
    params[Param.RESET] = 1.0 if _reset else 0.0
    params[Param.VOLUME_COUNT] = volumes.size() / VOLUME_STRIDE
    params[Param.HEAT_COUNT] = heat.size() / WeatherHeatProvider.STRIDE
    _reset = false
    _old_base = _base
    RenderingServer.call_on_render_thread(_dispatch.bind(params, volumes, heat))


func _create(dims: Vector3i) -> void:
    _rd = RenderingServer.get_rendering_device()
    if _rd == null:
        return
    if not _shader.is_valid():
        _shader = _rd.shader_create_from_spirv(SHADER.get_spirv())
        if not _shader.is_valid():
            return
        _pipeline = _rd.compute_pipeline_create(_shader)
        _params = _rd.storage_buffer_create(Param.COUNT * 4)
    # the new ones under the textures before the old ones go, so the materials never see none
    var old := [_probes, _ground_state, _ground]
    _probes = _create_texture(dims, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, true)
    _ground_state = _create_texture(dims, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, false)
    _ground = _create_texture(dims, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, true)
    _uniform_set = RID()
    probes_texture.texture_rd_rid = _probes
    ground_texture.texture_rd_rid = _ground
    for texture: RID in old:
        if texture.is_valid():
            _rd.free_rid(texture)
    textures_created.emit.call_deferred()


func _create_texture(dims: Vector3i, format: RenderingDevice.DataFormat, sampled: bool) -> RID:
    var texture_format := RDTextureFormat.new()
    texture_format.texture_type = RenderingDevice.TEXTURE_TYPE_3D
    texture_format.format = format
    texture_format.width = dims.x
    texture_format.height = dims.y
    texture_format.depth = dims.z
    # read back too: the editor's preview, a test
    texture_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT \
            | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
    if sampled:
        texture_format.usage_bits |= RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
    return _rd.texture_create(texture_format, RDTextureView.new(), [])


func _dispatch(params: PackedFloat32Array, volumes: PackedFloat32Array, heat: PackedFloat32Array) -> void:
    if _rd == null or not _pipeline.is_valid() or not _probes.is_valid():
        return
    # a buffer never empty, grown as it has to be (the uniform set made again with it)
    var volume_bytes := maxi(volumes.size(), VOLUME_STRIDE) * 4
    if volume_bytes > _volume_bytes:
        if _volumes.is_valid():
            _rd.free_rid(_volumes)
        _volume_bytes = volume_bytes * 2
        _volumes = _rd.storage_buffer_create(_volume_bytes)
        _uniform_set = RID()
    var heat_bytes := maxi(heat.size(), WeatherHeatProvider.STRIDE) * 4
    if heat_bytes > _heat_bytes:
        if _heat.is_valid():
            _rd.free_rid(_heat)
        _heat_bytes = heat_bytes * 2
        _heat = _rd.storage_buffer_create(_heat_bytes)
        _uniform_set = RID()
    if not _uniform_set.is_valid() or not _rd.uniform_set_is_valid(_uniform_set):
        _uniform_set = _rd.uniform_set_create([
            _image_uniform(0, _probes), _image_uniform(1, _ground_state), _image_uniform(2, _ground),
            _buffer_uniform(3, _params), _buffer_uniform(4, _volumes), _buffer_uniform(5, _heat),
        ], _shader, 0)
    if not volumes.is_empty():
        _rd.buffer_update(_volumes, 0, volumes.size() * 4, volumes.to_byte_array())
    if not heat.is_empty():
        _rd.buffer_update(_heat, 0, heat.size() * 4, heat.to_byte_array())
    var groups := Vector3i(ceili(float(_dims.x) / GROUP_SIZE), ceili(float(_dims.y) / GROUP_SIZE), ceili(float(_dims.z) / GROUP_SIZE))
    # the probes, then the ground at them
    for mode in 2:
        params[Param.MODE] = mode
        _rd.buffer_update(_params, 0, Param.COUNT * 4, params.to_byte_array())
        var list := _rd.compute_list_begin()
        _rd.compute_list_bind_compute_pipeline(list, _pipeline)
        _rd.compute_list_bind_uniform_set(list, _uniform_set, 0)
        _rd.compute_list_dispatch(list, groups.x, groups.y, groups.z)
        _rd.compute_list_end()


func _image_uniform(binding: int, texture: RID) -> RDUniform:
    var uniform := RDUniform.new()
    uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
    uniform.binding = binding
    uniform.add_id(texture)
    return uniform


func _buffer_uniform(binding: int, buffer: RID) -> RDUniform:
    var uniform := RDUniform.new()
    uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    uniform.binding = binding
    uniform.add_id(buffer)
    return uniform


func _free_textures() -> void:
    for texture in [_probes, _ground_state, _ground]:
        if texture.is_valid():
            _rd.free_rid(texture)
    _probes = RID()
    _ground_state = RID()
    _ground = RID()
    _uniform_set = RID()


func _free_all() -> void:
    if _rd == null:
        return
    _free_textures()
    for rid in [_volumes, _heat, _params, _shader]:
        if rid.is_valid():
            _rd.free_rid(rid)
    _volumes = RID()
    _heat = RID()
    _params = RID()
    _shader = RID()
    _pipeline = RID()
    _volume_bytes = 0
    _heat_bytes = 0
