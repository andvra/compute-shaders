#define PI 3.1415926535897932384626433832795f

layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;
layout(rgba32f, binding = 0) uniform image2D img_output;
layout(location = 0) uniform int image_width;
layout(location = 1) uniform int image_height;
layout(location = 2) uniform int action_id;
layout(location = 3) uniform float t_tot;
layout(location = 4) uniform float t_delta;
layout(location = 5) uniform int num_types;

layout(std430, binding = 7) buffer layout_mold_particles
{
    Mold_particle mold_particles[];
};

layout(std430, binding = 8) buffer layout_mold_intensity
{
    float mold_intensity[];
};

void release_mold(ivec2 texel_coord) {
    int idx_particle = texel_coord.x + texel_coord.y * image_width;

    if (idx_particle >= mold_particles.length()) {
        return;
    }

    ivec2 pos = ivec2(mold_particles[idx_particle].pos);

    int idx_intensity = num_types * (pos.x + image_width * pos.y) + mold_particles[idx_particle].type;
    mold_intensity[idx_intensity] = 1.0;
}

void darken(ivec2 texel_coord) {
    if (texel_coord.x >= image_width || texel_coord.y >= image_height) {
        return;
    }

    float reduce_factor = t_delta;

    for (int c = 0; c < num_types; c++) {
        int idx = num_types * (texel_coord.x + image_width * texel_coord.y) + c;
        mold_intensity[idx] = max(0, mold_intensity[idx] - reduce_factor);
    }
}

float get_area_value(ivec2 pos_center, int r, int mold_type) {
    float ret = 0;
    int num_pixels = 0;

    for (int x = max(0, pos_center.x - r); x < min(image_width - 1, pos_center.x + r); x++) {
        for (int y = max(0, pos_center.y - r); y < min(image_height - 1, pos_center.y + r); y++) {
            for (int c = 0; c < num_types; c++) {
                int idx = num_types * (x + y * image_width) + c;
                if(c == mold_type){
                    ret += mold_intensity[idx];
                }
                else {
                    ret -= mold_intensity[idx];
                }
            }
            num_pixels++;
        }
    }

    ret /= float(num_pixels);

    return ret;
}

void move(ivec2 texel_coord) {
    int idx = texel_coord.x + texel_coord.y * image_width;

    if (idx >= mold_particles.length()) {
        return;
    }

    int pos_x_left = int(mold_particles[idx].pos.x + 10.0f * cos(mold_particles[idx].angle + PI / 4.0f));
    int pos_y_left = int(mold_particles[idx].pos.y + 10.0f * sin(mold_particles[idx].angle + PI / 4.0f));
    int pos_x_fwd = int(mold_particles[idx].pos.x + 10.0f * cos(mold_particles[idx].angle));
    int pos_y_fwd = int(mold_particles[idx].pos.y + 10.0f * sin(mold_particles[idx].angle));
    int pos_x_right = int(mold_particles[idx].pos.x + 10.0f * cos(mold_particles[idx].angle - PI / 4.0f));
    int pos_y_right = int(mold_particles[idx].pos.y + 10.0f * sin(mold_particles[idx].angle - PI / 4.0f));

    int search_radius_px = 5;

    float val_left = get_area_value(ivec2(pos_x_left, pos_y_left), search_radius_px, mold_particles[idx].type);
    float val_fwd = get_area_value(ivec2(pos_x_fwd, pos_y_fwd), search_radius_px, mold_particles[idx].type);
    float val_right = get_area_value(ivec2(pos_x_right, pos_y_right), search_radius_px, mold_particles[idx].type);
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
    float new_x = mold_particles[idx].pos.x + move_factor * t_delta * cos(mold_particles[idx].angle);
    float new_y = mold_particles[idx].pos.y + move_factor * t_delta * sin(mold_particles[idx].angle);

    bool update_angle = false;
    bool do_move = true;
    bool is_out_of_bounds = false;

    if (new_x < 0 || new_x >= image_width) {
        is_out_of_bounds = true;
    }

    if (new_y < 0 || new_y >= image_height) {
        is_out_of_bounds = true;
    }

    if (is_out_of_bounds) {
        new_x = clamp(new_x, 0, image_width - 1);
        new_y = clamp(new_y, 0, image_height - 1);
        update_angle = true;
        do_move = false;
    }

    if (update_angle) {
        // A way to generate a "random" behavior
        float new_angle = PI * (1.0f + sin(t_tot * float(idx)));
        mold_particles[idx].angle = new_angle;
    }

    if (do_move) {
        mold_particles[idx].pos.x = new_x;
        mold_particles[idx].pos.y = new_y;
    }
}

void main()
{
    ivec2 texel_coord = ivec2(gl_GlobalInvocationID.xy);

    switch (action_id) {
    case 0: move(texel_coord); break;
    case 1: darken(texel_coord); break;
    case 2: release_mold(texel_coord); break;
    }
}