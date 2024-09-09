#include <iostream>
#include <numbers>
#include <vector>
#include <filesystem>

#include <glad/glad.h>
#include <GLFW/glfw3.h>

#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>

#include "shader_c.h"

void framebuffer_size_callback(GLFWwindow* window, int width, int height);
void renderQuad();

// timing 
float deltaTime = 0.0f; // time between current frame and last frame
float lastFrame = 0.0f; // time of last frame

auto background_center = glm::vec2(500, 500);
enum class Shaders { funky, rays, marching, solver, mold };
enum class Toolbar_control_type { button, slider, knob };

Shaders shader = Shaders::mold;

struct Key_info {
	bool is_pressed;
	bool has_been_read;
};

struct Mouse_move_info {
	int old_x;
	int old_y;
	int new_x;
	int new_y;
	bool has_been_read;
};

struct Mouse_button_info {
	bool is_pressed;
	bool has_been_read;
};

struct Sphere {
	float position[3];
	float r;
	float color[3];
};

struct Circle {
	float pos[2];
	float r;
	float r_square;	// For faster GPU calculations
	float color[3];
};

struct Mold_particle {
	float pos[2];
	float angle;
	int type;
};

struct Block_id {
	int x;
	int y;
};

struct Shared_data {
	int host_idx_selected_sphere;
	int device_idx_selected_sphere;
};

struct Toolbar_info {
	int x;
	int y;
	int w;
	int h;
	int border_height;
};

struct Toolbar_control {
	int id;
	Toolbar_control_type type;
	int x;
	int y;
	int w;
	int h;
	int val_min;
	int val_max;
	int val_cur;
};

Key_info key_info[512] = {}; // GLFW_KEY_ESCAPE is 256 for some reason
Mouse_button_info mouse_button_info[2] = {};
Mouse_move_info mouse_move_info = {};

void mouse_button_callback(GLFWwindow* window, int button, int action, int mods)
{
	enum class Mouse_actions { up, down };

	auto num_allocated_buttons = sizeof(mouse_button_info) / sizeof(Mouse_button_info);

	if (button >= num_allocated_buttons) {
		return;
	}

	switch ((Mouse_actions)action) {
	case Mouse_actions::down:
		mouse_button_info[button].is_pressed = true;
		mouse_button_info[button].has_been_read = false;
		break;
	case Mouse_actions::up:
		mouse_button_info[button].is_pressed = false;
		break;
	}
}

void mouse_move_callback(GLFWwindow* window, double xpos, double ypos) {
	mouse_move_info.new_x = xpos;
	mouse_move_info.new_y = ypos;
	mouse_move_info.has_been_read = false;
}

void key_callback(GLFWwindow* window, int key, int scancode, int action, int mods) {
	enum class Key_actions { up, down, holding };

	auto num_allocated_keys = sizeof(key_info) / sizeof(Key_info);

	if (key >= num_allocated_keys) {
		return;
	}

	switch ((Key_actions)action) {
	case Key_actions::down:
		key_info[key].is_pressed = true;
		key_info[key].has_been_read = false;
		break;
	case Key_actions::up:
		key_info[key].is_pressed = false;
		break;
	}
}

std::vector<unsigned char> read_bmp(std::string filename)
{
	FILE* f = fopen(filename.c_str(), "rb");
	unsigned char info[54];

	// read the 54-byte header
	fread(info, sizeof(unsigned char), 54, f);

	// extract image height and width from header
	int width = *(int*)&info[18];
	int height = *(int*)&info[22];

	// allocate 3 bytes per pixel
	int size = 3 * width * height;
	std::vector<unsigned char> data(size);

	// read the rest of the data at once
	fread(data.data(), sizeof(unsigned char), size, f);
	fclose(f);

	for (size_t i = 0; i < size; i += 3)
	{
		// flip the order of every 3 bytes
		auto tmp = data[i];
		data[i] = data[i + 2];
		data[i + 2] = tmp;
	}

	return data;
}

void log_error(std::string msg) {
	std::cout << msg << std::endl;
}

bool setup_window(int width, int height, std::string title, GLFWwindow*& window) {
	glfwInit();
	glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
	glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
	glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

#ifdef __APPLE__
	glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);
#endif

	window = glfwCreateWindow(width, height, title.c_str(), NULL, NULL);

	if (window == nullptr) {
		std::cout << "Failed to create GLFW window" << std::endl;
		glfwTerminate();
		return false;
	}
	
	glfwMakeContextCurrent(window);
	glfwSetFramebufferSizeCallback(window, framebuffer_size_callback);
	glfwSwapInterval(0);

	return true;
}

bool load_opengl() {
	if (!gladLoadGLLoader((GLADloadproc)glfwGetProcAddress)) {
		log_error("Failed to initialize GLAD");
		return false;
	}

	return true;
}

void print_gl_info() {
	int max_compute_work_group_count[3];
	int max_compute_work_group_size[3];
	int max_compute_work_group_invocations;

	for (int idx = 0; idx < 3; idx++) {
		glGetIntegeri_v(GL_MAX_COMPUTE_WORK_GROUP_COUNT, idx, &max_compute_work_group_count[idx]);
		glGetIntegeri_v(GL_MAX_COMPUTE_WORK_GROUP_SIZE, idx, &max_compute_work_group_size[idx]);
	}
	glGetIntegerv(GL_MAX_COMPUTE_WORK_GROUP_INVOCATIONS, &max_compute_work_group_invocations);

	std::cout << "OpenGL Limitations: " << std::endl;
	std::cout << "maximum number of work groups in X dimension " << max_compute_work_group_count[0] << std::endl;
	std::cout << "maximum number of work groups in Y dimension " << max_compute_work_group_count[1] << std::endl;
	std::cout << "maximum number of work groups in Z dimension " << max_compute_work_group_count[2] << std::endl;

	std::cout << "maximum size of a work group in X dimension " << max_compute_work_group_size[0] << std::endl;
	std::cout << "maximum size of a work group in Y dimension " << max_compute_work_group_size[1] << std::endl;
	std::cout << "maximum size of a work group in Z dimension " << max_compute_work_group_size[2] << std::endl;

	std::cout << "Number of invocations in a single local work group that may be dispatched to a compute shader " << max_compute_work_group_invocations << std::endl;
}

bool file_read(std::filesystem::path& path, std::string& s) {
	std::ifstream t(path);

	if (!t.is_open()) {
		return false;
	}

	std::stringstream ss;
	ss << t.rdbuf();

	s = ss.str();

	return true;
}

bool has_linker_error(GLuint id_shader, std::string& msg) {
	const int max_size_log_message = 1024;
	GLint success;
	GLchar log_message[max_size_log_message];

	glGetProgramiv(id_shader, GL_LINK_STATUS, &success);

	if (!success) {
		glGetProgramInfoLog(id_shader, max_size_log_message, NULL, log_message);
		return true;
	}

	return false;
}

bool has_compiler_error(GLuint id_shader, std::string& msg) {
	const int max_size_log_message = 1024;
	GLint success;
	GLchar log_message[max_size_log_message];

	glGetShaderiv(id_shader, GL_COMPILE_STATUS, &success);

	if (!success) {
		glGetShaderInfoLog(id_shader, max_size_log_message, nullptr, log_message);
		msg = log_message;
		return true;
	}

	return false;
}

bool compile_shader(GLuint& id_shader, const std::string& shader_code, GLenum type) {
	std::string shader_type_string = "Unknown";

	if (type == GL_VERTEX_SHADER) {
		shader_type_string = "vertex";
	}
	else if (type == GL_FRAGMENT_SHADER) {
		shader_type_string = "fragment";
	}

	id_shader = glCreateShader(type);
	auto the_code = shader_code.c_str();

	glShaderSource(id_shader, 1, &the_code, nullptr);
	glCompileShader(id_shader);

	std::string log_message = {};
	auto success = !has_compiler_error(id_shader, log_message);

	if (!success) {
		std::cout << "Could not compile " << shader_type_string << " shader. Message: " << log_message << std::endl;
	}

	return success;
}

bool compile_program(GLuint id_vertex_shader, GLuint id_fragment_shader, GLuint& id_program) {
	id_program = glCreateProgram();

	glAttachShader(id_program, id_vertex_shader);
	glAttachShader(id_program, id_fragment_shader);
	glLinkProgram(id_program);

	std::string log_message = {};
	auto success = !has_linker_error(id_program, log_message);

	if (!success) {
		std::cout << "Could not link program. Message: " << log_message << std::endl;
	}

	return success;
}

bool shader_create(std::filesystem::path& path_vertex, std::filesystem::path& path_fragment, GLuint& id_program) {
	std::string code_vertex_shader = {};
	std::string code_fragment_shader = {};

	if (!file_read(path_vertex, code_vertex_shader)) {
		return false;
	}

	if (!file_read(path_fragment, code_fragment_shader)) {
		return false;
	}

	GLuint id_vertex_shader;
	GLuint id_fragment_shader;

	auto success_vertex_shader = compile_shader(id_vertex_shader, code_vertex_shader, GL_VERTEX_SHADER);
	auto success_fragment_shader = compile_shader(id_fragment_shader, code_fragment_shader, GL_FRAGMENT_SHADER);

	if (!success_vertex_shader || !success_fragment_shader) {
		return false;
	}

	auto success_program = compile_program(id_vertex_shader, id_fragment_shader, id_program);

	glDeleteShader(id_vertex_shader);
	glDeleteShader(id_fragment_shader);

	return success_program;
}

void shader_set_int(GLuint id_program, const std::string& variable_name, int value) {
	glUniform1i(glGetUniformLocation(id_program, variable_name.c_str()), value);
}

void shader_use_program(GLuint id_program) {
	glUseProgram(id_program);
}

int main(int argc, char* argv[]) {
	const unsigned int window_width = 1200;
	const unsigned int window_height = 900;
	const unsigned int texture_width = window_width;
	const unsigned int texture_height = window_height;
	
	GLFWwindow* window = nullptr;

	if (!setup_window(window_width, window_height, "Compute shaders", window)) {
		log_error("Could not create GLFW window");
		return -1;
	}

	if (!load_opengl()) {
		log_error("Could not initialize OpenGL pointers");
		return -1;
	}

	print_gl_info();

	std::filesystem::path vertex_shader_path("screenQuad.vs");
	std::filesystem::path fragment_shader_path("screenQuad.fs");
	auto initial_shader_path = "computeShader.glsl";
	auto solver_path = "solver.glsl";
	auto rays_path = "rays.glsl";
	auto marching_path = "marching.glsl";
	auto mold_path = "mold.glsl";

	GLuint id_program;

	if (!shader_create(vertex_shader_path, fragment_shader_path, id_program)) {
		log_error("Could not create program");
		return -1;
	}

	ComputeShader initial_shader(initial_shader_path);
	ComputeShader solver(solver_path);
	ComputeShader rays(rays_path);
	ComputeShader marching(marching_path);
	ComputeShader mold(mold_path);

	mold.use();
	mold.setInt("w", window_width);
	mold.setInt("h", window_height);
	mold.setInt("action_id", 1);

	shader_use_program(id_program);
	shader_set_int(id_program, "tex", 0);

	GLuint id_texture;

	glGenTextures(1, &id_texture);
	glActiveTexture(GL_TEXTURE0);
	glBindTexture(GL_TEXTURE_2D, id_texture);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, texture_width, texture_height, 0, GL_RGBA, GL_FLOAT, nullptr);

	glBindImageTexture(0, id_texture, 0, GL_FALSE, 0, GL_READ_WRITE, GL_RGBA32F);

	glActiveTexture(GL_TEXTURE0);
	glBindTexture(GL_TEXTURE_2D, id_texture);

	std::vector<int> data(1000);

	for (int i = 0; i < data.size(); i++) {
		data[i] = i;
	}

	GLuint ssbo_solver;
	glGenBuffers(1, &ssbo_solver);
	glBindBuffer(GL_SHADER_STORAGE_BUFFER, ssbo_solver);
	glBufferData(GL_SHADER_STORAGE_BUFFER, sizeof(int) * data.size(), data.data(), GL_DYNAMIC_READ);
	glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, ssbo_solver);

	std::vector<Sphere> spheres = {	// x y z rad r g b
		{10, 2,   1, 1, 1, 0, 0},
		{7,  2.5, 3, 1, 0, 1, 0},
		{4,  2,   5, 1, 0, 0, 1},
		{0,  2,   0, 4, 1, 1, 1},
	};
	GLuint ssbo_spheres;
	glGenBuffers(1, &ssbo_spheres);
	glBindBuffer(GL_SHADER_STORAGE_BUFFER, ssbo_spheres);
	glBufferData(GL_SHADER_STORAGE_BUFFER, sizeof(Sphere) * spheres.size(), (const void*)spheres.data(), GL_DYNAMIC_DRAW);
	glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, ssbo_spheres);

	Shared_data shared_data = { -1, -1 };
	GLuint ssbo_shared_data;
	glGenBuffers(1, &ssbo_shared_data);
	glBindBuffer(GL_SHADER_STORAGE_BUFFER, ssbo_shared_data);
	glBufferData(GL_SHADER_STORAGE_BUFFER, sizeof(Shared_data) * 1, (const void*)&shared_data, GL_DYNAMIC_DRAW);
	glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 2, ssbo_shared_data);

	rays.use();
	rays.setInt("w", window_width);
	rays.setInt("h", window_height);

	std::vector<Circle> circles(200);
	std::vector<Block_id> block_ids(circles.size());
	Toolbar_info toolbar_info;
	toolbar_info = { .x = 100, .y = 300, .w = 300, .h = 500, .border_height = 50 };
	// This is to flip the coordinate system so it works with GLSL
	toolbar_info.y = window_height - toolbar_info.y - toolbar_info.h;
	std::vector<float> toolbar_pixels(3 * toolbar_info.w * toolbar_info.h);
	enum class Toolbar_control_ids { button_toggle_alpha, slider_alpha_level, knob_value};
	std::vector<Toolbar_control> toolbar_controls = {
		{(int)Toolbar_control_ids::button_toggle_alpha, Toolbar_control_type::button, 20, 50, 100, 50, 0, 0, 0},
		{(int)Toolbar_control_ids::slider_alpha_level, Toolbar_control_type::slider, 20, 120, 200, 50, 1, 100, 65},
		{(int)Toolbar_control_ids::knob_value, Toolbar_control_type::knob, 20, 190, 50, 50, 1, 100, 1}
	};
	int block_size = 200;
	GLuint ssbo_circles;
	GLuint ssbo_block_ids;
	GLuint ssbo_toolbar_info;
	GLuint ssbo_toolbar_colors;
	int idx_active_circle = -1;
	int idx_active_control = -1;
	bool moving_toolbar = false;
	int toolbar_click_pos[2] = {};
	bool use_toolbar_alpha = false;
	float toolbar_opacity_min = 0.5f;
	int slider_id = (int)Toolbar_control_ids::slider_alpha_level;
	float toolbar_opacity = toolbar_opacity_min + (1 - toolbar_opacity_min) * ((float)(toolbar_controls[slider_id].val_cur - toolbar_controls[slider_id].val_min) / (toolbar_controls[slider_id].val_max - toolbar_controls[slider_id].val_min));
	int knob_down_start_x = 0;
	int knob_down_start_val = 0;
	std::string font_file = "font_bitmap_16.bmp";

	auto font_texture = read_bmp((char*)font_file.c_str());

	auto hack_to_correct_font_bitmap_colors = [&font_texture]() {
		// The bitmap has blue-ish colors. We want pure black/white, so fix accordingly
		for (int idx_font_color = 0; idx_font_color < font_texture.size(); idx_font_color += 3) {
			unsigned char& c1 = font_texture[idx_font_color + 0];
			unsigned char& c2 = font_texture[idx_font_color + 1];
			unsigned char& c3 = font_texture[idx_font_color + 2];
			int tot_diff = std::abs(c1 - 255) + std::abs(c2 - 255) + std::abs(c3 - 255);
			if (tot_diff < 100) {
				c1 = 255;
				c2 = 255;
				c3 = 255;
			}
			else {
				c1 = 0;
				c2 = 0;
				c3 = 0;
			}
		}
	};

	hack_to_correct_font_bitmap_colors();

	auto draw_chars = [&toolbar_pixels, &toolbar_info, &font_texture](std::string s, int offset_x, int offset_y) {
		int char_width = 16;
		int char_height = 24;
		int num_chars_per_row = 16;
		int num_rows = 8;
		int tot_width = char_width * num_chars_per_row;
		for (auto idx_char : s) {
			int char_row = idx_char / num_chars_per_row;
			int char_col = idx_char - char_row * num_chars_per_row;
			for (int i = 0; i < char_width; i++) {
				auto toolbar_x = i + offset_x;
				if (toolbar_x < 0 || toolbar_x >= toolbar_info.w) {
					continue;
				}
				for (int j = 0; j < char_height; j++) {
					auto toolbar_y = j + offset_y;
					if (toolbar_y < 0 || toolbar_y >= toolbar_info.h) {
						continue;
					}
					auto col_offset = char_col * char_width;
					auto row_offset = (num_rows - 1 - char_row) * char_height;
					auto font_texture_x = col_offset + i;
					auto font_texture_y = j + row_offset;
					for (int c = 0; c < 3; c++) {
						toolbar_pixels[3 * (toolbar_x + toolbar_y * toolbar_info.w) + c] = font_texture[3 * (font_texture_x + font_texture_y * tot_width) + c] / 255.0f;
					}
				}
			}
			offset_x += char_width;
		}
	};

	auto draw_toolbar = [&toolbar_pixels, &toolbar_info, &draw_chars](int x_start, int x_end, int y_start, int y_end) {
		for (int col = x_start; col < x_end; col++) {
			for (int row = y_start; row < y_end; row++) {
				int row_fixed = toolbar_info.h - row - 1;
				float color[3];
				int idx_pixel = 3 * (col + row * toolbar_info.w);
				if (row_fixed >= toolbar_info.border_height) {
					color[0] = 0.4f;
					color[1] = std::sin(idx_pixel) * std::sin(idx_pixel);
					color[2] = (idx_pixel % 1000) / 1000.0f;
				}
				else {
					color[0] = 0.0f;
					color[1] = 0.0f;
					color[2] = 0.0f;
				}
				for (int i = 0; i < 3; i++) {
					toolbar_pixels[idx_pixel + i] = color[i];
				}
			}
		}
		draw_chars("Main toolbar", 20, toolbar_info.h - 40);
	};

	auto draw_control = [&toolbar_pixels, &toolbar_info, &ssbo_toolbar_colors, &draw_chars, &draw_toolbar](Toolbar_control& toolbar_control, bool do_push_to_device) {
		auto& c = toolbar_control;

		switch (c.type) {
		case Toolbar_control_type::button:
			for (int col = c.x; col < +c.x + c.w; col++) {
				for (int row = c.y; row < c.y + c.h; row++) {
					int row_fixed = toolbar_info.h - row - 1;
					toolbar_pixels[3 * (col + row_fixed * toolbar_info.w) + 0] = 1.0;
					toolbar_pixels[3 * (col + row_fixed * toolbar_info.w) + 1] = 1.0;
					toolbar_pixels[3 * (col + row_fixed * toolbar_info.w) + 2] = 1.0;
				}
			}
			break;
		case Toolbar_control_type::knob:
			{
				float r = c.w / 2.0f;
				float max_dist = r * r; // Width and height must be equal
				auto center_x = c.x + c.w / 2;
				auto center_y = c.y + c.h / 2;
				float colors[3] = { 1.0,1.0,1.0 };
				int fixed_y = toolbar_info.h - c.y - 1;
				int margin_for_chars_px = 100;
				draw_toolbar(c.x, c.x + c.w + margin_for_chars_px, fixed_y - c.h, fixed_y);
				for (int col = c.x; col < c.x + c.w; col++) {
					for (int row = c.y; row < c.y + c.h; row++) {
						auto cur_dist = (center_x - col) * (center_x - col) + (center_y - row) * (center_y - row);

						if(cur_dist > max_dist) {
							continue;
						}

						int row_fixed = toolbar_info.h - row - 1;
						toolbar_pixels[3 * (col + row_fixed * toolbar_info.w) + 0] = colors[0];
						toolbar_pixels[3 * (col + row_fixed * toolbar_info.w) + 1] = colors[1];
						toolbar_pixels[3 * (col + row_fixed * toolbar_info.w) + 2] = colors[2];
					}
				}
				float factor = (c.val_cur - c.val_min) / (float)(c.val_max - c.val_min);
				float diff_from_full_circle_rad = 0.5f;
				float angle_rad = diff_from_full_circle_rad + factor * (2.0f * 3.1415f - 2.0f * diff_from_full_circle_rad);
				float dot_r = 5;
				int dot_center_x = center_x + (r - dot_r) * std::sin(-angle_rad);
				int dot_start_x = dot_center_x - dot_r;
				int dot_end_x = dot_start_x + dot_r;
				int dot_center_y = center_y + (r - dot_r) * std::cos(angle_rad);
				int dot_start_y = dot_center_y - dot_r;
				int dot_end_y = dot_start_y + dot_r;
				for (int col = dot_start_x; col <= dot_end_x; col++) {
					for (int row = dot_start_y; row <= dot_end_y; row++) {
						int row_fixed = toolbar_info.h - row - 1;
						toolbar_pixels[3 * (col + row_fixed * toolbar_info.w) + 0] = 0.4f;
						toolbar_pixels[3 * (col + row_fixed * toolbar_info.w) + 1] = 0.5f;
						toolbar_pixels[3 * (col + row_fixed * toolbar_info.w) + 2] = 0.9f;
					}
				}
				draw_chars(std::to_string(c.val_cur), c.x + c.w + 10, toolbar_info.h - c.y - 1 - c.h / 2 - 12);
			}
			break;
		case Toolbar_control_type::slider:
			int anchor_width = 5;
			int anchor_min_x = -1;
			int anchor_max_x = -1;
			if (c.val_max - c.val_min > 0) {
				float factor = (c.val_cur - c.val_min) / (float)(c.val_max - c.val_min);
				int available_pixels = c.w - anchor_width;

				anchor_min_x = c.x + factor * available_pixels;
				anchor_max_x = anchor_min_x + anchor_width;
			}
			for (int col = c.x; col < c.x + c.w; col++) {
				for (int row = c.y; row < c.y + c.h; row++) {
					int row_fixed = toolbar_info.h - row - 1;
					float colors[3] = { 1.0,1.0,1.0 };
					if (col >= anchor_min_x && col < anchor_max_x) {
						colors[0] = 0.5;
					}
					toolbar_pixels[3 * (col + row_fixed * toolbar_info.w) + 0] = colors[0];
					toolbar_pixels[3 * (col + row_fixed * toolbar_info.w) + 1] = colors[1];
					toolbar_pixels[3 * (col + row_fixed * toolbar_info.w) + 2] = colors[2];
				}
			}
		}

		if (do_push_to_device) {
			glBindBuffer(GL_SHADER_STORAGE_BUFFER, ssbo_toolbar_colors);
			glBufferSubData(GL_SHADER_STORAGE_BUFFER, 0, sizeof(float) * toolbar_pixels.size(), toolbar_pixels.data());
		}
	};

	{
		for (int i = 0; i < circles.size(); i++) {
			Circle c = { 100 + std::rand() % (window_width - 200), 100 + std::rand() % (window_height - 200), 5, 0, std::rand() % 100 / 100.0f, std::rand() % 100 / 100.0f, std::rand() % 100 / 100.0f };
			c.r_square = c.r * c.r;
			circles[i] = c;
		}

		glGenBuffers(1, &ssbo_circles);
		glBindBuffer(GL_SHADER_STORAGE_BUFFER, ssbo_circles);
		glBufferData(GL_SHADER_STORAGE_BUFFER, sizeof(Circle) * circles.size(), (const void*)circles.data(), GL_DYNAMIC_DRAW);
		glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 3, ssbo_circles);

		for (int i = 0; i < block_ids.size(); i++) {
			block_ids[i] = { (int)circles[i].pos[0] / block_size, (int)circles[i].pos[1] / block_size };
		}

		glGenBuffers(1, &ssbo_block_ids);
		glBindBuffer(GL_SHADER_STORAGE_BUFFER, ssbo_block_ids);
		glBufferData(GL_SHADER_STORAGE_BUFFER, sizeof(Block_id) * block_ids.size(), (const void*)block_ids.data(), GL_DYNAMIC_DRAW);
		glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 4, ssbo_block_ids);

		glGenBuffers(1, &ssbo_toolbar_info);
		glBindBuffer(GL_SHADER_STORAGE_BUFFER, ssbo_toolbar_info);
		glBufferData(GL_SHADER_STORAGE_BUFFER, sizeof(Toolbar_info) * 1, (const void*)&toolbar_info, GL_DYNAMIC_DRAW);
		glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 5, ssbo_toolbar_info);

		draw_toolbar(0, toolbar_info.w, 0, toolbar_info.h);

		draw_chars("one two three 1 2 3", 55, 50);

		for (auto& c : toolbar_controls) {
			draw_control(c, false);
		}

		glGenBuffers(1, &ssbo_toolbar_colors);
		glBindBuffer(GL_SHADER_STORAGE_BUFFER, ssbo_toolbar_colors);
		glBufferData(GL_SHADER_STORAGE_BUFFER, sizeof(float) * toolbar_pixels.size(), (const void*)toolbar_pixels.data(), GL_DYNAMIC_DRAW);
		glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 6, ssbo_toolbar_colors);

		marching.use();
		marching.setInt("block_size", block_size);
		marching.setInt("w", window_width);
		marching.setInt("h", window_height);
		marching.setFloat("toolbar_opacity", toolbar_opacity);
	}

	size_t num_mold_particles = 25'000;

	std::vector<Mold_particle> mold_particles(num_mold_particles);
	int type_id = 0;
	int num_types = 1;
	for (auto& x : mold_particles) {
		float pos_x = window_width * (std::rand() % 10000) / 10000.0f;
		float pos_y = window_height * (std::rand() % 10000) / 10000.0f;
		float angle = 2.0f * (float)std::numbers::pi * (std::rand() % 10000) / 10000.0f;
		x = { .pos = {pos_x,pos_y}, .angle = angle, .type = type_id };
		type_id = (type_id + 1) % num_types;
	}
	GLuint ssbo_mold;
	glGenBuffers(1, &ssbo_mold);
	glBindBuffer(GL_SHADER_STORAGE_BUFFER, ssbo_mold);
	glBufferData(GL_SHADER_STORAGE_BUFFER, sizeof(Mold_particle) * mold_particles.size(), (const void*)mold_particles.data(), GL_DYNAMIC_DRAW);
	glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 7, ssbo_mold);

	std::vector<float> mold_intensities(window_width * window_height* num_types);
	GLuint ssbo_mold_intensities;
	glGenBuffers(1, &ssbo_mold_intensities);
	glBindBuffer(GL_SHADER_STORAGE_BUFFER, ssbo_mold_intensities);
	glBufferData(GL_SHADER_STORAGE_BUFFER, sizeof(float) * mold_intensities.size(), (const void*)mold_intensities.data(), GL_DYNAMIC_DRAW);
	glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 8, ssbo_mold_intensities);

	initial_shader.use();
	initial_shader.setInt("w", window_width);
	initial_shader.setInt("h", window_height);

	mold.use();
	mold.setInt("num_types", num_types);

	glfwSetMouseButtonCallback(window, mouse_button_callback);
	glfwSetKeyCallback(window, key_callback);
	glfwSetCursorPosCallback(window, mouse_move_callback);

	// Work groups should be a multiple of 32, so make sure to adjust the local work group sizes accordingly
	// See https://computergraphics.stackexchange.com/questions/13449/opengl-compute-local-size-vs-performance

	unsigned int workgroup_size_x = (unsigned int)ceil(texture_width / 32.0);
	unsigned int workgroup_size_y = (unsigned int)ceil(texture_height / 32.0);

	float last_fps_time = glfwGetTime();
	int frame_counter = 0;

	auto key_was_just_pressed = [](int key_code) -> bool {
		auto num_allocated_keys = sizeof(key_info) / sizeof(Key_info);
		if (key_code >= num_allocated_keys) {
			return false;
		}
		auto ret = key_info[key_code].is_pressed && !key_info[key_code].has_been_read;
		key_info[key_code].has_been_read = true;
		return ret;
	};

	auto key_is_pressed = [](int key_code) -> bool {
		auto num_allocated_keys = sizeof(key_info) / sizeof(Key_info);
		if (key_code >= num_allocated_keys) {
			return false;
		}
		key_info[key_code].has_been_read = true;
		return key_info[key_code].is_pressed;
	};

	glm::vec3 the_camera = glm::vec3(0, 15, 15);
	glm::vec3 the_focus = glm::vec3(10, 0, 10);
	float angle_alpha = std::numbers::pi;
	float angle_beta = -std::numbers::pi / 8;

	glfwSetCursorPos(window, window_width / 2, window_height / 2);
	mouse_move_info.has_been_read = true;
	mouse_move_info.new_x = window_width / 2;
	mouse_move_info.new_y = window_height / 2;
	mouse_move_info.old_x = window_width / 2;
	mouse_move_info.old_y = window_height / 2;
	
	int idx_dest = -1;
	int idx_src = -1;
	float t_move_start = 0;
	float t_move_end = 0;
	float move_origin[2] = { 0,0 };
	float move_vector[2] = { 0,0 };

	while (!glfwWindowShouldClose(window))
	{
		float currentFrame = glfwGetTime();
		deltaTime = currentFrame - lastFrame;
		lastFrame = currentFrame;

		float fps_print_diff_time = currentFrame - last_fps_time;
		if (fps_print_diff_time > 1.0f) {
			std::cout << "FPS: " << frame_counter / fps_print_diff_time << " (" << 1000 * fps_print_diff_time / frame_counter << " ms per frame)" << std::endl;
			frame_counter = 0;
			last_fps_time = currentFrame;
		}

		if (key_was_just_pressed(GLFW_KEY_ESCAPE)) {
			glfwSetWindowShouldClose(window, 1);
		}
		if (key_was_just_pressed(GLFW_KEY_1)) {
			shader = Shaders::funky;
		}
		if (key_was_just_pressed(GLFW_KEY_2)) {
			shader = Shaders::rays;
		}
		if (key_was_just_pressed(GLFW_KEY_3)) {
			shader = Shaders::marching;
		}
		if (key_was_just_pressed(GLFW_KEY_4)) {
			shader = Shaders::mold;
		}
		if (key_is_pressed(GLFW_KEY_W)) {
			the_camera += the_focus * deltaTime * 5.0f;
		}
		if (key_is_pressed(GLFW_KEY_S)) {
			the_camera -= the_focus * deltaTime * 5.0f;
		}
		if (key_is_pressed(GLFW_KEY_A)) {
			the_camera -= glm::normalize(glm::cross(the_focus, glm::vec3(0, 1, 0))) * deltaTime * 5.0f;
		}
		if (key_is_pressed(GLFW_KEY_D)) {
			the_camera += glm::normalize(glm::cross(the_focus, glm::vec3(0, 1, 0))) * deltaTime * 5.0f;
		}
		if (key_is_pressed(GLFW_KEY_Q)) {
			the_camera += glm::vec3(0, 1, 0) * deltaTime * 5.0f;
		}
		if (key_is_pressed(GLFW_KEY_Z)) {
			the_camera -= glm::vec3(0, 1, 0) * deltaTime * 5.0f;
		}
		if (shader == Shaders::rays && !mouse_move_info.has_been_read) {
			float move_factor = 1.0f;
			angle_alpha += (mouse_move_info.old_x - mouse_move_info.new_x) * deltaTime * move_factor;
			if (angle_alpha < 0) {
				angle_alpha += 2 * std::numbers::pi;
			}
			if (angle_alpha > 2 * std::numbers::pi) {
				angle_alpha -= 2 * std::numbers::pi;
			}
			angle_beta += (mouse_move_info.old_y - mouse_move_info.new_y) * deltaTime * move_factor;
			if (angle_beta <= -std::numbers::pi / 2) {
				angle_beta = -std::numbers::pi / 2 + 0.00001f;
			}
			if (angle_beta >= std::numbers::pi / 2) {
				angle_beta = std::numbers::pi / 2 - 0.00001f;
			}
			mouse_move_info.has_been_read = true;
			glfwSetCursorPos(window, window_width / 2, window_height / 2);
		}
		if (shader == Shaders::funky) {
			if (!mouse_button_info[0].has_been_read && mouse_button_info[0].is_pressed) {
				double xpos, ypos;
				glfwGetCursorPos(window, &xpos, &ypos);
				background_center.x = xpos;
				background_center.y = window_height - ypos;
				mouse_button_info[0].has_been_read = true;
			}
		}
		if (shader == Shaders::marching && !mouse_button_info[0].has_been_read && mouse_button_info[0].is_pressed) {
			double xpos, ypos;
			glfwGetCursorPos(window, &xpos, &ypos);
			auto y_fixed = window_height - ypos;
			bool within_toolbar_x = (xpos >= toolbar_info.x && xpos < toolbar_info.x + toolbar_info.w);
			bool within_toolbar_y = (y_fixed >= toolbar_info.y && y_fixed < toolbar_info.y + toolbar_info.h);

			if (within_toolbar_x && within_toolbar_y) {
				int pos_rel_x = xpos - toolbar_info.x;
				int pos_rel_y = toolbar_info.y + toolbar_info.h - y_fixed;
				if (pos_rel_y < toolbar_info.border_height) {
					moving_toolbar = true;
					toolbar_click_pos[0] = xpos - toolbar_info.x;
					toolbar_click_pos[1] = y_fixed - toolbar_info.y;
				}
				for (auto& c : toolbar_controls) {
					bool hit_x = (pos_rel_x >= c.x && pos_rel_x < c.x + c.w);
					bool hit_y = (pos_rel_y > c.y && pos_rel_y < c.y + c.h);
					if (hit_x && hit_y) {
						switch (c.type) {
						case Toolbar_control_type::button:
							// TODO: Act on this button
							use_toolbar_alpha = !use_toolbar_alpha;
							marching.use();
							marching.setBool("use_toolbar_alpha", use_toolbar_alpha);
							break;
						case Toolbar_control_type::slider:
							{
								int anchor_width = 10;
								int anchor_min_x = -1;
								int anchor_max_x = -1;
								if (c.val_max - c.val_min > 0) {
									float factor = (c.val_cur - c.val_min) / (float)(c.val_max - c.val_min);
									int available_pixels = c.w - anchor_width;

									anchor_min_x = c.x + factor * available_pixels;
									anchor_max_x = anchor_min_x + anchor_width;
								}
								if (pos_rel_x >= anchor_min_x && pos_rel_x < anchor_max_x) {
									idx_active_control = c.id;
									// TODO: We are pulling the slider
								}
							}
							break;
						case Toolbar_control_type::knob:
							idx_active_control = c.id;
							knob_down_start_x = xpos;
							knob_down_start_val = c.val_cur;
							// TODO: Make sure it is within the circle
							break;
						}
					}
				}
			}
			else {
				for (int i = 0; i < circles.size(); i++) {
					auto d_square = (xpos - circles[i].pos[0]) * (xpos - circles[i].pos[0]) + (y_fixed - circles[i].pos[1]) * (y_fixed - circles[i].pos[1]);
					auto r_square = circles[i].r * circles[i].r;
					if (d_square < r_square) {
						idx_active_circle = i;
					}
				}
			}
			mouse_button_info[0].has_been_read = true;
		}
		if (shader == Shaders::marching && mouse_button_info[0].is_pressed && idx_active_circle > -1) {
			double xpos, ypos;
			glfwGetCursorPos(window, &xpos, &ypos);
			auto y_fixed = window_height - ypos;
			circles[idx_active_circle].pos[0] = xpos;
			circles[idx_active_circle].pos[1] = y_fixed;
			block_ids[idx_active_circle] = {(int)xpos / block_size,(int)y_fixed / block_size };
			glBindBuffer(GL_SHADER_STORAGE_BUFFER, ssbo_circles);
			glBufferSubData(GL_SHADER_STORAGE_BUFFER, sizeof(Circle) * idx_active_circle, sizeof(Circle), &circles[idx_active_circle]);
			glBindBuffer(GL_SHADER_STORAGE_BUFFER, ssbo_block_ids);
			glBufferSubData(GL_SHADER_STORAGE_BUFFER, sizeof(Block_id) * idx_active_circle, sizeof(Block_id), &block_ids[idx_active_circle]);
		}
		if (shader == Shaders::marching && mouse_button_info[0].is_pressed && moving_toolbar) {
			double xpos, ypos;
			glfwGetCursorPos(window, &xpos, &ypos);
			auto y_fixed = window_height - ypos;
			toolbar_info.x = xpos - toolbar_click_pos[0];
			toolbar_info.y = y_fixed - toolbar_click_pos[1];
			glBindBuffer(GL_SHADER_STORAGE_BUFFER, ssbo_toolbar_info);
			glBufferSubData(GL_SHADER_STORAGE_BUFFER, 0, sizeof(Toolbar_info), &toolbar_info);
		}
		if (shader == Shaders::marching && mouse_button_info[0].is_pressed && idx_active_control > -1) {
			double xpos, ypos;
			glfwGetCursorPos(window, &xpos, &ypos);
			auto& c = toolbar_controls[idx_active_control];
			switch(c.type) {
			case Toolbar_control_type::slider:
				{
					int xrel = xpos - toolbar_info.x - c.x;
					float pos_factor = xrel / (float)c.w;
					int new_val = c.val_min + pos_factor * (c.val_max - c.val_min);
					new_val = std::clamp(new_val, c.val_min, c.val_max);
					c.val_cur = new_val;
					toolbar_opacity = toolbar_opacity_min + (1 - toolbar_opacity_min) * ((float)(c.val_cur - c.val_min) / (c.val_max - c.val_min));
					marching.use();
					marching.setFloat("toolbar_opacity", toolbar_opacity);
				}
				break;
			case Toolbar_control_type::knob:
				auto move_range = 200.0f;
				auto pos_factor = (xpos - knob_down_start_x) / move_range;
				int new_val = knob_down_start_val + pos_factor * (c.val_max - c.val_min);
				new_val = std::clamp(new_val, c.val_min, c.val_max);
				c.val_cur = new_val;
				break;
			}
			draw_control(c, true);
		}
		if (shader == Shaders::marching && !mouse_button_info[0].is_pressed) {
			idx_active_circle = -1;
			moving_toolbar = false;
			idx_active_control = -1;
		}
		if (shader == Shaders::marching) {
			if (circles.size() >= 2) {
				if (idx_src == -1) {
					idx_src = std::rand() % circles.size();
					// Setting t_move_end to zero will trigger a new destination
					t_move_end = 0;
				}
				if (currentFrame > t_move_end) {
					if (idx_dest != -1) {
						// Don't move source circle when initializing the app
						circles[idx_src].pos[0] = circles[idx_dest].pos[0];
						circles[idx_src].pos[1] = circles[idx_dest].pos[1];
						glBindBuffer(GL_SHADER_STORAGE_BUFFER, ssbo_circles);
						glBufferSubData(GL_SHADER_STORAGE_BUFFER, sizeof(Circle) * idx_src, sizeof(Circle), &circles[idx_src]);
						glBindBuffer(GL_SHADER_STORAGE_BUFFER, ssbo_block_ids);
						glBufferSubData(GL_SHADER_STORAGE_BUFFER, sizeof(Block_id) * idx_src, sizeof(Block_id), &block_ids[idx_dest]);
						idx_src = idx_dest;
					}
					while ((idx_dest = std::rand() % circles.size()) == idx_src);
					auto x1 = circles[idx_dest].pos[0];
					auto y1 = circles[idx_dest].pos[1];
					auto x2 = circles[idx_src].pos[0];
					auto y2 = circles[idx_src].pos[1];
					float d = std::sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));
					t_move_end = currentFrame + d * 0.005f;
					t_move_start = currentFrame;
					auto diff_x = circles[idx_dest].pos[0] - circles[idx_src].pos[0];
					auto diff_y = circles[idx_dest].pos[1] - circles[idx_src].pos[1];
					move_origin[0] = circles[idx_src].pos[0];
					move_origin[1] = circles[idx_src].pos[1];
					move_vector[0] = diff_x;
					move_vector[1] = diff_y;
				}
				auto t = (currentFrame - t_move_start) / (t_move_end - t_move_start);
				circles[idx_src].pos[0] = move_origin[0] + t * move_vector[0];
				circles[idx_src].pos[1] = move_origin[1] + t * move_vector[1];
				block_ids[idx_src] = { (int)circles[idx_src].pos[0] / block_size, (int)circles[idx_src].pos[1] / block_size };
				glBindBuffer(GL_SHADER_STORAGE_BUFFER, ssbo_circles);
				glBufferSubData(GL_SHADER_STORAGE_BUFFER, sizeof(Circle) * idx_src, sizeof(Circle), &circles[idx_src]);
				glBindBuffer(GL_SHADER_STORAGE_BUFFER, ssbo_block_ids);
				glBufferSubData(GL_SHADER_STORAGE_BUFFER, sizeof(Block_id) * idx_src, sizeof(Block_id), &block_ids[idx_src]);
			}
		}

		double xpos, ypos;
		glfwGetCursorPos(window, &xpos, &ypos);

		switch (shader) {
		case Shaders::mold:
			{
			mold.use();
			mold.setFloat("t_tot", currentFrame);
			mold.setFloat("t_delta", deltaTime);
			int tot_num_actions = 4; // Must sync with the number of actions in mold::main()
			for (int action_id = 0; action_id < tot_num_actions; action_id++) {
				mold.setInt("action_id", action_id);
				glDispatchCompute(workgroup_size_x, workgroup_size_y, 1);
				//glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT);
				glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT | GL_SHADER_STORAGE_BARRIER_BIT);
			}
			}
			break;
		case Shaders::funky:
			initial_shader.use();
			initial_shader.setFloat("t", currentFrame);
			initial_shader.setVec2("mouse_pos", glm::vec2(xpos, ypos));
			initial_shader.setVec2("background_center", background_center);
			glDispatchCompute(workgroup_size_x, workgroup_size_y, 1);
			glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT);
			break;
		case Shaders::rays:
			{
				rays.use();
				rays.setFloat("t", currentFrame);
				rays.setVec2("mouse_pos", glm::vec2(xpos, ypos));
				the_focus.x = std::sin(angle_alpha) * std::cos(angle_beta);
				the_focus.y = std::sin(angle_beta);
				the_focus.z = std::cos(angle_alpha) * std::cos(angle_beta);
				the_focus /= glm::length(the_focus);
				rays.setVec3("the_focus", the_focus);
				rays.setVec3("the_camera", the_camera);
				glDispatchCompute(workgroup_size_x, workgroup_size_y, 1);
				glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT | GL_SHADER_STORAGE_BARRIER_BIT);
				Shared_data ss{};
				glBindBuffer(GL_SHADER_STORAGE_BUFFER, ssbo_shared_data);
				glGetBufferSubData(GL_SHADER_STORAGE_BUFFER, 0, sizeof(Shared_data), &ss);
				ss.host_idx_selected_sphere = ss.device_idx_selected_sphere;
				ss.device_idx_selected_sphere = -1;
				glBufferSubData(GL_SHADER_STORAGE_BUFFER, 0, sizeof(Shared_data), &ss);
			}
			break;
		case Shaders::marching:
			marching.use();
			glDispatchCompute(workgroup_size_x, workgroup_size_y, 1);
			glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT);
			break;
		case Shaders::solver:
			solver.use();
			glDispatchCompute(workgroup_size_x, workgroup_size_y, 1);
			glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT);
			int result_int;
			glBindBuffer(GL_SHADER_STORAGE_BUFFER, ssbo_solver);
			// Here, we take the 10th int to verify results
			glGetBufferSubData(GL_SHADER_STORAGE_BUFFER, sizeof(int) * 10, sizeof(int), &result_int);
			break;
		}

		// render image to quad
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

		shader_use_program(id_program);

		renderQuad();
		glfwSwapBuffers(window);
		glfwPollEvents();

		frame_counter++;
	}

	glBindBuffer(GL_SHADER_STORAGE_BUFFER, 0); // unbind
	glDeleteTextures(1, &id_texture);
	glDeleteProgram(id_program);
	glDeleteProgram(initial_shader.ID);
	glDeleteProgram(rays.ID);

	glfwTerminate();

	return EXIT_SUCCESS;
}

unsigned int quadVAO = 0;
unsigned int quadVBO;
void renderQuad()
{
	if (quadVAO == 0)
	{
		float quadVertices[] = {
			// positions        // texture Coords
			-1.0f,  1.0f, 0.0f, 0.0f, 1.0f,
			-1.0f, -1.0f, 0.0f, 0.0f, 0.0f,
			 1.0f,  1.0f, 0.0f, 1.0f, 1.0f,
			 1.0f, -1.0f, 0.0f, 1.0f, 0.0f,
		};
		// setup plane VAO
		glGenVertexArrays(1, &quadVAO);
		glGenBuffers(1, &quadVBO);
		glBindVertexArray(quadVAO);
		glBindBuffer(GL_ARRAY_BUFFER, quadVBO);
		glBufferData(GL_ARRAY_BUFFER, sizeof(quadVertices), &quadVertices, GL_STATIC_DRAW);
		glEnableVertexAttribArray(0);
		glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 5 * sizeof(float), (void*)0);
		glEnableVertexAttribArray(1);
		glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 5 * sizeof(float), (void*)(3 * sizeof(float)));
	}
	glBindVertexArray(quadVAO);
	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
	glBindVertexArray(0);
}

void framebuffer_size_callback(GLFWwindow* window, int width, int height)
{
	// make sure the viewport matches the new window dimensions; note that width and 
	// height will be significantly larger than specified on retina displays.
	glViewport(0, 0, width, height);
}