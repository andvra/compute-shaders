#version 430 core

layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;
layout(std430, binding = 0) buffer layoutName
{
    int data_SSBO [];
};

void main()
{
    ivec2 texelCoord = ivec2(gl_GlobalInvocationID.xy);

    // These few lines are what we use to try out the SSBO capability of compute shaders
    if (texelCoord.x == 0 && texelCoord.y < 1000)
    {
        data_SSBO[texelCoord.y] *= 2;
    }
}