cmake_minimum_required(VERSION 3.19)
project(krkr2_tests CXX)

# SIMD vs 标量逐像素比对测试（Linux 宿主）。
# core_visual_module 内含 tvpgl.cpp（*_c 标量）与 tvpgl_simd（_hwy），
# 静态库按需拉取，测试只引用 tvpgl 混合函数，不会拖入渲染路径。
add_executable(tvpgl_simd_compare tvpgl_simd_compare.cpp)
target_link_libraries(tvpgl_simd_compare PRIVATE core_visual_module)

add_test(NAME tvpgl_simd_compare COMMAND tvpgl_simd_compare)