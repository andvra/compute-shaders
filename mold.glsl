#version 430 core
#define PI 3.1415926535897932384626433832795f

struct Mold_particle {
    float pos[2];
    float angle;
    int type;
};

layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;
layout(rgba32f, binding = 0) uniform image2D img_output;
layout(location = 0) uniform int w;
layout(location = 1) uniform int h;
layout(location = 2) uniform int action_id;
layout(location = 3) uniform float t_tot;
layout(location = 4) uniform float t_delta;

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

    vec4 pixel_color = vec4(0.0, 0.2, 0.3, 1.0);
    if (mold_particles[idx].type == 1) {
        pixel_color = vec4(0.3, 0.2, 0.0, 1.0);
    }
    if (mold_particles[idx].type == 2) {
        pixel_color = vec4(0.2, 0.3, 0.0, 1.0);
    }

    imageStore(img_output, pos, pixel_color);
}

void darken(ivec2 texel_coord) {
    if (texel_coord.x >= w || texel_coord.y >= h) {
        return;
    }

    vec4 cur_color = imageLoad(img_output, texel_coord).rgba;

    float reduce_factor = t_delta;
    cur_color = cur_color - reduce_factor * vec4(1.0f, 1.0f, 1.0f, 0);
    cur_color.r = cur_color.r < 0 ? 0 : cur_color.r;
    cur_color.g = cur_color.g < 0 ? 0 : cur_color.g;
    cur_color.b = cur_color.b < 0 ? 0 : cur_color.b;

    imageStore(img_output, texel_coord, cur_color);
}

float get_area_value(ivec2 pos_center, int r) {
    float ret = 0;
    int num_pixels = 0;

    for (int x = max(0, pos_center.x - r); x < min(w - 1, pos_center.x + r); x++) {
        for (int y = max(0, pos_center.y - r); y < min(h - 1, pos_center.y + r); y++) {
            vec3 the_rgb = imageLoad(img_output, ivec2(x, y)).rgb;
            ret += max(max(the_rgb.r, the_rgb.g), the_rgb.b);
            num_pixels++;
        }
    }

    ret /= float(num_pixels);

    return ret;
}

void move(ivec2 texel_coord) {
    int idx = texel_coord.x + texel_coord.y * w;

    if (idx >= mold_particles.length()) {
        return;
    }

    int pos_x_left = int(mold_particles[idx].pos[0] + 10.0f * cos(mold_particles[idx].angle + PI / 4.0f));
    int pos_y_left = int(mold_particles[idx].pos[1] + 10.0f * sin(mold_particles[idx].angle + PI / 4.0f));
    int pos_x_fwd = int(mold_particles[idx].pos[0] + 10.0f * cos(mold_particles[idx].angle));
    int pos_y_fwd = int(mold_particles[idx].pos[1] + 10.0f * sin(mold_particles[idx].angle));
    int pos_x_right = int(mold_particles[idx].pos[0] + 10.0f * cos(mold_particles[idx].angle - PI / 4.0f));
    int pos_y_right = int(mold_particles[idx].pos[1] + 10.0f * sin(mold_particles[idx].angle - PI / 4.0f));

    float val_left = get_area_value(ivec2(pos_x_left, pos_y_left), 5);
    float val_fwd = get_area_value(ivec2(pos_x_fwd, pos_y_fwd), 5);
    float val_right = get_area_value(ivec2(pos_x_right, pos_y_right), 5);
    float max_val = max(max(val_left, val_fwd), val_right);

    if (max_val > 0) {
        if (max_val == val_left && max_val > 0) {
            mold_particles[idx].angle += 100.0f * t_delta;
        }
        if (max_val == val_right) {
            mold_particles[idx].angle -= 100.0f * t_delta;
        }
    }

    float move_factor = 100.0f;
    float new_x = mold_particles[idx].pos[0] + move_factor * t_delta * cos(mold_particles[idx].angle);
    float new_y = mold_particles[idx].pos[1] + move_factor * t_delta * sin(mold_particles[idx].angle);

    bool update_angle = false;
    bool do_move = true;
    bool is_out_of_bounds = false;

    if (new_x < 0 || new_x >= w) {
        is_out_of_bounds = true;
    }

    if (new_y < 0 || new_y >= h) {
        is_out_of_bounds = true;
    }

    if (is_out_of_bounds) {
        new_x = clamp(new_x, 0, w - 1);
        new_y = clamp(new_y, 0, h - 1);
        update_angle = true;
        do_move = false;
    }

    if (update_angle) {
        // A way to generate a "random" behavior
        float new_angle = 3.141593f * (1.0f + sin(t_tot * float(idx)));
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