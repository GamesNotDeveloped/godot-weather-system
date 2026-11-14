@tool
class_name PrecipitationShelterEffect
extends CompositorEffect

## The shelter map's camera's compositor effect (PrecipitationShelterMap): once its opaque geometry is
## drawn, its depth is turned into the shelter map by a compute shader (precipitation_shelter.glsl) -
## how far along the fall the first thing the precipitation meets is, in metres from the camera, for
## every texel (shelter_texture). The texture is made on the rendering thread as the map asks (setup()),
## never by itself.

const SHADER: RDShaderFile = preload("precipitation_shelter.glsl")
const GROUP_SIZE := 8

## The texture stands on the GPU (setup() made it on the rendering thread): only now is it for the
## materials - before, a texture with nothing under it
signal texture_created

## How far along the fall the first thing the precipitation meets is, in metres from the map's camera
var shelter_texture: Texture2DRD

var _rd: RenderingDevice
var _shader := RID()
var _pipeline := RID()
var _sampler := RID()
var _shelter := RID()
var _size := 0
var _near := 0.0
var _far := 1.0


func _init() -> void:
    # the opaque geometry's depth, before the transparent's: the precipitation itself writes none
    effect_callback_type = EFFECT_CALLBACK_TYPE_POST_OPAQUE


## The texture for a map size texels a side, made anew, for a camera from near to far (m)
func setup(size: int, near: float, far: float) -> void:
    if shelter_texture == null:
        shelter_texture = Texture2DRD.new()
    RenderingServer.call_on_render_thread(_create.bind(size, near, far))


## Lets go of what it holds on the GPU: the texture first (whoever was given it has let go of it by
## now), so no material is left with one whose GPU texture is gone
func release() -> void:
    shelter_texture = null
    RenderingServer.call_on_render_thread(_free_all)


func _create(size: int, near: float, far: float) -> void:
    _rd = RenderingServer.get_rendering_device()
    if _rd == null:
        return
    if not _shader.is_valid():
        _shader = _rd.shader_create_from_spirv(SHADER.get_spirv())
        if not _shader.is_valid():
            return
        _pipeline = _rd.compute_pipeline_create(_shader)
        _sampler = _rd.sampler_create(RDSamplerState.new())
    # the new one under the texture before the old one goes, so the materials never see none
    var old := _shelter
    var texture_format := RDTextureFormat.new()
    texture_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
    texture_format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
    texture_format.width = size
    texture_format.height = size
    # read back too: a test
    texture_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
            | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
    _shelter = _rd.texture_create(texture_format, RDTextureView.new(), [])
    _size = size
    _near = near
    _far = far
    if shelter_texture != null:
        shelter_texture.texture_rd_rid = _shelter
    if old.is_valid():
        _rd.free_rid(old)
    texture_created.emit.call_deferred()


func _render_callback(callback_type: int, render_data: RenderData) -> void:
    if callback_type != EFFECT_CALLBACK_TYPE_POST_OPAQUE or _rd == null or not _pipeline.is_valid() or not _shelter.is_valid():
        return
    var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
    if buffers == null:
        return
    var internal_size := buffers.get_internal_size()
    var width := mini(internal_size.x, _size)
    var height := mini(internal_size.y, _size)
    if width <= 0 or height <= 0:
        return
    var depth := RDUniform.new()
    depth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
    depth.binding = 0
    depth.add_id(_sampler)
    depth.add_id(buffers.get_depth_layer(0))
    var shelter := RDUniform.new()
    shelter.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
    shelter.binding = 1
    shelter.add_id(_shelter)
    var uniform_set := UniformSetCacheRD.get_cache(_shader, 0, [depth, shelter])
    var push_constant := PackedFloat32Array([width, height, _near, _far]).to_byte_array()
    var list := _rd.compute_list_begin()
    _rd.compute_list_bind_compute_pipeline(list, _pipeline)
    _rd.compute_list_bind_uniform_set(list, uniform_set, 0)
    _rd.compute_list_set_push_constant(list, push_constant, push_constant.size())
    _rd.compute_list_dispatch(list, ceili(float(width) / GROUP_SIZE), ceili(float(height) / GROUP_SIZE), 1)
    _rd.compute_list_end()


func _free_all() -> void:
    if _rd == null:
        return
    for rid in [_shelter, _sampler, _shader]:
        if rid.is_valid():
            _rd.free_rid(rid)
    _shelter = RID()
    _sampler = RID()
    _shader = RID()
    _pipeline = RID()
    _size = 0
