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