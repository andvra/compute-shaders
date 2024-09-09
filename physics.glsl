#version 430 core

layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;
layout(rgba32f, binding = 0) uniform image2D img_output;

layout(std430, binding = 0) buffer layoutName
{
    int data_SSBO [];
};

void main()
{
    ivec2 texel_coord = ivec2(gl_GlobalInvocationID.xy);

    vec4 pixel_color = vec4(0.3, texel_coord.y%100 / 100.0, 0, 1);

    imageStore(img_output, texel_coord, pixel_color);
}