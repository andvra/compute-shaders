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
layout(location = 3) uniform vec3 the_camera;
layout(location = 4) uniform vec3 the_focus;

layout(std430, binding = 0) buffer layout_spheres
{
	Sphere spheres[];
};
layout(std430, binding = 1) buffer layout_shared_data
{
	Shared_data shared_data;
};

#define PI 3.1415926538

const int num_triangles = 2;
const int num_vertices = 4;
vec3 the_vertices[num_vertices];
ivec3 the_triangles[num_triangles];// Consist of indices of the_vertices
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

	// See https://en.wikipedia.org/wiki/M%C3%B6ller%E2%80%93Trumbore_intersection_algorithm

	for (int idx_triangle = 0; idx_triangle < num_triangles; idx_triangle++) {
		ivec3 current_triangle = the_triangles[idx_triangle];
		const float EPSILON = 0.00001;
		vec3 vertex0 = the_vertices[current_triangle.x];
		vec3 vertex1 = the_vertices[current_triangle.y];
		vec3 vertex2 = the_vertices[current_triangle.z];

		vec3 edge1 = vertex1 - vertex0;
		vec3 edge2 = vertex2 - vertex0;
		vec3 h = cross(ray, edge2);
		float a = dot(edge1, h);

		if (a > -EPSILON && a < EPSILON) {
			continue; // This ray is parallel to this triangle.
		}

		float f = 1.0 / a;
		vec3 s = ray_start_pos - vertex0;
		float u = f * dot(s, h);

		if (u < 0.0 || u > 1.0) {
			continue;
		}

		vec3 q = cross(s, edge1);
		float v = f * dot(ray, q);

		if (v < 0.0 || u + v > 1.0) {
			continue;
		}

		// At this stage we can compute t to find out where the intersection point is on the line.
		float tt = f * dot(edge2, q);

		if (tt > EPSILON) // ray intersection
		{
			vec3 intersection_point = ray_start_pos + ray * tt;
			float distance_from_camera = distance(intersection_point, the_camera);
			ret.pixel.color = vec4(1, 1, 1, 1);
			ret.pixel.distance = distance_from_camera;
			ret.did_hit = true;
			ret.collision_point = intersection_point;
			// https://math.stackexchange.com/questions/13261/how-to-get-a-reflection-vector
			vec3 n = cross(edge1, edge2);
			ret.collision_direction = normalize(ray - 2 * dot(ray, n) * n);
			min_distance = distance_from_camera;

			vec4 pixel_color_side_one = vec4(0.8, 0.2, 0.05, 1);
			vec4 pixel_color_side_two = vec4(0.9, 0.4, 0.7, 1);
			vec4 pixel_color_band = vec4(1, 1, 1, 1);
			float sin_val = sin(10.0f * (intersection_point.z / 10.0f + t));
			ret.pixel.color = pixel_color_side_one;
			float band_width = 1.0f;
			if (sin_val < intersection_point.x) {
				ret.pixel.color = pixel_color_side_two;
			}
			else if (sin_val < intersection_point.x + band_width) {
				float mix_factor = (sin_val - intersection_point.x) / band_width; // 0 <= mix_factor <= 1
				ret.pixel.color = mix_factor * pixel_color_side_one + (1.0f - mix_factor) * pixel_color_side_two;
				float mix_factor2 = 0.15f * (sin(5 * t) + 1.0f) + 0.7f;
				ret.pixel.color = mix_factor2 * ret.pixel.color + (1 - mix_factor2) * pixel_color_band;

			}
		}
	}

	return ret;
}

Collision_info do_spheres(float min_distance, vec3 ray_start_pos, vec3 ray, bool do_color) {
	Collision_info ret;
	ret.did_hit = false;

	for (int i = 0; i < spheres.length(); i++) {
		vec3 sphere_pos = vec3(spheres[i].position[0], spheres[i].position[1], spheres[i].position[2]);
		float sphere_rad = spheres[i].r;
		vec4 sphere_color = vec4(spheres[i].color[0], spheres[i].color[1], spheres[i].color[2], 1);
		if (shared_data.host_idx_selected_sphere == i) {
			sphere_color = vec4(0.7 * sphere_color.xyz + 0.3 * sin(3 * t) * vec3(1, 1, 1), 1);
		}

		vec3 oc = ray_start_pos - sphere_pos;
		float a = dot(ray, ray);
		float b = 2.f * dot(oc, ray);
		float c = dot(oc, oc) - sphere_rad * sphere_rad;
		float discriminant = b * b - 4 * a * c;
		if (discriminant > 0) {
			float t = (-b - sqrt(discriminant)) / (2.0 * a);
			if (t > 0) {
				vec3 collision_point = vec3(ray_start_pos + t * ray);
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
					ret.collision_direction = normalize(collision_point - sphere_pos);
					min_distance = the_distance;
				}
			}
		}
	}

	return ret;
}

void main()
{
	ivec2 texel_coord = ivec2(gl_GlobalInvocationID.xy);

	if (texel_coord.x > w || texel_coord.y > h) {
		return;
	}

	vec3 the_up;
	vec4 bg_color;

	float fov_h = 90.0f;
	float fov_v = fov_h * h / w;
	// Defining -1 <= x <= 1 gives us this distance to (render) screen:
	// tan (fov_H/2) = opp/adj =>
	// adj = opp/tan(fov_H/2) =
	// adj = 1/tan(fov_H/2)
	float dist_to_render_screen = 1.0f / tan(radians(fov_h / 2.0f));

	the_up = vec3(0, 1, 0);

	the_vertices[0] = vec3(-10, 0, -10);
	the_vertices[1] = vec3(-10, 0, 10);
	the_vertices[2] = vec3(10, 0, 10);
	the_vertices[3] = vec3(10, 0, -10);

	the_triangles[0] = ivec3(0, 1, 2);
	the_triangles[1] = ivec3(2, 3, 0);

	vec3 render_screen_x = normalize(cross(the_focus, the_up));
	vec3 render_screen_y = normalize(cross(render_screen_x, the_focus));

	// TODO: Something's a bit fishy with the rays. See this for ray generation: https://viterbi-web.usc.edu/~jbarbic/cs420-s21/15-ray-tracing/15-ray-tracing.pdf
	vec3 render_screen_pixel = the_camera + dist_to_render_screen * the_focus + (2 * render_screen_x * (float(texel_coord.x) / w - 0.5f)) + (2 * render_screen_y * (float(texel_coord.y) / h - 0.5f));
	vec3 ray = normalize(render_screen_pixel - the_camera);

	bool do_color = false;

	if (texel_coord.y == (h - mouse_pos.y) && texel_coord.x == mouse_pos.x){
		do_color = true;
	}

	const float min_distance = 10000;
	bg_color = vec4(0.6, 0.5, 0.5, 1);
	Pixel_info pixel = Pixel_info(bg_color, min_distance);

	const int max_bounces = 3;
	vec4 bounce_color[max_bounces];
	float bounce_reflectivity[max_bounces];	// 0 - 1
	int actual_bounces = 0;
	int idx_bounce;
	vec3 start_pos = the_camera;

	for (idx_bounce = 0; idx_bounce < max_bounces; idx_bounce++) {
		float cur_distance = min_distance;
		Collision_info collision_info[2];
		Collision_info best_collision_info;
		best_collision_info.did_hit = false;

		for (int idx_type = 0; idx_type < 2; idx_type++) {
			switch (idx_type) {
			case 0:
				collision_info[idx_type] = do_triangles(cur_distance, start_pos, ray);
				break;
			case 1:
				collision_info[idx_type] = do_spheres(cur_distance, start_pos, ray, do_color);
				break;
			}

			if (collision_info[idx_type].did_hit 
					&& collision_info[idx_type].pixel.distance < cur_distance) {
				cur_distance = collision_info[idx_type].pixel.distance;
				best_collision_info = collision_info[idx_type];
			}
		}

		if (best_collision_info.did_hit) {
			// We hit something
			bounce_color[idx_bounce] = best_collision_info.pixel.color;
			bounce_reflectivity[idx_bounce] = 0.5; // TODO: 50% reflectivity for now. Make this dynamic
			ray = normalize(best_collision_info.collision_direction);
			start_pos = best_collision_info.collision_point;
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