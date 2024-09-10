cmake_minimum_required (VERSION 3.20)

# Enable Hot Reload for MSVC compilers if supported.
if (POLICY CMP0141)
  cmake_policy(SET CMP0141 NEW)
  set(CMAKE_MSVC_DEBUG_INFORMATION_FORMAT "$<IF:$<AND:$<C_COMPILER_ID:MSVC>,$<CXX_COMPILER_ID:MSVC>>,$<$<CONFIG:Debug,RelWithDebInfo>:EditAndContinue>,$<$<CONFIG:Debug,RelWithDebInfo>:ProgramDatabase>>")
endif()

project ("compute_shaders")

find_package(glad CONFIG REQUIRED)
find_package(glm CONFIG REQUIRED)
find_package(glfw3 CONFIG REQUIRED)

# Add source to this project's executable.
add_executable (compute_shaders "main.cpp")

if (CMAKE_VERSION VERSION_GREATER 3.12)
  set_property(TARGET compute_shaders PROPERTY CXX_STANDARD 20)
endif()

target_link_libraries(compute_shaders
	PRIVATE
	glad::glad
	glfw
	glm::glm
)

configure_file("physics_compute.glsl" "physics_compute.glsl" COPYONLY)
configure_file("physics_render.glsl" "physics_render.glsl" COPYONLY)
configure_file("shared_shapes.glsl" "shared_shapes.glsl" COPYONLY)
configure_file("solver.glsl" "solver.glsl" COPYONLY)
configure_file("mold.glsl" "mold.glsl" COPYONLY)
configure_file("rays.glsl" "rays.glsl" COPYONLY)
configure_file("screenQuad.vs" "screenQuad.vs" COPYONLY)
configure_file("screenQuad.fs" "screenQuad.fs" COPYONLY)
configure_file("computeShader.glsl" "computeShader.glsl" COPYONLY)
configure_file("voronoi.glsl" "voronoi.glsl" COPYONLY)
configure_file("font_bitmap_16.bmp" "font_bitmap_16.bmp" COPYONLY)