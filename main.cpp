#include <iostream>
#include <numbers>
#include <vector>
#include <filesystem>

#include <glad/glad.h>
#include <GLFW/glfw3.h>

#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>

#include "shader_m.h"
#include "shader_c.h"

void framebuffer_size_callback(GLFWwindow* window, int width, int height);
void renderQuad();

// settings
const unsigned int SCR_WIDTH = 1200;
const unsigned int SCR_HEIGHT = 900;

// texture size
const unsigned int TEXTURE_WIDTH = SCR_WIDTH, TEXTURE_HEIGHT = SCR_HEIGHT;

// timing 
float deltaTime = 0.0f; // time between current frame and last frame
float lastFrame = 0.0f; // time of last frame

auto background_center = glm::vec2(500, 500);
enum class Shaders { funky, rays, marching };
Shaders shader = Shaders::funky;

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

struct Sphere {
	float position[3];
	float r;
	float color[3];
};

struct Circle {
	float pos[2];
	float r;
	float color[3];
};

struct Block_id {
	int x;
	int y;
};

struct Shared_data {
	int host_idx_selected_sphere;
	int device_idx_selected_sphere;
};

int main(int argc, char* argv[])
{
	glfwInit();
	glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
	glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
	glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

#ifdef __APPLE__
	glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);
#endif

	GLFWwindow* window = glfwCreateWindow(SCR_WIDTH, SCR_HEIGHT, "Compute shaders", NULL, NULL);
	if (window == NULL)
	{
		std::cout << "Failed to create GLFW window" << std::endl;
		glfwTerminate();
		return -1;
	}

	glfwMakeContextCurrent(window);
	glfwSetFramebufferSizeCallback(window, framebuffer_size_callback);
	glfwSwapInterval(0);

	if (!gladLoadGLLoader((GLADloadproc)glfwGetProcAddress))
	{
		std::cout << "Failed to initialize GLAD" << std::endl;
		return -1;
	}

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

	std::filesystem::path root_folder(R"(D:\work\compute_shaders)");
	if (!std::filesystem::exists(root_folder)) {
		std::cerr << "Could not find folder " << root_folder.string() << std::endl;
		return 1;
	}

	auto vertex_shader_path = (root_folder / "screenQuad.vs").string();
	auto fragment_shader_path = (root_folder / "screenQuad.fs").string();
	auto initial_shader_path = (root_folder / "computeShader.glsl").string();
	auto solver_path = (root_folder / "solver.glsl").string();
	auto rays_path = (root_folder / "rays.glsl").string();
	auto marching_path = (root_folder / "marching.glsl").string();
	Shader screenQuad(vertex_shader_path.c_str(), fragment_shader_path.c_str());
	ComputeShader initial_shader(initial_shader_path.c_str());
	ComputeShader solver(solver_path.c_str());
	ComputeShader rays(rays_path.c_str());
	ComputeShader marching(marching_path.c_str());

	screenQuad.use();
	screenQuad.setInt("tex", 0);

	unsigned int texture;

	glGenTextures(1, &texture);
	glActiveTexture(GL_TEXTURE0);
	glBindTexture(GL_TEXTURE_2D, texture);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, TEXTURE_WIDTH, TEXTURE_HEIGHT, 0, GL_RGBA, GL_FLOAT, NULL);

	glBindImageTexture(0, texture, 0, GL_FALSE, 0, GL_READ_WRITE, GL_RGBA32F);

	glActiveTexture(GL_TEXTURE0);
	glBindTexture(GL_TEXTURE_2D, texture);

	int data[1000];

	for (int i = 0; i < 1000; i++) {
		data[i] = i;
	}

	GLuint ssbo_solver;
	glGenBuffers(1, &ssbo_solver);
	glBindBuffer(GL_SHADER_STORAGE_BUFFER, ssbo_solver);
	glBufferData(GL_SHADER_STORAGE_BUFFER, sizeof(data), &data[0], GL_DYNAMIC_READ);
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

	std::vector<Circle> circles = {
		{100,	100,	30,	0.8f,	0.1f,	0.2f},
		{300,	500,	20,	0.2f,	0.8f,	0.2f},
		{500,	530,	70,	0.2f,	0.8f,	0.9f},
		{50,	500,	70,	0.2f,	0.4f,	0.2f},
		{800,	340,	90,	0.7f,	0.3f,	0.3f}
	};
	circles.clear();
	for (int i = 0; i < 200; i++) {
		Circle c = { 100 + std::rand() % (SCR_WIDTH-200), 100 + std::rand() % (SCR_HEIGHT-200), 5, std::rand() % 100 / 100.0f, std::rand() % 100 / 100.0f, std::rand() % 100 / 100.0f };
		circles.push_back(c);
	}
	GLuint ssbo_circles;
	glGenBuffers(1, &ssbo_circles);
	glBindBuffer(GL_SHADER_STORAGE_BUFFER, ssbo_circles);
	glBufferData(GL_SHADER_STORAGE_BUFFER, sizeof(Circle) * circles.size(), (const void*)circles.data(), GL_DYNAMIC_DRAW);
	glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 3, ssbo_circles);
	int block_size = 100;
	std::vector<Block_id> block_ids(circles.size());
	for (int i = 0; i < block_ids.size(); i++) {
		block_ids[i] = { (int)circles[i].pos[0] / block_size, (int)circles[i].pos[1] / block_size };
	}
	GLuint ssbo_block_ids;
	glGenBuffers(1, &ssbo_block_ids);
	glBindBuffer(GL_SHADER_STORAGE_BUFFER, ssbo_block_ids);
	glBufferData(GL_SHADER_STORAGE_BUFFER, sizeof(Block_id) * block_ids.size(), (const void*)block_ids.data(), GL_DYNAMIC_DRAW);
	glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 4, ssbo_block_ids);
	marching.use();
	marching.setInt("block_size", block_size);

	int idx_active_circle = -1;

	glfwSetMouseButtonCallback(window, mouse_button_callback);
	glfwSetKeyCallback(window, key_callback);
	glfwSetCursorPosCallback(window, mouse_move_callback);

	// Work groups should be a multiple of 32, so make sure to adjust the local work group sizes accordingly
	// See https://computergraphics.stackexchange.com/questions/13449/opengl-compute-local-size-vs-performance

	unsigned int workgroup_size_x = (unsigned int)ceil(TEXTURE_WIDTH / 32.0);
	unsigned int workgroup_size_y = (unsigned int)ceil(TEXTURE_HEIGHT / 32.0);

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

	glfwSetCursorPos(window, SCR_WIDTH / 2, SCR_HEIGHT / 2);
	mouse_move_info.has_been_read = true;
	mouse_move_info.new_x = SCR_WIDTH / 2;
	mouse_move_info.new_y = SCR_HEIGHT / 2;
	mouse_move_info.old_x = SCR_WIDTH / 2;
	mouse_move_info.old_y = SCR_HEIGHT / 2;
	 
	while (!glfwWindowShouldClose(window))
	{
		float currentFrame = glfwGetTime();
		deltaTime = currentFrame - lastFrame;
		lastFrame = currentFrame;

		float fps_print_diff_time = currentFrame - last_fps_time;
		if (fps_print_diff_time > 1.0f) {
			std::cout << "FPS: " << frame_counter / fps_print_diff_time << std::endl;
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
			glfwSetCursorPos(window, SCR_WIDTH / 2, SCR_HEIGHT / 2);
		}
		if (shader == Shaders::funky) {
			if (!mouse_button_info[0].has_been_read && mouse_button_info[0].is_pressed) {
				double xpos, ypos;
				glfwGetCursorPos(window, &xpos, &ypos);
				background_center.x = xpos;
				background_center.y = SCR_HEIGHT - ypos;
				mouse_button_info[0].has_been_read = true;
			}
		}
		if (shader == Shaders::marching && !mouse_button_info[0].has_been_read && mouse_button_info[0].is_pressed) {
			double xpos, ypos;
			glfwGetCursorPos(window, &xpos, &ypos);
			auto y_fixed = SCR_HEIGHT - ypos;
			for (int i = 0; i < circles.size(); i++) {
				auto d_square = (xpos - circles[i].pos[0]) * (xpos - circles[i].pos[0]) + (y_fixed - circles[i].pos[1]) * (y_fixed - circles[i].pos[1]);
				auto r_square = circles[i].r * circles[i].r;
				if (d_square < r_square) {
					idx_active_circle = i;
				}
			}
			mouse_button_info[0].has_been_read = true;
		}
		if (shader == Shaders::marching && mouse_button_info[0].is_pressed && idx_active_circle > -1) {
			double xpos, ypos;
			glfwGetCursorPos(window, &xpos, &ypos);
			auto y_fixed = SCR_HEIGHT - ypos;
			circles[idx_active_circle].pos[0] = xpos;
			circles[idx_active_circle].pos[1] = y_fixed;
			block_ids[idx_active_circle] = {(int)xpos / block_size,(int)y_fixed / block_size };
			glBindBuffer(GL_SHADER_STORAGE_BUFFER, ssbo_circles);
			glBufferSubData(GL_SHADER_STORAGE_BUFFER, sizeof(Circle) * idx_active_circle, sizeof(Circle), &circles[idx_active_circle]);
			glBindBuffer(GL_SHADER_STORAGE_BUFFER, ssbo_block_ids);
			glBufferSubData(GL_SHADER_STORAGE_BUFFER, sizeof(Block_id) * idx_active_circle, sizeof(Block_id), &block_ids[idx_active_circle]);
		}
		if (shader == Shaders::marching && !mouse_button_info[0].is_pressed) {
			idx_active_circle = -1;
		}

		double xpos, ypos;
		glfwGetCursorPos(window, &xpos, &ypos);

		switch (shader) {
		case Shaders::funky:
			initial_shader.use();
			initial_shader.setFloat("t", currentFrame);
			initial_shader.setVec2("mouse_pos", glm::vec2(xpos, ypos));
			initial_shader.setVec2("background_center", background_center);
			glDispatchCompute(workgroup_size_x, workgroup_size_y, 1);
			// make sure writing to image has finished before read
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
			//glBindBuffer(GL_SHADER_STORAGE_BUFFER, ssbo_circles);
			//if (idx_active_circle > -1) {
			//	circles[idx_active_circle].pos[0] = original_circle_pos[0] + 100 * sin(currentFrame);
			//	glBufferSubData(GL_SHADER_STORAGE_BUFFER, sizeof(Circle) * idx_active_circle, sizeof(Circle), &circles[idx_active_circle]);
			//}
			glDispatchCompute(workgroup_size_x, workgroup_size_y, 1);
			glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT);
			break;
		}

		solver.use();
		glDispatchCompute(workgroup_size_x, workgroup_size_y, 1);
		glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT);
		// These three lines maps device to host memory!
		int* vals = (int*)glMapBuffer(GL_SHADER_STORAGE_BUFFER, GL_READ_ONLY);
		int first_int = vals[5];
		glUnmapBuffer(GL_SHADER_STORAGE_BUFFER);

		// render image to quad
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
		screenQuad.use();

		renderQuad();
		glfwSwapBuffers(window);
		glfwPollEvents();

		frame_counter++;
	}

	glBindBuffer(GL_SHADER_STORAGE_BUFFER, 0); // unbind
	glDeleteTextures(1, &texture);
	glDeleteProgram(screenQuad.ID);
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