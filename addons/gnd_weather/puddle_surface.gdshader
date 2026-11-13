shader_type spatial;

// opaque, so the screen-space reflections take it in: a puddle is a mirror more than a window
render_mode depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// the weather where it lies, all of it from the globals and the probes (nothing set every frame):
// how full it is, ice over it, snow on it, the rain on it
#include "res://addons/gnd_weather/weather_surface.gdshaderinc"
// the snow's cover (the rain on the ground and how full the hollows are: weather_surface's)
global uniform float gnd_snow_cover;
// the weather probes: how much of the precipitation reaches each (r) - a shelter over it keeps the
// ripples off
global uniform sampler3D gnd_weather_probes : filter_linear, repeat_enable;

uniform sampler2D mask_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 shallow_color : source_color = vec4(0.11, 0.15, 0.13, 1.0);
uniform vec4 deep_color : source_color = vec4(0.03, 0.06, 0.07, 1.0);
// how full it stays whatever the weather: a pond's 1, a puddle's 0 (only the rain's water in it)
uniform float fed_level : hint_range(0.0, 1.0) = 0.0;
uniform vec3 ice_tint : source_color = vec3(0.78, 0.84, 0.9);
uniform vec3 snow_albedo : source_color = vec3(0.86, 0.88, 0.92);
uniform float rain_ripple_threshold : hint_range(0.0, 1.0) = 0.12;
uniform float rain_wave_threshold : hint_range(0.0, 1.0) = 0.45;
uniform float puddle_alpha_cutoff : hint_range(0.0, 1.0) = 0.07;
// how far the shore wanders from the mask's and how uneven its bottom is, so a round mask makes a
// puddle of lobes and inlets that dries into a few smaller ones; and how many lobes across the mask
uniform float shore_irregularity : hint_range(0.0, 1.0) = 0.6;
uniform float shore_scale : hint_range(0.5, 10.0) = 3.0;
uniform float visibility_range_begin : hint_range(0.0, 500.0) = 18.0;
uniform float visibility_range_end : hint_range(0.0, 500.0) = 28.0;
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.04;
uniform float ripple_roughness_reduction : hint_range(0.0, 1.0) = 0.02;
uniform float specular_strength : hint_range(0.0, 1.0) = 0.65;
uniform float wave_intensity : hint_range(0.0, 2.0) = 0.08;
uniform float wave_scale : hint_range(0.1, 20.0) = 1.6;
uniform float wave_speed : hint_range(0.1, 20.0) = 0.35;
uniform float secondary_wave_intensity : hint_range(0.0, 2.0) = 0.05;
uniform float secondary_wave_scale : hint_range(0.1, 20.0) = 2.8;
uniform float secondary_wave_speed : hint_range(0.1, 20.0) = 0.55;
uniform float ripple_intensity : hint_range(0.0, 2.0) = 0.18;
uniform float ripple_scale : hint_range(0.1, 10.0) = 1.2;
uniform float ripple_speed : hint_range(0.1, 4.0) = 0.9;
uniform float ripple_max_radius : hint_range(0.0, 5.0) = 1.0;
uniform float edge_foam_strength : hint_range(0.0, 1.0) = 0.08;
uniform float normal_strength : hint_range(0.0, 8.0) = 1.4;

const float HASHSCALE1 = 0.1031;
const vec3 HASHSCALE3 = vec3(0.1031, 0.1030, 0.0973);

// each puddle its own shape
varying vec2 shore_seed;
// not INV_VIEW_MATRIX * VERTEX in fragment(): a double precision build keeps the view's origin there
// its own way
varying vec3 world_position;

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * HASHSCALE1);
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.x + p3.y) * p3.z);
}


// value noise, 0 - 1
float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
        mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x),
        u.y
    );
}


// The puddle's depth (0 - 1): the mask's, its shore pushed about and its bottom made uneven, and
// nothing still at the mask's own edge
float sample_mask_alpha(vec2 uv) {
    vec2 p = uv * shore_scale + shore_seed;
    vec2 warp = vec2(value_noise(p + 3.1), value_noise(p + vec2(8.7, 1.3))) - 0.5;
    float depth = texture(mask_texture, uv + warp * 0.22 * shore_irregularity).a;
    float bottom = value_noise(p * 2.1 + 5.0) * 0.65 + value_noise(p * 4.3 + 1.3) * 0.35 - 0.5;
    return clamp(depth + bottom * shore_irregularity * 0.7 * smoothstep(0.0, 0.3, depth), 0.0, 1.0);
}


void vertex() {
    shore_seed = MODEL_MATRIX[3].xz * 0.37;
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


// How much of the precipitation reaches world_position, of the open sky's: the probes', 1 out of them
float precipitation_reach(vec3 position) {
    float inside = gnd_weather_probe_blend(position);
    if (inside <= 0.0) {
        return 1.0;
    }
    return mix(1.0, texture(gnd_weather_probes, position / gnd_weather_probe_size).r, inside);
}


float linear_depth(float nonlinear_depth, mat4 inv_projection_matrix) {
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
        nonlinear_depth = nonlinear_depth * 2.0 - 1.0;
    #endif
    return 1.0 / (nonlinear_depth * inv_projection_matrix[2].w + inv_projection_matrix[3].w);
}


vec2 hash22(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * HASHSCALE3);
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.xx + p3.yz) * p3.zy);
}


float ripple_height(vec2 uv, float time_value, float rain_strength) {
    float rain_mask = smoothstep(rain_ripple_threshold, 1.0, rain_strength);
    if (rain_mask <= 0.0001) {
        return 0.0;
    }

    vec2 field_uv = uv / max(ripple_scale, 0.001) * 0.85;
    vec2 cell_origin = floor(field_uv);
    float height = 0.0;

    for (float j = -1.0; j <= 1.0; j += 1.0) {
        for (float i = -1.0; i <= 1.0; i += 1.0) {
            vec2 cell = cell_origin + vec2(i, j);
            vec2 rnd = hash22(cell);
            vec2 center = cell + rnd;
            float age = fract(time_value * ripple_speed * mix(0.85, 1.15, rnd.x) + hash12(cell));
            float radius = mix(0.02, 0.18 + max(ripple_max_radius, 0.0) * 0.54, age);
            vec2 delta = field_uv - center;
            float dist = length(delta);
            float band = dist - radius;
            float envelope = exp(-11.0 * abs(band)) * (1.0 - age) * mix(0.8, 1.15, rnd.y);
            float ring = sin(band * 34.0 - age * 4.5) * envelope;
            height += ring;
        }
    }

    return height * ripple_intensity * rain_mask * 0.12;
}


float primary_wave_height(vec2 uv, float time_value) {
    float height = 0.0;
    height += sin(dot(uv, normalize(vec2(1.0, 0.24))) * wave_scale * 10.0 + time_value * wave_speed);
    height += sin(dot(uv, normalize(vec2(-0.45, 1.0))) * wave_scale * 7.0 - time_value * wave_speed * 0.82) * 0.65;
    return height * wave_intensity * 0.02;
}


float secondary_wave_height(vec2 uv, float time_value) {
    float height = 0.0;
    height += sin(dot(uv, normalize(vec2(0.18, 1.0))) * secondary_wave_scale * 13.0 + time_value * secondary_wave_speed);
    height += cos(dot(uv, normalize(vec2(-1.0, 0.16))) * secondary_wave_scale * 9.0 - time_value * secondary_wave_speed * 1.17) * 0.6;
    return height * secondary_wave_intensity * 0.012;
}


float water_height(vec2 uv, float time_value, float rain_strength, float frozen) {
    float mask = sample_mask_alpha(uv);
    if (mask <= 0.001) {
        return 0.0;
    }
    // ice does not ripple
    float waves = (primary_wave_height(uv, time_value) + secondary_wave_height(uv, time_value)) * (1.0 - frozen);
    float ripples = ripple_height(uv, time_value, rain_strength);
    return (waves + ripples) * mask;
}


void fragment() {
    // the ground where it lies: its standing water, its temperature (ice below freezing), its snow
    vec4 local = gnd_weather_local(world_position);
    float water_level = max(fed_level, clamp(gnd_puddles, 0.0, 1.0) * local.b);
    float frozen = 1.0 - clamp(local.a + 0.5, 0.0, 1.0);
    float snow_cover = clamp(gnd_snow_cover * local.r * gnd_weather_snow_kept(local.a, 0.0), 0.0, 1.0);
    // only the rain ripples it, as much of it as reaches it, and not the ice
    float rain_strength = clamp(gnd_rain * precipitation_reach(world_position), 0.0, 1.0) * (1.0 - frozen);

    float mask = sample_mask_alpha(UV);
    // drying, only the deeper part of the mask still holds water
    float cutoff = mix(1.02, puddle_alpha_cutoff, smoothstep(0.05, 0.6, water_level));
    if (mask < cutoff) {
        discard;
    }

    float fragment_depth = linear_depth(FRAGCOORD.z, INV_PROJECTION_MATRIX);
    float visibility = 1.0 - smoothstep(visibility_range_begin, visibility_range_end, fragment_depth);
    float fade_noise = hash12(floor(UV * 192.0));
    if (visibility <= 0.0 || fade_noise > visibility) {
        discard;
    }

    float t = TIME;
    float eps = 0.004;
    float h_l = water_height(UV + vec2(-eps, 0.0), t, rain_strength, frozen);
    float h_r = water_height(UV + vec2(eps, 0.0), t, rain_strength, frozen);
    float h_d = water_height(UV + vec2(0.0, -eps), t, rain_strength, frozen);
    float h_u = water_height(UV + vec2(0.0, eps), t, rain_strength, frozen);

    vec3 base_normal = normalize(NORMAL);
    float slope_strength = max(normal_strength, 0.0) * 3.2;
    vec3 tangent_normal = normalize(vec3((h_l - h_r) * slope_strength, (h_d - h_u) * slope_strength, 0.55));
    mat3 tbn = mat3(normalize(TANGENT), normalize(BINORMAL), base_normal);
    vec3 view_normal = normalize(tbn * tangent_normal);
    NORMAL = view_normal;

    // the water: the darker the deeper, over a muddy shore
    float deep = smoothstep(cutoff, min(cutoff + 0.4, 1.0), mask);
    float edge_blend = (1.0 - smoothstep(cutoff, min(cutoff + 0.18, 1.0), mask)) * (0.75 + edge_foam_strength * 0.25);
    ALBEDO = mix(shallow_color.rgb, deep_color.rgb, deep);
    METALLIC = 0.0;
    SPECULAR = specular_strength * (1.0 - edge_blend * 0.6);
    ROUGHNESS = clamp(surface_roughness + edge_blend * 0.16, 0.02, 0.32);

    // ice: a pale, still sheet over the water
    ALBEDO = mix(ALBEDO, ice_tint * 0.35, frozen);
    ROUGHNESS = mix(ROUGHNESS, 0.12, frozen);
    // snow lying on it hides it, the more the thicker
    float snowed = smoothstep(0.15, 0.55, snow_cover) * mix(0.6, 1.0, frozen);
    ALBEDO = mix(ALBEDO, snow_albedo, snowed);
    SPECULAR *= 1.0 - snowed;
    ROUGHNESS = mix(ROUGHNESS, 0.8, snowed);
}
