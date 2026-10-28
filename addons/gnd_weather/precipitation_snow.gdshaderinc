// The snowflakes (precipitation_snow.gdshader and a weather's own): included after a wind -
// vec3 precipitation_snow_wind(vec3 position, vec2 flight, vec2 air_travel, float gust_strength,
// float gust_scale, float turbulence, float seed, float detail, float response, float time), where it
// carries a flake; air_travel - how far the wind has carried the air, in metres

// Snowflakes: each instance a cell of the precipitation field (PrecipitationMesh), drawing up to
// flake_count of its mesh's quads (their index in UV2.x) as small soft flakes facing the camera,
// scattered over the cell, falling, swaying and carried along by the wind.
// INSTANCE_CUSTOM: r - phase, g - how much of the snow reaches the cell (volumes), b - variation,
// a - detail

uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.8);
// the flake's size, in metres
uniform float flake_size : hint_range(0.001, 0.1) = 0.012;
// how many of an instance's flakes show, and over how much of its cell they are scattered (metres)
uniform int flake_count = 16;
uniform float cell_spread = 0.8;
// how fast it falls, in metres a second
uniform float fall_speed : hint_range(0.05, 10.0) = 1.0;
// how far TIME * fall_speed is ahead of the snow's fall: taken up as the speed changes, so that no
// flake moves (TIME * a new speed alone moved every flake by the whole time it had snowed)
uniform float fall_offset = 0.0;
// The flakes wrap around in a box about the camera (box_center above it, box_extents its half
// size), fading out towards its sides, so they fill it whichever way the wind blows them
uniform float box_center_height = 0.0;
uniform vec3 box_extents = vec3(4.6, 6.0, 4.6);
// how far to the sides it sways, in metres
uniform float sway : hint_range(0.0, 2.0) = 0.25;
// how fast the wind carries it now (m/s), which draws a flake out into a streak over streak_time
uniform vec3 flight = vec3(0.0);
// how far TIME * flight is ahead of where the wind has carried the snow: taken up as the wind
// changes, so that no flake moves
uniform vec3 drift_offset = vec3(0.0);
uniform float streak_time : hint_range(0.0, 0.2) = 0.03;
// how far the eddies of a gusty wind swirl the flakes about, in metres
uniform float turbulence : hint_range(0.0, 5.0) = 0.0;
// the wind's gusts (precipitation_snow_wind()'s): how far they shove, and how long their waves are
uniform float gust_strength : hint_range(0.0, 20.0) = 0.0;
uniform float gust_scale : hint_range(2.0, 200.0) = 25.0;
uniform float layer_alpha : hint_range(0.0, 1.0) = 1.0;
// how much of a flake's shape shows: 1 the near layer's fluffy clumps of crystals, 0 a soft speck
uniform float flake_detail : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.9;

#include "res://addons/gnd_weather/precipitation_exclusion.gdshaderinc"
#include "res://addons/gnd_weather/precipitation_camera.gdshaderinc"

varying float flake_alpha;
varying float flake_seed;

float hash11(float p) {
	return fract(sin(p * 12.9898) * 43758.5453);
}

void vertex() {
	float flake = UV2.x;
	vec4 custom = INSTANCE_CUSTOM;
	// the flakes past flake_count are folded away to nothing
	flake_alpha = 0.0;
	vec3 world_position = vec3(0.0);
	vec3 flake_velocity = vec3(0.0, -1.0, 0.0);
	if (flake >= float(flake_count)) {
		VERTEX = vec3(0.0);
	} else {
		float seed = custom.a * 31.7 + flake * 0.618034;
		flake_seed = fract(seed);
		float variation = hash11(seed + custom.b);
		float detail = hash11(seed * 1.7 + 3.1);
		vec3 scatter = vec3(hash11(seed * 2.3 + 0.7) - 0.5, hash11(seed * 3.1 + 1.9), hash11(seed * 4.7 + 2.3) - 0.5);
		float speed = fall_speed * mix(0.7, 1.3, variation);
		// all of it from the camera: the instance's cell, fixed in the world, and the box about the eye
		vec3 camera = precipitation_camera(INV_VIEW_MATRIX);
		vec3 cell = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz - camera;
		vec3 box_center = vec3(0.0, box_center_height, 0.0);
		vec3 half_size = max(box_extents, vec3(0.1));

		// each flake takes the wind its own way, a light one more than a heavy one: all alike, the
		// whole box of them slid as one sheet
		float response = mix(0.75, 1.25, fract(variation * 3.7 + detail));
		vec3 position = cell + (TIME * flight - drift_offset) * response + vec3(scatter.x * cell_spread, 0.0, scatter.z * cell_spread);
		position.y += fract(custom.r + scatter.y) * half_size.y * 2.0 - (TIME * fall_speed - fall_offset) * mix(0.7, 1.3, variation);
		float sway_phase = TIME * mix(0.6, 1.4, detail) + detail * 6.2832;
		position.x += sin(sway_phase) * sway * mix(0.5, 1.0, variation);
		position.z += cos(sway_phase * 0.83 + variation * 3.1) * sway * mix(0.5, 1.0, detail);
		// the gusts, the turbulence's swirls and each flake's own little loop: the wind included's
		// - its waves are the world's, so taken where the flake is in it
		position = precipitation_snow_wind(camera + position, flight.xz, (TIME * flight - drift_offset).xz, gust_strength,
			gust_scale, turbulence, seed, detail, response, TIME) - camera;
		vec3 relative = mod(position - box_center + half_size, half_size * 2.0) - half_size;
		vec3 center = box_center + relative;
		world_position = camera + center;

		// faced to the camera, the size its own, drawn out along the way it flies
		vec3 view_center = mat3(VIEW_MATRIX) * center;
		float size = flake_size * mix(0.6, 1.4, detail);
		flake_velocity = flight + vec3(0.0, -speed, 0.0);
		vec2 velocity = (VIEW_MATRIX * vec4(flake_velocity, 0.0)).xy;
		float streak = length(velocity) * streak_time;
		vec2 along = streak > 0.0001 ? velocity / length(velocity) : vec2(0.0, 1.0);
		vec2 across = vec2(-along.y, along.x);
		VERTEX = view_center + vec3(across * VERTEX.x * size + along * VERTEX.y * (size + streak), 0.0);
		NORMAL = vec3(0.0, 0.0, 1.0);

		// faded out towards the sides of the box, where they wrap around, and right in front of the eye,
		// where a flake would be a blur the size of the screen
		vec3 edge = abs(relative) / half_size;
		flake_alpha = (1.0 - smoothstep(0.7, 1.0, max(edge.x, max(edge.y, edge.z))))
			* smoothstep(0.25, 0.9, length(view_center)) * clamp(custom.g, 0.0, 1.0);
		// a shelter's and the probes' once a flake, not every pixel of it: thinned where the probes
		// let less of it through (a volume's feathered edge, a partial one), none under a roof
		flake_alpha *= precipitation_sheltered(world_position, flake_velocity) ? 0.0 : precipitation_reach(world_position);
		if (flake_alpha <= 0.0) {
			VERTEX = vec3(0.0);
		}
	}
}

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float radius = length(q);
	float disc = 1.0 - smoothstep(0.35, 1.0, radius);
	float shape = disc;
	if (flake_detail > 0.001) {
		// a flake up close: a clump of crystals stuck together, each a soft lump, catching a glint
		// along its six arms
		float clump = 0.0;
		for (int k = 0; k < 5; k++) {
			float h = flake_seed * 17.3 + float(k) * 3.17;
			vec2 lump = vec2(fract(sin(h) * 4375.85), fract(sin(h * 1.7) * 2317.13)) - 0.5;
			float lump_radius = mix(0.22, 0.48, fract(sin(h * 2.3) * 9131.7));
			clump = max(clump, 1.0 - smoothstep(lump_radius * 0.45, lump_radius, length(q - lump * 0.9)));
		}
		float angle = atan(q.y, q.x) + flake_seed * 6.2832;
		float arms = pow(abs(cos(angle * 3.0)), 12.0) * (1.0 - smoothstep(0.05, 0.85, radius));
		shape = mix(disc, max(clump * 0.85, arms), flake_detail);
	}
	float alpha = shape * tint.a * layer_alpha * flake_alpha;
	if (alpha < 0.003) {
		discard;
	}
	ALBEDO = tint.rgb;
	ALPHA = alpha;
	ROUGHNESS = roughness;
	SPECULAR = 0.2;
	// lit as a soft speck, from the front whichever way it faces
	NORMAL = vec3(0.0, 0.0, 1.0);
	BACKLIGHT = vec3(0.4);
}
