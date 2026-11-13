// Where the camera is, for the precipitation's shaders (skip_vertex_transform) - nothing about the
// camera handed over by the CPU, which moves it every frame: INV_VIEW_MATRIX's origin, which a double
// precision build keeps negated (its emulated doubles add it to every model's origin) - right to some
// centimetres far from the world's origin. An instance's place from the camera is its MODEL_MATRIX
// origin less that: a multimesh instance's MODELVIEW_MATRIX was metres off far from the origin, and
// CAMERA_POSITION_WORLD no good at all (measured in a double precision build, 40 km out).

// set once as the material is made (PrecipitationMesh), as the engine is built
uniform bool view_origin_negated = false;

vec3 precipitation_camera(mat4 inv_view) {
	return view_origin_negated ? -inv_view[3].xyz : inv_view[3].xyz;
}
