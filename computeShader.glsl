#version 430 core

layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;
layout(rgba32f, binding = 0) uniform image2D imgOutput;
layout(location = 0) uniform float t;
layout(location = 1) uniform vec2 mouse_pos;
layout(location = 2) uniform vec2 background_center;
layout(location = 3) uniform int w;
layout(location = 4) uniform int h;

vec4 draw_crosshair(vec2 texel_coord, vec4 pixel_color)
{
    float dx = abs(mouse_pos.x - texel_coord.x);
    float dy = abs(h - mouse_pos.y - texel_coord.y);
    float crosshair_width = 2;
    float crosshair_height = 15;

    if ((dx < crosshair_width && dy < crosshair_height) || (dx < crosshair_height && dy < crosshair_width))
    {
        pixel_color.x = 1;
        pixel_color.y = 1;
        pixel_color.z = 1;
    }

    return pixel_color;
}

void main()
{
    ivec2 texel_coord = ivec2(gl_GlobalInvocationID.xy);

    if (texel_coord.x > w || texel_coord.y > h) {
        return;
    }

    vec4 pixel_color = vec4(0, 0, 0, 1);

    float d1 = distance(texel_coord, ivec2(background_center.x + 10 * sin(t), background_center.y + 15 * cos(t)));
    float d2 = distance(texel_coord, ivec2(mouse_pos.x + 100 * sin(t + 0.2), h - mouse_pos.y + 60 * cos(t + 0.5)));
    pixel_color.x = sin(d1 / 10);
    pixel_color.y = 0.5 + 0.5 * sin(d2 / 20);

    pixel_color = draw_crosshair(texel_coord, pixel_color);

    imageStore(imgOutput, texel_coord, pixel_color);
}