#version 430 core

struct Circle {
    float pos[2];
    float r;
    float color[3];
};

layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;
layout(rgba32f, binding = 0) uniform image2D imgOutput;
layout(std430, binding = 2) buffer layout_circles
{
    Circle circles[];
};

const float w = 1200.0f;
const float h = 900.0f;

void main()
{
    ivec2 texel_coord = ivec2(gl_GlobalInvocationID.xy);
    if (texel_coord.x > w || texel_coord.y > h) {
        return;
    }

    vec4 pixel_color = vec4(0, 0, 0, 1);
    float min_d = 1000000.0f;
    for (int i = 0; i < circles.length(); i++) {
        float d = distance(texel_coord.xy, vec2(circles[i].pos[0], circles[i].pos[1]));
        float outer_d = d - circles[i].r;
        if (outer_d < 0) {
            pixel_color = vec4(0, 0, 0, 1);
            min_d = 0;
        }
        if (outer_d > 0.0f && outer_d < min_d && outer_d < 100){
            min_d = outer_d;
            vec3 the_color = vec3(circles[i].color[0], circles[i].color[1], circles[i].color[2]);
            pixel_color = vec4(the_color, 1);
        }
    }

    imageStore(imgOutput, texel_coord, pixel_color);
}