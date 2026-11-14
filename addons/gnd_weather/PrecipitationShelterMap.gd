@tool
class_name PrecipitationShelterMap
extends Node

## The precipitation's shelter map: the scene's own opaque geometry about the observer, rendered by an
## orthogonal camera looking the way the precipitation falls (the wind slanting it), kept as how far
## along the fall the first thing the precipitation meets is (PrecipitationShelterEffect). A drop, a
## flake or a surface beyond that, back up along the fall, is under a roof: every model shelters what is
## under it without a PrecipitationVolume of its own, and a slanting rain wets the windward edge under a
## roof. The map and the world-to-map transform are the materials' (WeatherServer.SHELTER_*_GLOBAL,
## precipitation_shelter.gdshaderinc).
##
## Rendered again as the observer moves by a texel (the map stays put on the world's texels, so it does
## not shimmer), as the fall turns by more than TURN, and every refresh_frames frames besides for what
## moves. Its camera draws no light, no sky and no effect (DEBUG_DRAW_UNSHADED, an Environment of its
## own) - but the engine renders a directional light's shadows for every camera that sees the light's
## layer: the lights are left out of cull_mask. Without a RenderingDevice (the Compatibility renderer)
## there is none: is_supported() false.

## How far above the observer the camera stands along the fall, and how far below it the map reaches
## (m): what is higher shelters nothing, what is lower is not reached
const ABOVE := 200.0
const BELOW := 100.0
const NEAR := 0.05
## A fall turned this far (radians, about a degree) from the one the map was rendered along renders it
## again, along the new one
const TURN := 0.0175

## The map rendered (its texture get_texture()), world_to_map its transform now - the precipitation's
## materials take them as their own parameters, the scene's as globals (set here)
signal rendered(world_to_map: Projection)
## The map no longer read: its texture going, or gone
signal hidden

var _extent := 96.0
var _resolution := 1024
var _cull_mask := 0xFFFFF
var _refresh_frames := 4
var _observer_id := 0
var _fall := Vector3.DOWN
var _viewport: SubViewport
var _camera: Camera3D
var _effect: PrecipitationShelterEffect
var _texture_ready := false
var _shown := false
var _rendered_center := Vector3.INF
var _rendered_fall := Vector3.ZERO
var _frames := 0


static func is_supported() -> bool:
    return RenderingServer.get_rendering_device() != null


## How wide the map is, in metres, the observer in its middle
func set_extent(value: float) -> void:
    _extent = maxf(value, 1.0)
    if _camera != null:
        _camera.size = _extent
    _rendered_center = Vector3.INF


## How many texels a side it has
func set_resolution(value: int) -> void:
    value = maxi(value, 16)
    if value == _resolution:
        return
    _resolution = value
    if _viewport == null:
        return
    _viewport.size = Vector2i(_resolution, _resolution)
    _hide()
    _texture_ready = false
    _effect.setup(_resolution, NEAR, ABOVE + BELOW)


## The render layers it takes: what shelters - not the lights (see above)
func set_cull_mask(value: int) -> void:
    _cull_mask = value
    if _camera != null:
        _camera.cull_mask = _cull_mask
    _rendered_center = Vector3.INF


## How many frames apart it is rendered at the most, for what moves under it
func set_refresh_frames(value: int) -> void:
    _refresh_frames = maxi(value, 1)


## About whom, and the way the precipitation falls (world space, any length)
func set_view(observer: Node3D, fall: Vector3) -> void:
    _observer_id = observer.get_instance_id() if observer != null else 0
    if fall.length_squared() > 0.000001:
        _fall = fall.normalized()


func _ready() -> void:
    _viewport = SubViewport.new()
    _viewport.size = Vector2i(_resolution, _resolution)
    _viewport.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
    _viewport.positional_shadow_atlas_size = 0
    _viewport.msaa_3d = Viewport.MSAA_DISABLED
    _viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
    _viewport.use_taa = false
    _viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
    _viewport.scaling_3d_scale = 1.0
    _viewport.gui_disable_input = true
    _viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
    add_child(_viewport, false, Node.INTERNAL_MODE_BACK)
    _camera = Camera3D.new()
    _camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    _camera.size = _extent
    _camera.near = NEAR
    _camera.far = ABOVE + BELOW
    _camera.cull_mask = _cull_mask
    var environment := Environment.new()
    environment.background_mode = Environment.BG_CLEAR_COLOR
    _camera.environment = environment
    _effect = PrecipitationShelterEffect.new()
    _effect.texture_created.connect(_on_texture_created)
    var compositor := Compositor.new()
    compositor.compositor_effects = [_effect]
    _camera.compositor = compositor
    _viewport.add_child(_camera)
    _camera.current = true
    _effect.setup(_resolution, NEAR, ABOVE + BELOW)


func _enter_tree() -> void:
    # back in the tree: its texture, let go of as it left it
    if is_node_ready():
        _effect.setup(_resolution, NEAR, ABOVE + BELOW)


func _exit_tree() -> void:
    _hide()
    _texture_ready = false
    _effect.release()


func _process(_delta: float) -> void:
    var observer := instance_from_id(_observer_id) as Node3D if _observer_id != 0 else null
    if not _texture_ready or observer == null:
        return
    _frames += 1
    var turned := _rendered_fall == Vector3.ZERO or _fall.angle_to(_rendered_fall) >= TURN
    var fall := _fall if turned else _rendered_fall
    var basis := Basis.looking_at(fall, Vector3.BACK)
    # the observer on the map's texels, along the fall as well
    var texel := _extent / _resolution
    var at := observer.global_position
    var snapped := (Vector3(at.dot(basis.x), at.dot(basis.y), at.dot(basis.z)) / texel).round() * texel
    var center := basis * snapped
    if not turned and center == _rendered_center and _frames < _refresh_frames:
        return
    var origin := center - fall * ABOVE
    _camera.global_transform = Transform3D(basis, origin)
    _viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
    var world_to_map := _get_world_to_map(basis, origin)
    WeatherServer.set_ground_global(WeatherServer.SHELTER_TRANSFORM_GLOBAL, world_to_map)
    _rendered_center = center
    _rendered_fall = fall
    _frames = 0
    if not _shown:
        _shown = true
        WeatherServer.set_ground_global(WeatherServer.SHELTER_ENABLED_GLOBAL, 1.0)
    rendered.emit(world_to_map)


## Whether the map is the materials' now
func is_shown() -> bool:
    return _shown


## The map's texture (null until it stands on the GPU)
func get_texture() -> Texture2D:
    return _effect.shelter_texture if _effect != null and _texture_ready else null


## The world-to-map transform the materials take: x, y - the texel's coordinates (0 - 1, as the texture
## lies: its first row at the camera's top), z - how far along the fall from the camera, in metres
func _get_world_to_map(basis: Basis, origin: Vector3) -> Projection:
    var across := basis.x / _extent
    var up := basis.y / _extent
    var fall := -basis.z
    return Projection(
        Vector4(across.x, -up.x, fall.x, 0.0),
        Vector4(across.y, -up.y, fall.y, 0.0),
        Vector4(across.z, -up.z, fall.z, 0.0),
        Vector4(0.5 - origin.dot(across), 0.5 + origin.dot(up), -origin.dot(fall), 1.0))


func _on_texture_created() -> void:
    if _effect == null or _effect.shelter_texture == null or not is_inside_tree():
        return
    _texture_ready = true
    WeatherServer.set_ground_global(WeatherServer.SHELTER_MAP_GLOBAL, _effect.shelter_texture)
    # rendered for it on the next frame
    _rendered_center = Vector3.INF


## The materials let go of the map before its GPU texture goes
func _hide() -> void:
    if _shown:
        WeatherServer.set_ground_global(WeatherServer.SHELTER_ENABLED_GLOBAL, 0.0)
    _shown = false
    hidden.emit()
    WeatherServer.set_ground_global(WeatherServer.SHELTER_MAP_GLOBAL, null)
