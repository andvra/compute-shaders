struct Block_id {
    int x;
    int y;
};

struct Toolbar_info {
    int x;
    int y;
    int w;
    int h;
    int border_height;
};

layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;
layout(rgba32f, binding = 0) uniform image2D img_output;
layout(location = 0) uniform int block_size;
layout(location = 1) uniform int w;
layout(location = 2) uniform int h;
layout(location = 3) uniform bool use_toolbar_alpha;
layout(location = 4) uniform float toolbar_opacity;

layout(std430, binding = 3) buffer layout_circles
{
    Circle circles[];
};
layout(std430, binding = 4) buffer layout_blocks
{
    Block_id block_ids[];
};
layout(std430, binding = 5) buffer layout_toolbar_info
{
    Toolbar_info toolbar_info;
};
layout(std430, binding = 6) buffer layout_toolbar_pixels
{
    float toolbar_colors[];
};

void main()
{
    ivec2 texel_coord = ivec2(gl_GlobalInvocationID.xy);
    if (texel_coord.x > w || texel_coord.y > h) {
        return;
    }

    vec4 pixel_color_scene = vec4(0, 0, 0, 1);
    vec4 pixel_color_toolbar = vec4(0, 0, 0, 1);

    bool within_toolbar_x = (texel_coord.x >= toolbar_info.x && texel_coord.x < (toolbar_info.x + toolbar_info.w));
    bool within_toolbar_y = (texel_coord.y >= toolbar_info.y && texel_coord.y < (toolbar_info.y + toolbar_info.h));
    bool within_toolbar = within_toolbar_x && within_toolbar_y;

    if (within_toolbar) {
        int x_rel = texel_coord.x - toolbar_info.x;
        int y_rel = texel_coord.y - toolbar_info.y;
        int idx_r = 3 * (x_rel + y_rel * toolbar_info.w) + 0;
        int idx_g = 3 * (x_rel + y_rel * toolbar_info.w) + 1;
        int idx_b = 3 * (x_rel + y_rel * toolbar_info.w) + 2;
        float rr = toolbar_colors[idx_r];
        float gg = toolbar_colors[idx_g];
        float bb = toolbar_colors[idx_b];
        pixel_color_toolbar = vec4(rr, gg, bb, 1);
    }
    if(use_toolbar_alpha || !within_toolbar) {
        int this_block_id_x = texel_coord.x / block_size;
        int this_block_id_y = texel_coord.y / block_size;
        int block_x_min = this_block_id_x - 1;
        int block_x_max = this_block_id_x + 1;
        int block_y_min = this_block_id_y - 1;
        int block_y_max = this_block_id_y + 1;

        float min_d = 1000000.0f;
        float max_d = 200 * 200;
        for (int i = 0; i < circles.length(); i++) {
            if (block_ids[i].x >= block_x_min && block_ids[i].x <= block_x_max && block_ids[i].y >= block_y_min && block_ids[i].y <= block_y_max) {
                vec2 v = texel_coord.xy - vec2(circles[i].pos[0], circles[i].pos[1]);
                float d = dot(v, v);
                float outer_d = d - circles[i].r_square;
                if (outer_d < 0.0f) {
                    pixel_color_scene = vec4(0, 0, 0, 1);
                    min_d = 0;
                    break;
                }
                if (outer_d > 0.0f && outer_d < min_d && outer_d < max_d) {
                    min_d = outer_d;
                    vec3 the_color = vec3(circles[i].color[0], circles[i].color[1], circles[i].color[2]);
                    pixel_color_scene = vec4(the_color, 1);
                }
            }
        }
    }

    vec4 pixel_color = pixel_color_scene;

    if (within_toolbar) {
        if (use_toolbar_alpha) {
            int y_rel = texel_coord.y - toolbar_info.y;
            pixel_color_toolbar.a = 0.0f;
            if (y_rel < toolbar_info.h - toolbar_info.border_height) {
                pixel_color_toolbar.a = 1.0 - toolbar_opacity;
            }
            pixel_color = vec4(mix(pixel_color_toolbar.rgb, pixel_color_scene.rgb, pixel_color_toolbar.a), 1.0f);

        }
        else {
            pixel_color = pixel_color_toolbar;
        }
    }

    imageStore(img_output, texel_coord, pixel_color);
}