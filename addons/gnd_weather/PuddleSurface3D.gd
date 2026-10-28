@tool
extends Node3D
class_name PuddleSurface3D

## A puddle: mask_texture's alpha its depth, on mesh (a plane). The weather where it lies is its
## shader's, from the ground's globals and the weather probes (puddle_surface.gdshader): how full it
## is, ice over it below freezing, snow on it, the rain's ripples as much as reaches it - nothing of it
## worked out here, nor every frame. Its properties go to the material as they are set. A pond is one
## fed of its own (fed_level 1): full in a drought, frozen in a frost.

const PUDDLE_SURFACE_SHADER := preload("res://addons/gnd_weather/puddle_surface.gdshader")

@export var mask_texture: Texture2D:
    set(value):
        mask_texture = value
        _sync_render_state()
@export var mesh: Mesh:
    set(value):
        mesh = value
        if is_inside_tree():
            _ensure_render_resources()
            _sync_render_state()
## How full it stays whatever the weather: a pond's 1, a puddle's 0 (as full as the ground's hollows)
@export_range(0.0, 1.0, 0.01) var fed_level: float = 0.0:
    set(value):
        fed_level = value
        _sync_render_state()
@export_range(0.0, 0.2, 0.001) var surface_height_offset: float = 0.078:
    set(value):
        surface_height_offset = value
        _sync_render_state()
@export_range(0.0, 500.0, 0.1) var visibility_range_begin: float = 6.0:
    set(value):
        visibility_range_begin = value
        _sync_render_state()
@export_range(0.0, 500.0, 0.1) var visibility_range_end: float = 10.0:
    set(value):
        visibility_range_end = value
        _sync_render_state()
@export_range(0.0, 1.0, 0.01) var rain_ripple_threshold: float = 0.31:
    set(value):
        rain_ripple_threshold = value
        _sync_render_state()
@export_range(0.0, 1.0, 0.01) var specular_wet: float = 0.75:
    set(value):
        specular_wet = value
        _sync_render_state()
@export_range(0.0, 1.0, 0.01) var surface_roughness: float = 0.04:
    set(value):
        surface_roughness = value
        _sync_render_state()
@export_range(0.0, 1.0, 0.01) var ripple_roughness_reduction: float = 0.02:
    set(value):
        ripple_roughness_reduction = value
        _sync_render_state()
@export_range(0.1, 4.0, 0.01) var ripple_speed: float = 0.67:
    set(value):
        ripple_speed = value
        _sync_render_state()
@export_range(0.1, 10.0, 0.01) var ripple_scale: float = 0.1:
    set(value):
        ripple_scale = value
        _sync_render_state()
@export_range(0.0, 5.0, 0.01) var ripple_max_radius: float = 1.0:
    set(value):
        ripple_max_radius = value
        _sync_render_state()
@export_range(0.0, 2.0, 0.01) var ripple_intensity: float = 0.9:
    set(value):
        ripple_intensity = value
        _sync_render_state()
@export_range(0.0, 1.0, 0.01) var edge_foam_strength: float = 0.08:
    set(value):
        edge_foam_strength = value
        _sync_render_state()
@export_range(0.0, 8.0, 0.01) var normal_strength: float = 1.0:
    set(value):
        normal_strength = value
        _sync_render_state()
@export_range(0.0, 1.0, 0.01) var puddle_alpha_cutoff: float = 0.07:
    set(value):
        puddle_alpha_cutoff = value
        _sync_render_state()

var _material: ShaderMaterial
var _instance_rid: RID


func _ready() -> void:
    set_notify_transform(true)
    _ensure_render_resources()
    _sync_render_state()


func _exit_tree() -> void:
    if _instance_rid.is_valid():
        RenderingServer.free_rid(_instance_rid)
        _instance_rid = RID()


func _notification(what: int) -> void:
    if what == NOTIFICATION_TRANSFORM_CHANGED:
        _sync_render_state()
    elif what == NOTIFICATION_ENTER_WORLD:
        _sync_render_state()


func _ensure_render_resources() -> void:
    if _material == null:
        _material = ShaderMaterial.new()
        _material.shader = PUDDLE_SURFACE_SHADER

    if not _instance_rid.is_valid():
        _instance_rid = RenderingServer.instance_create()
        RenderingServer.instance_geometry_set_material_override(_instance_rid, _material.get_rid())

    var render_mesh := _get_render_mesh()
    if render_mesh != null:
        RenderingServer.instance_set_base(_instance_rid, render_mesh.get_rid())
    else:
        RenderingServer.instance_set_base(_instance_rid, RID())


func _sync_render_state() -> void:
    if _material == null or not _instance_rid.is_valid():
        return

    var render_mesh := _get_render_mesh()
    if render_mesh == null:
        RenderingServer.instance_set_base(_instance_rid, RID())
        return

    RenderingServer.instance_set_base(_instance_rid, render_mesh.get_rid())

    var world_3d := get_world_3d()
    if world_3d != null:
        RenderingServer.instance_set_scenario(_instance_rid, world_3d.scenario)

    var render_transform := global_transform.translated_local(Vector3(0.0, surface_height_offset, 0.0))
    RenderingServer.instance_set_transform(_instance_rid, render_transform)

    _material.set_shader_parameter("mask_texture", mask_texture)
    _material.set_shader_parameter("fed_level", fed_level)
    _material.set_shader_parameter("rain_ripple_threshold", rain_ripple_threshold)
    _material.set_shader_parameter("puddle_alpha_cutoff", puddle_alpha_cutoff)
    _material.set_shader_parameter("visibility_range_begin", visibility_range_begin)
    _material.set_shader_parameter("visibility_range_end", maxf(visibility_range_end, visibility_range_begin + 0.001))
    _material.set_shader_parameter("surface_roughness", clampf(surface_roughness, 0.01, 0.18))
    _material.set_shader_parameter("ripple_roughness_reduction", ripple_roughness_reduction)
    _material.set_shader_parameter("specular_strength", specular_wet)
    _material.set_shader_parameter("ripple_intensity", ripple_intensity)
    _material.set_shader_parameter("ripple_scale", ripple_scale)
    _material.set_shader_parameter("ripple_speed", ripple_speed)
    _material.set_shader_parameter("ripple_max_radius", ripple_max_radius)
    _material.set_shader_parameter("edge_foam_strength", edge_foam_strength)
    _material.set_shader_parameter("normal_strength", normal_strength)


func _get_render_mesh() -> Mesh:
    return mesh
