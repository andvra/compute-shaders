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
    int idx_particle = texel_coord.x + texel_coord.y * w;

    if (idx_particle >= mold_particles.length()) {
        return;
    }

    ivec2 pos = ivec2(mold_particles[idx_particle].pos[0], mold_particles[idx_particle].pos[1]);

    int idx_intensity = num_types * (pos.x + w * pos.y) + mold_particles[idx_particle].type;
    mold_intensity[idx_intensity] = 1.0;
}

void render(ivec2 texel_coord) {
    if (texel_coord.x >= w || texel_coord.y >= h) {
        return;
    }

    vec4 pixel_color = vec4(0, 0, 0, 1);

    vec4 colors[3] = vec4[3](
        vec4(0.0, 0.2, 0.3, 1.0),
        vec4(0.3, 0.7, 0.0, 1.0),
        vec4(0.7, 0.3, 0.0, 1.0)
        );

    int use_c = -1;
    float cur_intensity = -1.0;
    // do_blend == true: Add weighted intensities from the different channels
    // do_blend == false: Only render color from the channel with the highest intensity
    bool do_blend = false;
    for (int c = 0; c < num_types; c++) {
        int idx = num_types * (texel_coord.x + w * texel_coord.y) + c;
        if(!do_blend && mold_intensity[idx] > cur_intensity){
            use_c = c;
            cur_intensity = mold_intensity[idx];
        }
        if (do_blend) {
            vec4 cur_color = vec4(1, 1, 1, 1);
            if (colors.length() > c) {
                cur_color = colors[c];
            }
            pixel_color += mold_intensity[idx] * cur_color;
        }
    }

    if (!do_blend && (use_c > -1)) {
        pixel_color = cur_intensity * colors[use_c];
    }

    pixel_color.r = min(pixel_color.r, 1);
    pixel_color.g = min(pixel_color.g, 1);
    pixel_color.b = min(pixel_color.b, 1);
    pixel_color.a = min(pixel_color.a, 1);

    imageStore(img_output, texel_coord, pixel_color);
}

void darken(ivec2 texel_coord) {
    if (texel_coord.x >= w || texel_coord.y >= h) {
        return;
    }

    float reduce_factor = t_delta;

    for (int c = 0; c < num_types; c++) {
        int idx = num_types * (texel_coord.x + w * texel_coord.y) + c;
        mold_intensity[idx] = max(0, mold_intensity[idx] - reduce_factor);
    }
}

float get_area_value(ivec2 pos_center, int r, int mold_type) {
    float ret = 0;
    int num_pixels = 0;

    for (int x = max(0, pos_center.x - r); x < min(w - 1, pos_center.x + r); x++) {
        for (int y = max(0, pos_center.y - r); y < min(h - 1, pos_center.y + r); y++) {
            for (int c = 0; c < num_types; c++) {
                int idx = num_types * (x + y * w) + c;
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
        float new_angle = PI * (1.0f + sin(t_tot * float(idx)));
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
    case 2: release_mold(texel_coord); break;
    case 3: render(texel_coord); break;
    }
}