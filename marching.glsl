#version 430 core

struct Circle {
    float pos[2];
    float r;
    float color[3];
};

struct Block_id {
    int x;
    int y;
};

layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;
layout(rgba32f, binding = 0) uniform image2D imgOutput;
layout(location = 0) uniform int block_size;
layout(location = 1) uniform int w;
layout(location = 2) uniform int h;

layout(std430, binding = 3) buffer layout_circles
{
    Circle circles[];
};
layout(std430, binding = 4) buffer layout_blocks
{
    Block_id block_ids[];
};

void main()
{
    ivec2 texel_coord = ivec2(gl_GlobalInvocationID.xy);
    if (texel_coord.x > w || texel_coord.y > h) {
        return;
    }

    int this_block_id_x = texel_coord.x / block_size;
    int this_block_id_y = texel_coord.y / block_size;
    int block_x_min = this_block_id_x - 1;
    int block_x_max = this_block_id_x + 1;
    int block_y_min = this_block_id_y - 1;
    int block_y_max = this_block_id_y + 1;

    vec4 pixel_color = vec4(0, 0, 0, 1);
    float min_d = 1000000.0f;
    for (int i = 0; i < circles.length(); i++) {
		if (block_ids[i].x >= block_x_min && block_ids[i].x <= block_x_max && block_ids[i].y >= block_y_min && block_ids[i].y <= block_y_max) {
            float d = distance(texel_coord.xy, vec2(circles[i].pos[0], circles[i].pos[1]));
            float outer_d = d - circles[i].r;
            if (outer_d < 0) {
                pixel_color = vec4(0, 0, 0, 1);
                min_d = 0;
            }
            if ( outer_d < min_d && outer_d < 200) {
                min_d = outer_d;
                vec3 the_color = vec3(circles[i].color[0], circles[i].color[1], circles[i].color[2]);
                pixel_color = vec4(the_color, 1);
            }
        }
    }

    imageStore(imgOutput, texel_coord, pixel_color);
}