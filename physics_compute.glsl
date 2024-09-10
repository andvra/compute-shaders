layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;
layout(rgba32f, binding = 0) uniform image2D img_output;
layout(location = 0) uniform float world_min_x;
layout(location = 1) uniform float world_max_x;
layout(location = 2) uniform float world_min_y;
layout(location = 3) uniform float world_max_y;
layout(location = 4) uniform float step_ms;

layout(std430, binding = 9) buffer layout_circles
{
    Circle circles[];
};

void main()
{
    uint workgroup_size_x = gl_WorkGroupSize.x;
    uint workgroup_size_y = gl_WorkGroupSize.y;
    uint workgroup_size_z = gl_WorkGroupSize.z;
    uint cur_group_x = gl_GlobalInvocationID.x;
    uint cur_group_y = gl_GlobalInvocationID.y;
    uint cur_group_z = gl_GlobalInvocationID.z;

    uint idx_circle = cur_group_x +
        cur_group_y * workgroup_size_x +
        cur_group_z * workgroup_size_x * workgroup_size_y;

    uint num_circles = circles.length();

    if(idx_circle < num_circles) {
        circles[idx_circle].pos.x += step_ms;
        if (circles[idx_circle].pos.x + circles[idx_circle].r >= world_max_x) {
            circles[idx_circle].pos.x -= (world_max_x - world_min_x - 2 * circles[idx_circle].r);
        }
    }
}