cmake_minimum_required(VERSION 3.22)
project(ceres_geometry_adapter LANGUAGES CXX)

find_package(Ceres 2.3 REQUIRED)
if(NOT NLOHMANN_JSON_INCLUDE_DIR)
  message(FATAL_ERROR "Set NLOHMANN_JSON_INCLUDE_DIR to the pinned nlohmann/json single_include directory")
endif()

add_executable(ceres_geometry_adapter main.cpp)
target_compile_features(ceres_geometry_adapter PRIVATE cxx_std_17)
target_compile_definitions(ceres_geometry_adapter PRIVATE EIGEN_MPL2_ONLY)
target_include_directories(ceres_geometry_adapter PRIVATE "${NLOHMANN_JSON_INCLUDE_DIR}")
target_link_libraries(ceres_geometry_adapter PRIVATE Ceres::ceres)
target_compile_options(ceres_geometry_adapter PRIVATE -Wall -Wextra -Wpedantic)
