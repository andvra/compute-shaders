#define PI 3.1415926535897932384626433832795f

layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;
layout(rgba32f, binding = 0) uniform image2D img_output;
layout(location = 0) uniform int image_width;
layout(location = 1) uniform int image_height;
layout(location = 2) uniform int action_id;
layout(location = 3) uniform float pseudo_random_float;
layout(location = 4) uniform float t_step_ms;   // Pre-defined step length
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

    int num_line_steps = 10;
    vec2 pos_last = mold_particles[idx_particle].pos;
    vec2 pos_cur = mold_particles[idx_particle].pos_last;

    // TODO: This is a primitive line drawing algorithm. Use a better one, with anti-aliasing and no upper limit
    //  to the number of steps required
    for (int idx_step = 0; idx_step < num_line_steps; idx_step++) {
        vec2 pos_write = pos_cur + idx_step * (pos_last - pos_cur) / float(num_line_steps - 1);
        ivec2 pos = ivec2(pos_write);

        int idx_intensity = num_types * (pos.x + image_width * pos.y) + mold_particles[idx_particle].type;
        mold_intensity[idx_intensity] = 1.0;
    }
}

void darken(ivec2 texel_coord) {
    if (texel_coord.x >= image_width || texel_coord.y >= image_height) {
        return;
    }

    float reduce_factor = t_step_ms / 1000.0f;

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

    float factor_distance_px = 10.0f;
    int search_radius_px = 5;

    int pos_x_left = int(mold_particles[idx].pos.x + factor_distance_px * cos(mold_particles[idx].angle + PI / 4.0f));
    int pos_y_left = int(mold_particles[idx].pos.y + factor_distance_px * sin(mold_particles[idx].angle + PI / 4.0f));
    int pos_x_fwd = int(mold_particles[idx].pos.x + factor_distance_px * cos(mold_particles[idx].angle));
    int pos_y_fwd = int(mold_particles[idx].pos.y + factor_distance_px * sin(mold_particles[idx].angle));
    int pos_x_right = int(mold_particles[idx].pos.x + factor_distance_px * cos(mold_particles[idx].angle - PI / 4.0f));
    int pos_y_right = int(mold_particles[idx].pos.y + factor_distance_px * sin(mold_particles[idx].angle - PI / 4.0f));

    float val_left = get_area_value(ivec2(pos_x_left, pos_y_left), search_radius_px, mold_particles[idx].type);
    float val_fwd = get_area_value(ivec2(pos_x_fwd, pos_y_fwd), search_radius_px, mold_particles[idx].type);
    float val_right = get_area_value(ivec2(pos_x_right, pos_y_right), search_radius_px, mold_particles[idx].type);
    
    float abs_left = abs(val_left);
    float abs_right = abs(val_right);
    float abs_fwd = abs(val_fwd);

    bool is_largest_left = abs_left > abs_right && abs_left > abs_fwd;
    bool is_largest_right = abs_right > abs_left && abs_right > abs_fwd;

    float factor_rotate = 2 * PI * 0.015f;

    if (is_largest_left) {
        mold_particles[idx].angle += factor_rotate * t_step_ms;
    }

    if (is_largest_right) {
        mold_particles[idx].angle -= factor_rotate * t_step_ms;
    }

    float factor_move = 0.1f;
    float new_x = mold_particles[idx].pos.x + factor_move * t_step_ms * cos(mold_particles[idx].angle);
    float new_y = mold_particles[idx].pos.y + factor_move * t_step_ms * sin(mold_particles[idx].angle);

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
        float new_angle = PI * (1.0f + sin(pseudo_random_float * float(idx)));
        mold_particles[idx].angle = new_angle;
    }

    if (do_move) {
        mold_particles[idx].pos_last = mold_particles[idx].pos;
        mold_particles[idx].pos = vec2(new_x, new_y);
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