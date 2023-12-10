#version 430 core

struct Mold_particle {
    float pos[2];
    float angle;
};

layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;
layout(rgba32f, binding = 0) uniform image2D img_output;
layout(location = 0) uniform int w;
layout(location = 1) uniform int h;
layout(location = 2) uniform int action_id;
layout(location = 3) uniform float t;

layout(std430, binding = 7) buffer layout_nonames
{
    Mold_particle mold_particles[];
};

void draw_objects(ivec2 texel_coord) {
    int idx = texel_coord.x + texel_coord.y * w;

    if (idx >= mold_particles.length()) {
        return;
    }

    ivec2 pos = ivec2(mold_particles[idx].pos[0], mold_particles[idx].pos[1]);

    vec4 pixel_color = vec4(0, 0.2, 0.3, 1);

    imageStore(img_output, pos, pixel_color);
}

void darken(ivec2 texel_coord) {
    if (texel_coord.x >= w || texel_coord.y >= h) {
        return;
    }

    vec4 cur_color = imageLoad(img_output, texel_coord).rgba;

    float reduce_factor = 0.01f;
    cur_color = cur_color - reduce_factor * vec4(1.0f, 1.0f, 1.0f, 0);
    cur_color.r = cur_color.r < 0 ? 0 : cur_color.r;
    cur_color.g = cur_color.g < 0 ? 0 : cur_color.g;
    cur_color.b = cur_color.b < 0 ? 0 : cur_color.b;

    imageStore(img_output, texel_coord, cur_color);
}

void move(ivec2 texel_coord) {
    int idx = texel_coord.x + texel_coord.y * w;

    if (idx >= mold_particles.length()) {
        return;
    }
  
    float new_x = mold_particles[idx].pos[0] + 1.0f * sin(mold_particles[idx].angle);
    float new_y = mold_particles[idx].pos[1] + 1.0f * cos(mold_particles[idx].angle);

    bool update_angle = false;
    bool do_move = true;
    if (new_x < 0 || new_x >= w) {
        new_x = clamp(new_x, 0, w - 1);
        update_angle = true;
        do_move = false;
    }
    if (new_y < 0 || new_y > h) {
        new_y = clamp(new_y, 0, h - 1);
        update_angle = true;
        do_move = false;
    }

    if (update_angle) {
        // A way to generate a "random" behavior
        float new_angle = 3.141593f * (1.0f + sin(t * float(idx)));
        mold_particles[idx].angle = new_angle;
    }
    if (do_move) {
        mold_particles[idx].pos[0] = new_x;
        mold_particles[idx].pos[1] = new_y;
    }
}

void main()
{
    ivec2 texel_coord = ivec2(gl_GlobalInvocationID.xy);

    switch (action_id) {
    case 0: move(texel_coord); break;
    case 1: darken(texel_coord); break;
    case 2: draw_objects(texel_coord); break;
    }
}