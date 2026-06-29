# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. Keep this low so the stub builds
# on older desktop toolchains.
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "record_windows")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "record_windows_plugin")

list(APPEND PLUGIN_SOURCES
  "record_windows_plugin.cpp"
  "record_windows_plugin.h"
)

add_library(${PLUGIN_NAME} SHARED
  "include/record_windows/record_windows_plugin_c_api.h"
  "record_windows_plugin_c_api.cpp"
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

set(record_windows_bundled_libraries
  ""
  PARENT_SCOPE
)
