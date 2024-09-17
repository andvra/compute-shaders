#define PI 3.1415926535897932384626433832795f

layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;
layout(rgba32f, binding = 0) uniform image2D img_output;
layout(location = 0) uniform int image_width;
layout(location = 1) uniform int image_height;
layout(location = 5) uniform int num_types;

layout(std430, binding = 8) buffer layout_mold_intensity
{
	float mold_intensity[];
};

void render(ivec2 texel_coord) {
	if (texel_coord.x >= image_width || texel_coord.y >= image_height) {
		return;
	}

	vec4 pixel_color = vec4(0, 0, 0, 1);

	vec4 colors[3] = vec4[3](
		vec4(0.0, 0.2, 0.3, 1.0),
		vec4(0.3, 0.7, 0.0, 1.0),
		vec4(0.7, 0.3, 0.0, 1.0)
		);

	int idx_type_to_use = -1;
	float cur_intensity = -1.0;
	// do_blend == true: Add weighted intensities from the different channels
	// do_blend == false: Only render color from the channel with the highest intensity
	bool do_blend = false;

	for (int idx_type = 0; idx_type < num_types; idx_type++) {
		int idx_pixel = num_types * (texel_coord.x + image_width * texel_coord.y) + idx_type;

		if (!do_blend && mold_intensity[idx_pixel] > cur_intensity) {
			idx_type_to_use = idx_type;
			cur_intensity = mold_intensity[idx_pixel];
		}

		if (do_blend) {
			vec4 cur_color = vec4(1, 1, 1, 1);
			if (colors.length() > idx_type) {
				cur_color = colors[idx_type];
			}
			pixel_color += mold_intensity[idx_pixel] * cur_color;
		}
	}

	if (!do_blend && (idx_type_to_use > -1)) {
		pixel_color = cur_intensity * colors[idx_type_to_use];
	}

	pixel_color.r = min(pixel_color.r, 1);
	pixel_color.g = min(pixel_color.g, 1);
	pixel_color.b = min(pixel_color.b, 1);
	pixel_color.a = min(pixel_color.a, 1);

	imageStore(img_output, texel_coord, pixel_color);
}

void main()
{
	ivec2 texel_coord = ivec2(gl_GlobalInvocationID.xy);

	render(texel_coord);
}