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

    if (idx_circle >= num_circles) {
        return;
    }


    // TODO: Add a pass first where we see what happens first - collision with any of the objects or the walls?
    //  If another object, which one?





    float r = circles[idx_circle].r;
    vec2 pos_initial = physics[idx_circle].pos;
    vec2 dir_initial = normalize(physics[idx_circle].dir);
    float speed = physics[idx_circle].speed;
    vec2 move = step_ms * speed * dir_initial;
    vec2 pos_next = pos_initial + move;

    if ((pos_next.x > world_max_x) || abs(pos_next.x - world_max_x) < r) {
        float t_collision = (world_max_x - pos_initial.x - r) / move.x;
        physics[idx_circle].pos.x = world_max_x - r - (1 - t_collision) * dir_initial.x;
        physics[idx_circle].dir.x = -physics[idx_circle].dir.x;
    }
    else if ((pos_next.x < world_min_x) || abs(pos_next.x - world_min_x) < r) {
        float t_collision = (pos_initial.x - r - world_min_x) / move.x;
        physics[idx_circle].pos.x = world_min_x + r - (1 - t_collision) * dir_initial.x;
        physics[idx_circle].dir.x = -physics[idx_circle].dir.x;
    }
    else {
        physics[idx_circle].pos.x = pos_next.x;
    }

    if ((pos_next.y > world_max_y) || abs(pos_next.y - world_max_y) < r) {
        float t_collision = (world_max_y - pos_initial.y - r) / move.y;
        physics[idx_circle].pos.y = world_max_y - r - (1 - t_collision) * dir_initial.y;
        physics[idx_circle].dir.y = -physics[idx_circle].dir.y;
    }
    else if ((pos_next.y < world_min_y) || abs(pos_next.y - world_min_y) < r) {
        float t_collision = (pos_initial.y - r - world_min_y) / move.y;
        physics[idx_circle].pos.y = world_min_y + r - (1 - t_collision) * dir_initial.y;
        physics[idx_circle].dir.y = -physics[idx_circle].dir.y;
    }
    else {
        physics[idx_circle].pos.y = pos_next.y;
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
            float t_collision = ((r_me + r_other) - d) / distance(pos_initial, pos_me);
            float t_after_collision = 1 - t_collision;
            float s1 = physics[idx_circle].speed;
            float m1 = physics[idx_circle].mass;
            vec2 v1 = s1 * physics[idx_circle].dir;
            vec2 x1 = physics[idx_circle].pos;
            float s2 = physics[idx_other].speed;
            float m2 = physics[idx_other].mass;
            vec2 v2 = s2 * physics[idx_other].dir;
            vec2 x2 = physics[idx_other].pos;

            float d = length(x1 - x2);
            float d_square = d * d;

            vec2 v1_new = v1 - (2 * m2 / (m1 + m2)) * (dot(v1 - v2, x1 - x2) / d_square) * (x1 - x2);
            vec2 v2_new = v2 - (2 * m1 / (m1 + m2)) * (dot(v2 - v1, x2 - x1) / d_square) * (x2 - x1);

            if (m1 * length(v1_new) + m2 * length(v2_new) > 1.2 * (m1 * length(v1) + m2 * length(v2))) {
                circles[idx_circle].color[0] = 0;
            }

            physics[idx_circle].dir = normalize(v1_new);
            physics[idx_circle].speed = length(v1_new);
            physics[idx_other].dir = normalize(v2_new);
            physics[idx_circle].speed = length(v2_new);

        }
    }
}