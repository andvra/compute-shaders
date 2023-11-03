# version 430 core

struct Sphere {
	float position[3];
	float r;
	float color[3];
};

struct Shared_data {
	int host_idx_selected_sphere;
	int device_idx_selected_sphere;
};

layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;
layout(rgba32f, binding = 0) uniform image2D imgOutput;
layout(location = 0) uniform float t;
layout(location = 1) uniform vec2 mouse_pos;
layout(location = 2) uniform vec2 background_center;
layout(std430, binding = 0) buffer layout_spheres
{
	Sphere spheres[3];
};
layout(std430, binding = 1) buffer layout_shared_data
{
	Shared_data shared_data;
};

#define PI 3.1415926538

const int num_triangles = 2;
const int num_spheres = 3;
const int num_vertices = 4;
vec3 the_vertices[num_vertices];
vec4 the_spheres[num_spheres]; // x y z r
ivec3 the_triangles[num_triangles];// Consist of indices of the_vertices
vec3 the_camera;
vec3 the_focus;
const float w = 1200.0f;
const float h = 900.0f;

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

struct Pixel_info {
	vec4 color;
	float distance;
};

struct Collision_info {
	Pixel_info pixel;
	bool did_hit;
	vec3 collision_point;
	vec3 collision_direction;
};

Collision_info do_triangles(float min_distance, vec3 ray_start_pos, vec3 ray) {
	Collision_info ret;
	ret.did_hit = false;

	for (int idx_triangle = 0; idx_triangle < num_triangles; idx_triangle++) {
		vec3 current_vertices[3];
		ivec3 current_triangle = the_triangles[idx_triangle];
		current_vertices[0] = the_vertices[current_triangle.x];
		current_vertices[1] = the_vertices[current_triangle.y];
		current_vertices[2] = the_vertices[current_triangle.z];
		vec3 p0 = (current_vertices[0] + current_vertices[1] + current_vertices[2]) / 3.0f;
		vec3 l0 = ray_start_pos;
		vec3 n = normalize(cross(current_vertices[1] - current_vertices[0], current_vertices[2] - current_vertices[1]));
		float d = dot(p0 - l0, n) / dot(ray, n);
		vec3 plane_intersect_point = l0 + ray * d;

		float distance_from_camera = distance(plane_intersect_point, ray_start_pos);
		if (distance_from_camera < min_distance) {
			float tot_angle = 0.0f;
			for (int idx_sub_triangle = 0; idx_sub_triangle < 3; idx_sub_triangle++) {
				vec3 v1 = normalize(current_vertices[(0 + idx_sub_triangle) % 3] - plane_intersect_point);
				vec3 v2 = normalize(current_vertices[(1 + idx_sub_triangle) % 3] - plane_intersect_point);
				float dot_res = min(1.0, dot(v1, v2));
				tot_angle += acos(dot_res);
			}
			// Are we inside the triangle?
			if (abs(tot_angle - 2 * PI) < 0.01f) {
				vec4 pixel_color_side_one = vec4(0.8, 0.2, 0.05, 1);
				vec4 pixel_color_side_two = vec4(0.9, 0.4, 0.7, 1);
				vec4 pixel_color_band = vec4(1, 1, 1, 1);
				float sin_val = sin(10.0f * (plane_intersect_point.z / 10.0f + t));
				ret.pixel.color = pixel_color_side_one;
				float band_width = 1.0f;
				if (sin_val < plane_intersect_point.x) {
					ret.pixel.color = pixel_color_side_two;
				}
				else if (sin_val < plane_intersect_point.x + band_width) {
					float mix_factor = (sin_val - plane_intersect_point.x) / band_width; // 0 <= mix_factor <= 1
					ret.pixel.color = mix_factor * pixel_color_side_one + (1.0f - mix_factor) * pixel_color_side_two;
					float mix_factor2 = 0.15f * (sin(5 * t) + 1.0f) + 0.7f;
					ret.pixel.color = mix_factor2 * ret.pixel.color + (1 - mix_factor2) * pixel_color_band;

				}
				ret.pixel.distance = distance_from_camera;
				ret.did_hit = true;
				ret.collision_point = plane_intersect_point;
				// https://math.stackexchange.com/questions/13261/how-to-get-a-reflection-vector
				ret.collision_direction = ray - 2 * dot(ray, n) * n;
			}
			// This gives the nice flower effect
			// NB this is possible not good to keep, it doesn't follow the structure above
			if (abs(tot_angle - PI) < 0.01f) {
				ret.pixel.color = vec4(1, 0, 1, 1);
				ret.did_hit = true;
			}
		}
	}

	return ret;
}

Collision_info do_spheres(float min_distance, vec3 ray_start_pos, vec3 ray, bool do_color) {
	Collision_info ret;
	ret.did_hit = false;

	for (int i = 0; i < 3; i++) {
		vec3 sphere_pos = vec3(spheres[i].position[0], spheres[i].position[1], spheres[i].position[2]);
		float sphere_rad = spheres[i].r;
		vec4 sphere_color = vec4(spheres[i].color[0], spheres[i].color[1], spheres[i].color[2], 1);
		if (shared_data.host_idx_selected_sphere == i) {
			sphere_color = vec4(0.5 * sphere_color.xyz + vec3(0.5, 0.5, 0.5), 1);
		}
		float a = 1.0f;
		float b = 2.0f * dot(ray, ray_start_pos - sphere_pos);
		float c = dot(ray_start_pos - sphere_pos, ray_start_pos - sphere_pos) - sphere_rad * sphere_rad;
		// f(x) = a*x^2 + b*x + c = 0
		// ==> x^2 + (b/a)*x + c/a = 0
		// ==> pq-formula
		float p = b / a;
		float q = c / a;
		float root_inner = p * p / 4.0 - q;
		if (root_inner > 0) {
			// We have a collision
			float root_sqrt = sqrt(root_inner);
			float root_1 = -p / 2.0f + root_sqrt;
			float root_2 = -p / 2.0f - root_sqrt;
			float use_root = 0.0f;
			if (root_1 > 0.0f) {
				use_root = root_1;
			}
			if (root_2 > 0.0f && root_2 < use_root) {
				use_root = root_2;
			}
			if (use_root != 0.0f) {
				vec3 collision_point = vec3(ray_start_pos + use_root * ray);
				float the_distance = distance(collision_point, ray_start_pos);
				if (the_distance < min_distance) {
					vec3 v1 = collision_point - sphere_pos;
					vec3 v2 = collision_point - ray_start_pos;
					float angle = acos(dot(v1, v2) / (length(v1) * length(v2)));
					float angle_normalized = 2.0f * (angle / 3.1415f - 0.5f);
					if (do_color) {
						shared_data.device_idx_selected_sphere = i;
					}

					ret.pixel.color = sphere_color * angle_normalized;
					ret.pixel.distance = the_distance;
					ret.did_hit = true;
					ret.collision_point = collision_point;
					ret.collision_direction = collision_point - sphere_pos;
				}
			}
		}
	}

	return ret;
}

void main()
{
	ivec2 texel_coord = ivec2(gl_GlobalInvocationID.xy);
	vec3 the_up;
	vec4 bg_color;

	float fov_h = 60.0f;
	float fov_v = fov_h * h / w;
	// Defining -1 <= x <= 1 gives us this distance to (render) screen:
	// tan (fov_H/2) = opp/adj =>
	// adj = opp/tan(fov_H/2) =
	// adj = 1/tan(fov_H/2)
	float dist_to_render_screen = 1.0f / tan(radians(fov_h / 2.0f));

	the_camera = vec3(20, 10 + 15 * sin(t), 5);
	the_focus = vec3(0, 0, 0);
	the_up = vec3(0, 1, 0);
	bg_color = vec4(0.4, 0.3, 0.5 + 0.3 * sin(5.0 * t + texel_coord.x / 300.0f), 1);

	the_vertices[0] = vec3(-10, 0, -10);
	the_vertices[1] = vec3(-10, 0, 10);
	the_vertices[2] = vec3(10, 0, 10);
	the_vertices[3] = vec3(10, 0, -10);

	the_triangles[0] = ivec3(0, 1, 2);
	the_triangles[1] = ivec3(2, 3, 0);

	the_spheres[0] = vec4(0, 0, 0, 2);
	the_spheres[1] = vec4(5, 1, -2, 2);
	the_spheres[2] = vec4(5, 2, 2, 2);

	vec3 render_screen_x = normalize(cross(normalize(the_focus - the_camera), normalize(the_up)));
	vec3 render_screen_y = normalize(cross(render_screen_x, normalize(the_focus - the_camera)));

	vec3 render_screen_pixel = the_camera + dist_to_render_screen * normalize(the_focus - the_camera) + (2 * render_screen_x * (float(texel_coord.x) / w - 0.5f)) + (2 * render_screen_y * (float(texel_coord.y) / h - 0.5f));
	vec3 ray = normalize(render_screen_pixel - the_camera);

	bool do_color = false;

	if (texel_coord.y == (h - mouse_pos.y) && texel_coord.x == mouse_pos.x){
		do_color = true;
	}

	const float min_distance = 10000;
	Pixel_info pixel = Pixel_info(bg_color, min_distance);

	const int max_bounces = 3;
	vec4 bounce_color[max_bounces];
	float bounce_reflectivity[max_bounces];	// 0 - 1
	int actual_bounces = 0;
	int idx_bounce;

	for (idx_bounce = 0; idx_bounce < max_bounces; idx_bounce++) {
		float cur_distance = min_distance;
		Collision_info collision_info[2];
		Collision_info best_collision_info;
		best_collision_info.did_hit = false;

		for (int idx_type = 0; idx_type < 2; idx_type++) {
			switch (idx_type) {
			case 0:
				collision_info[idx_type] = do_triangles(cur_distance, the_camera, ray);
				break;
			case 1:
				collision_info[idx_type] = do_spheres(cur_distance, the_camera, ray, do_color);
				break;
			}

			if (collision_info[idx_type].did_hit) {
				cur_distance = collision_info[idx_type].pixel.distance;
				best_collision_info = collision_info[idx_type];
			}
		}

		if (best_collision_info.did_hit) {
			// We hit something
			bounce_color[idx_bounce] = best_collision_info.pixel.color;
			bounce_reflectivity[idx_bounce] = 0.5; // TODO: 50% reflectivity for now. Make this dynamic
			ray = best_collision_info.collision_direction;
		}
		else {
			// We reached the background
			bounce_color[idx_bounce] = bg_color;
			bounce_reflectivity[idx_bounce] = 0;
			break;
		}
	}

	vec4 the_color = bounce_color[idx_bounce];
	for (int i = idx_bounce - 1; i >= 0; i--) {
		the_color = (1 - bounce_reflectivity[i]) * bounce_color[i] + bounce_reflectivity[i] * the_color;
	}

	pixel.color = the_color;

	pixel.color = draw_crosshair(texel_coord, pixel.color);

	imageStore(imgOutput, texel_coord, pixel.color);
}