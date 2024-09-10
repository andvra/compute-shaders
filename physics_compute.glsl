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

layout(std430, binding = 11) buffer layout_physics
{
    Physics physics[];
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

    if (idx_circle < num_circles) {
        float r = circles[idx_circle].r;
        vec2 cur_pos = physics[idx_circle].pos;
        vec2 cur_dir = normalize(physics[idx_circle].dir);
        vec2 move = step_ms * cur_dir;
        vec2 next_pos = cur_pos + move;

        if ((next_pos.x > world_max_x) || abs(next_pos.x - world_max_x) < r) {
            float t_collision = (world_max_x - cur_pos.x - r) / move.x;
            physics[idx_circle].pos.x = world_max_x - r - (1 - t_collision) * cur_dir.x;
            physics[idx_circle].dir.x = -physics[idx_circle].dir.x;
        }
        else if ((next_pos.x < world_min_x) || abs(next_pos.x - world_min_x) < r) {
            float t_collision = (cur_pos.x - r - world_min_x) / move.x;
            physics[idx_circle].pos.x = world_min_x + r - (1 - t_collision) * cur_dir.x;
            physics[idx_circle].dir.x = -physics[idx_circle].dir.x;
        }
        else {
            physics[idx_circle].pos.x = next_pos.x;
        }

        if ((next_pos.y > world_max_y) || abs(next_pos.y - world_max_y) < r) {
            float t_collision = (world_max_y - cur_pos.y - r) / move.y;
            physics[idx_circle].pos.y = world_max_y - r - (1 - t_collision) * cur_dir.y;
            physics[idx_circle].dir.y = -physics[idx_circle].dir.y;
        }
        else if ((next_pos.y < world_min_y) || abs(next_pos.y - world_min_y) < r) {
            float t_collision = (cur_pos.y - r - world_min_y) / move.y;
            physics[idx_circle].pos.y = world_min_y + r - (1 - t_collision) * cur_dir.y;
            physics[idx_circle].dir.y = -physics[idx_circle].dir.y;
        }
        else {
            physics[idx_circle].pos.y = next_pos.y;
        }

        // Only comparing to circles with higher indices is a way to avoid
        //  doing collision detection both ways (circle A --> circle B and circle B --> circle A)
        for (uint idx_other = idx_circle + 1; idx_other < num_circles; idx_other++) {
            vec2 pos_me = physics[idx_circle].pos;
            vec2 pos_other = physics[idx_other].pos;
            float r_me = circles[idx_circle].r;
            float r_other = circles[idx_other].r;
            float d = distance(pos_me, pos_other);

            bool does_collide = d < r_me + r_other;

            if (does_collide) {
                if (physics[idx_other].weight > physics[idx_circle].weight) {
                    physics[idx_other].pos = vec2(10, 10);
                }
                else {
                    physics[idx_circle].pos = vec2(10, 10);
                }

            }
        }
    }
}