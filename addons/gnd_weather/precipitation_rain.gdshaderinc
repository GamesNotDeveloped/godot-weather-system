// The rain's drops (precipitation_rain.gdshader and a weather's own): included after a wind -
// vec3 precipitation_rain_wind(vec3 world_position, vec2 wind, vec2 air_travel, float gust_strength,
// float gust_scale, float turbulence, float seed, float variation, float time), how far it shoves a
// drop; air_travel - how far the wind has carried the air, in metres (its gusts and swirls with it)
// Each instance a cell of a lattice fixed in the world (PrecipitationMesh), its card wrapped round
// in a box about the camera - nothing about the camera handed over by the CPU - standing along the
// way the rain falls and turned to the eye. Skips the vertex transform.
// INSTANCE_CUSTOM: r - phase, g - how much of the rain reaches the cell, b - variation, a - detail

uniform vec4 tint : source_color = vec4(0.84, 0.9, 1.0, 0.12);
uniform float width_softness : hint_range(0.01, 0.8) = 0.22;
uniform float flow_speed : hint_range(0.0, 8.0) = 1.0;
// how far TIME * flow_speed is ahead of the streaks' flow: taken up as the speed changes, so that no
// drop moves (TIME * a new speed alone moved every drop by the whole time it had rained)
uniform float flow_offset = 0.0;
uniform float travel_distance : hint_range(0.0, 32.0) = 8.0;
uniform float respawn_spread : hint_range(0.0, 4.0) = 0.35;
uniform float streak_length_scale : hint_range(0.05, 2.0) = 1.0;
uniform float blur_amount : hint_range(0.0, 1.0) = 0.0;
uniform float glow_amount : hint_range(0.0, 1.0) = 0.0;
uniform float intensity : hint_range(0.0, 1.0) = 0.47;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform float roughness : hint_range(0.0, 1.0) = 0.1;
uniform float specular_fade_start : hint_range(0.0, 50.0) = 2.0;
uniform float specular_fade_end : hint_range(0.1, 100.0) = 8.0;
// the box the cards wrap round in about the camera (its half size, its centre this high above the
// eye) - upwind of it as the rain slants, so the drops come down past the eye
uniform vec3 box_extents = vec3(8.0, 6.0, 8.0);
uniform float card_center_height = 0.0;

#include "res://addons/gnd_weather/precipitation_exclusion.gdshaderinc"
#include "res://addons/gnd_weather/precipitation_camera.gdshaderinc"

// the wind (m/s, x and z), its gusts - how far they shove, in metres, and how long their waves are -
// and how far its eddies whirl a drop about, in metres: precipitation_rain_wind()'s, from the wind
// included before this
uniform vec2 wind = vec2(0.0);
// how far TIME * wind is ahead of the air the wind has carried, in metres: taken up as the wind
// changes, so that its gusts and swirls go on where they were (TIME * a new wind alone threw them
// metres aside at every change)
uniform vec2 wind_offset = vec2(0.0);
uniform float gust_strength : hint_range(0.0, 20.0) = 0.0;
uniform float gust_scale : hint_range(2.0, 200.0) = 25.0;
uniform float turbulence : hint_range(0.0, 5.0) = 0.0;

// the way the rain falls (WeatherNode), for what a roof shelters
uniform vec3 fall_direction = vec3(0.0, -1.0, 0.0);
// The light all round the drops take (WeatherNode.get_rain_ambient_light()): the shaders including
// this leave the engine's ambient light out (render_mode ambient_light_disabled), worked out for every
// pixel of every drop - SDFGI's probes included - and take it as one colour for the whole rain
uniform vec3 ambient_light = vec3(0.0);

varying vec4 instance_custom_data;
varying float streak_flow;
varying float edge_fade;
// how much of it the probes let through, worked out at the card's corners
varying float precipitation_open;
// where the drop is in the world, and whether the card may reach under a shelter, its pixels
// tested then (precipitation_near_shelter())
varying vec3 drop_position;
varying flat float near_shelter;

// how far down its card a streak is drawn at most, of the card at streak_length_scale 1: fragment()'s
// body ends by 0.82 of it, its blur by 1.2 times that
const float STREAK_EXTENT = 0.85;
// a card whose line passes nearer the eye than EYE_CLEAR (m) is not drawn, faded out up to EYE_FADE:
// a streak brushing past the eye was tens of pixels wide, the cards the nearest the most of the screen
const float EYE_CLEAR = 0.35;
const float EYE_FADE = 0.8;

float hash11(float p) {
	return fract(sin(p) * 43758.5453123);
}

void vertex() {
	instance_custom_data = INSTANCE_CUSTOM;
	float variation = instance_custom_data.b;
	float detail = instance_custom_data.a;
	float speed = (TIME * flow_speed - flow_offset) * mix(0.75, 1.35, variation);
	streak_flow = fract(instance_custom_data.r + speed);
	float cycle = floor(instance_custom_data.r + speed);
	float offset_x = (hash11(instance_custom_data.a * 97.13 + cycle * 13.71) - 0.5) * respawn_spread;
	float offset_z = (hash11(instance_custom_data.r * 83.17 + cycle * 7.91 + instance_custom_data.a * 19.37) - 0.5) * respawn_spread;
	// the card's place from the camera: its cell wrapped round in the box, which stands upwind of the
	// eye as far as the rain slants over the box's height
	vec3 camera = precipitation_camera(INV_VIEW_MATRIX);
	vec3 cell = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz - camera;
	vec3 down = normalize(fall_direction);
	vec2 slant = down.xz / clamp(-down.y, 0.25, 1.0);
	vec3 box_center = vec3(-slant.x * card_center_height, card_center_height, -slant.y * card_center_height);
	vec2 half_size = max(box_extents.xz, vec2(0.1));
	vec2 relative = mod(cell.xz - box_center.xz + half_size, half_size * 2.0) - half_size;
	vec3 center = box_center + vec3(relative.x + offset_x, 0.0, relative.y + offset_z);
	// faded out towards the box's sides, where the cards wrap round
	vec2 edge = abs(relative) / half_size;
	edge_fade = 1.0 - smoothstep(0.75, 1.0, max(edge.x, edge.y));
	// along the way it falls, turned to the eye: the card's x across, its y down the fall
	vec3 eye_forward = -normalize(INV_VIEW_MATRIX[2].xyz);
	vec3 across = cross(eye_forward, down);
	across = length(across) > 0.0001 ? normalize(across) : normalize(INV_VIEW_MATRIX[0].xyz);
	float card_scale = mix(0.85, 1.15, variation);
	// the card only as long as its streak is drawn: a light rain's short streaks left most of a long
	// card's pixels to be thrown away. Its top (UV.y 0) stays, its bottom comes up with its UV
	float drawn = clamp(STREAK_EXTENT * streak_length_scale * (glow_amount > 0.0 ? mix(1.04, 1.2, blur_amount) : 1.0), 0.05, 1.0);
	float card_half = abs(VERTEX.y);
	float card_y = card_half - UV.y * drawn * card_half * 2.0;
	UV.y *= drawn;
	float along = (card_y + (streak_flow - 0.5) * travel_distance) * card_scale;
	float side = (VERTEX.x + sin((streak_flow + detail) * 6.28318) * mix(0.0, 0.012, detail)) * card_scale;
	vec3 point = center + across * side + down * along;
	// the gusts' waves are the world's, so taken where the drop is in it
	point += precipitation_rain_wind(camera + point, wind, wind * TIME - wind_offset, gust_strength, gust_scale,
		turbulence, instance_custom_data.a + cycle * 0.137, variation, TIME);
	drop_position = camera + point;
	// the probes' at the card's corners, not every pixel of it: thinned where they let less of it
	// through (a volume's feathered edge, a partial one)
	precipitation_open = precipitation_reach(drop_position);
	// the whole card from its top to its bottom, as wide as it is and as far as the wind shoves it:
	// the same at its four corners
	float half_height = abs(VERTEX.y) * card_scale;
	vec3 card_top = camera + center + down * ((streak_flow - 0.5) * travel_distance * card_scale - half_height);
	float margin = abs(VERTEX.x) * card_scale + gust_strength + turbulence * 2.0 + 0.25;
	near_shelter = precipitation_near_shelter(card_top, down, half_height * 2.0, margin) ? 1.0 : 0.0;
	VERTEX = mat3(VIEW_MATRIX) * point;
	NORMAL = normalize(mat3(VIEW_MATRIX) * cross(across, down));
	// how near the card's line passes the eye: the same at its four corners
	float eye_distance = length(center - down * dot(center, down));
	edge_fade *= smoothstep(EYE_CLEAR, EYE_FADE, eye_distance);
	if (eye_distance < EYE_CLEAR) {
		// all four corners at one point: no pixel of it
		VERTEX = vec3(0.0, 0.0, -1.0);
	}
}

void fragment() {
	// under a roof, or in a car: a card's corners above the roof and below the floor let it through
	if (precipitation_open <= 0.01 || (near_shelter > 0.5 && precipitation_sheltered(drop_position, fall_direction))) {
		discard;
	}
	float instance_alpha = clamp(instance_custom_data.g, 0.0, 1.0) * edge_fade * precipitation_open;
	float variation = instance_custom_data.b;
	float detail = instance_custom_data.a;
	float primary_trail = UV.y;
	float secondary_trail = fract(UV.y * 1.35 + instance_custom_data.r * 0.7 + (TIME * flow_speed - flow_offset) * 0.18);

	float center_shift = mix(-0.18, 0.18, detail);
	float centered_x = abs((UV.x - 0.5) + center_shift * (1.0 - UV.y)) * 2.0;
	float width_mask = 1.0 - smoothstep(0.0, mix(width_softness * 0.7, width_softness * 1.35, detail), centered_x);
	width_mask *= 1.0 - smoothstep(0.78, 1.0, centered_x);

	float primary_length = mix(0.24, 0.52, variation) * streak_length_scale;
	float primary_head_size = mix(0.02, 0.05, detail);
	float primary_tail = (1.0 - smoothstep(0.0, primary_length, primary_trail)) * smoothstep(0.0, 0.012, primary_trail);
	float primary_head_glow = 1.0 - smoothstep(0.0, primary_head_size, primary_trail);
	float primary_streak = max(primary_tail * 0.9, primary_head_glow);

	float secondary_length = mix(0.1, 0.28, detail) * streak_length_scale;
	float secondary_tail = (1.0 - smoothstep(0.0, secondary_length, secondary_trail)) * smoothstep(0.0, 0.02, secondary_trail);
	float secondary_head_glow = 1.0 - smoothstep(0.0, mix(0.025, 0.055, variation), secondary_trail);
	float secondary_streak = max(secondary_tail * mix(0.35, 0.7, detail), secondary_head_glow * 0.65);

	float streak_mask = max(primary_streak, secondary_streak * mix(0.2, 0.45, variation));
	float body_end_min = mix(0.28, 0.46, detail) * streak_length_scale;
	float body_end_max = mix(0.58, 0.82, variation) * streak_length_scale;
	float body_fade = smoothstep(0.0, 0.04, UV.y) * (1.0 - smoothstep(body_end_min, body_end_max, UV.y));
	float breakup = 0.65 + 0.35 * sin(
		UV.y * mix(16.0, 28.0, detail)
		+ instance_custom_data.r * 17.0
		+ UV.x * mix(6.0, 14.0, variation)
	);
	float core_alpha = width_mask * body_fade * streak_mask * breakup;
	float blur_width = mix(width_softness * 1.35, width_softness * 3.1, blur_amount);
	float blur_width_mask = 1.0 - smoothstep(0.0, mix(blur_width * 0.95, blur_width * 1.55, detail), centered_x);
	blur_width_mask *= 1.0 - smoothstep(0.96, 1.36 + blur_amount * 0.3, centered_x);
	float blur_body_start = 0.08 + blur_amount * 0.08;
	float blur_body_end_min = body_end_min * mix(0.92, 0.74, blur_amount);
	float blur_body_end_max = body_end_max * mix(1.04, 1.2, blur_amount);
	float blur_body_fade = smoothstep(0.0, blur_body_start, UV.y) * (1.0 - smoothstep(blur_body_end_min, blur_body_end_max, UV.y));
	float blur_breakup = mix(1.0, breakup, 0.35);
	float blur_shape = blur_width_mask * blur_body_fade * pow(max(streak_mask, 0.0), 0.7) * blur_breakup;
	float blur_alpha = blur_shape * glow_amount;
	float alpha = core_alpha + blur_alpha;
	if (alpha < 0.00001) {
		discard;
	}
	float color_alpha = clamp(intensity * 0.5, 0.1, 0.3);
	float opacity_alpha = clamp(intensity * 0.5, 0.1, 0.4);
	float blur_visibility = mix(1.0, 0.42, blur_amount);
	float blur_color_visibility = mix(1.0, 0.58, blur_amount);
	// thinned out where a PrecipitationVolume's feathered edge or a partial shelter takes the rain away
	ALBEDO = tint.rgb * ((core_alpha * intensity + blur_alpha * 0.18) * color_alpha * blur_color_visibility) * instance_alpha;
	ALPHA = (core_alpha * intensity + blur_alpha * 0.1) * opacity_alpha * blur_visibility * instance_alpha;
	ROUGHNESS = roughness;
	
	// Z-buffer / Distance fade:
	// Fade specular intensity based on distance from the camera using inspector parameters.
	float dist = length(VERTEX);
	float specular_fade = 1.0 - smoothstep(specular_fade_start, specular_fade_end, dist);
	SPECULAR = specular * specular_fade;
	EMISSION = vec3(1.0, 1.0, 1.0) * intensity * 0.005 * specular_fade + ALBEDO * ambient_light;

	// Curve the normal to make the streak act like a cylinder rather than a flat mirror.
	// Softened the multiplier from 2.5 to 1.8 to prevent side-lights from catching too aggressively.
	vec3 local_normal = normalize(vec3((UV.x - 0.5) * 1.8, 0.0, 1.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(local_normal, 0.0)).xyz);
}

