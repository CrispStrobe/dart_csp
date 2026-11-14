cmake_minimum_required(VERSION 3.22)
project(dart_csp_sparse_step LANGUAGES CXX)

if(NOT EIGEN_SOURCE_DIR OR NOT EXISTS "${EIGEN_SOURCE_DIR}/Eigen/Core")
  message(FATAL_ERROR "Set EIGEN_SOURCE_DIR to the verified Eigen 3.4.0 source checkout")
endif()

add_library(dart_csp_sparse_step SHARED sparse_step.cpp)
target_compile_features(dart_csp_sparse_step PRIVATE cxx_std_17)
target_compile_definitions(dart_csp_sparse_step PRIVATE EIGEN_MPL2_ONLY)
target_include_directories(dart_csp_sparse_step SYSTEM PRIVATE "${EIGEN_SOURCE_DIR}")
target_compile_options(dart_csp_sparse_step PRIVATE -Wall -Wextra -Wpedantic)

