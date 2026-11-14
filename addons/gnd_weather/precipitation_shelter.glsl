#[compute]
#version 450

// The precipitation's shelter map (PrecipitationShelterEffect.gd): the depth its camera rendered of the
// scene's opaque geometry, looking the way the precipitation falls, turned into how far along the fall
// the first thing the precipitation meets is, in metres from the camera. A texel takes the farthest of
// those about it, ERODE texels each way: a wire or a thin mast, narrower than that, shelters nothing -
// kept, it drew a dry line on the ground under every wire - and a roof's edge comes in by as much.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D depth_buffer;
layout(r32f, set = 0, binding = 1) uniform restrict writeonly image2D shelter;

layout(push_constant, std430) uniform Params {
	vec2 size;
	// the camera's near and far planes (m): its depth is reversed, 1 at the near plane, 0 at the far
	// one, and an orthogonal camera's is linear between them
	float near;
	float far;
} params;

const int ERODE = 1;

void main() {
	ivec2 texel = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(params.size);
	if (any(greaterThanEqual(texel, size))) {
		return;
	}
	// the farthest: the least of the reversed depths
	float depth = 1.0;
	for (int y = -ERODE; y <= ERODE; y++) {
		for (int x = -ERODE; x <= ERODE; x++) {
			ivec2 at = clamp(texel + ivec2(x, y), ivec2(0), size - 1);
			depth = min(depth, texelFetch(depth_buffer, at, 0).r);
		}
	}
	imageStore(shelter, texel, vec4(params.near + (1.0 - depth) * (params.far - params.near)));
}
