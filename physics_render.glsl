layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;
layout(rgba32f, binding = 0) uniform image2D img_output;
layout(location = 0) uniform float world_min_x;
layout(location = 1) uniform float world_max_x;
layout(location = 2) uniform float world_min_y;
layout(location = 3) uniform float world_max_y;
layout(location = 4) uniform float window_width;
layout(location = 5) uniform float window_height;
layout(location = 6) uniform float window_world_start_x;
layout(location = 7) uniform float window_world_start_y;
layout(location = 8) uniform float window_world_scale_x;
layout(location = 9) uniform float window_world_scale_y;

layout(std430, binding = 9) buffer layout_circles
{
    Circle circles[];
};

void main()
{
    ivec2 texel_coord = ivec2(gl_GlobalInvocationID.xy);

    // TODO: This compute shader should do some physics simulation, with a good main loop.
    //  Idea: maybe have two separate shaders, one for physics calculations and one for rendering?

    vec4 pixel_color = vec4(0, 0, 0, 1);

    vec4 pixel_color_bg = vec4(0.3, texel_coord.y % 100 / 100.0, 0, 1);

    int num_circles = circles.length();

    vec2 world_pos_start = vec2(window_world_start_x, window_world_start_y);
    vec2 world_scale = vec2(window_world_scale_x, window_world_scale_y);

    bool is_ok_x = (texel_coord.x >= world_pos_start.x) && (texel_coord.x < world_pos_start.x + window_world_scale_x * (world_max_x - world_min_x));
    bool is_ok_y = (texel_coord.y >= world_pos_start.y) && (texel_coord.y < world_pos_start.y + window_world_scale_y * (world_max_y - world_min_y));

    if (is_ok_x && is_ok_y) {
        pixel_color = pixel_color_bg;
    }
    else {
        pixel_color = vec4(0.1, 0.1, 0.1, 1.0) * pixel_color_bg;
    }

    for (int idx_circle = 0; idx_circle < num_circles; idx_circle++) {
        vec2 pos_window = world_pos_start + world_scale * circles[idx_circle].pos;
        vec3 color = circles[idx_circle].color;
        float r_window = world_scale.x * circles[idx_circle].r;
        // Distance measurements need to take into consideration that the two axes might
        //  be scaled differently.
        float d_x = pow(texel_coord.x - pos_window.x, 2);
        float d_y = (texel_coord.y - pos_window.y) * (world_scale.y / world_scale.x);
        d_y = d_y * d_y;
        float d = sqrt(d_x + d_y);

        if (d < r_window) {
            bool use_smoothing = true;
            if (use_smoothing && (d + 1 > r_window)) {
                float alpha = d - floor(d);
                pixel_color = alpha * pixel_color_bg + (1 - alpha) * vec4(color, 1);
            }
            else {
                pixel_color = vec4(color, 1);
            }
        }
    }

    imageStore(img_output, texel_coord, pixel_color);
}