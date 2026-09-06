cmake_minimum_required(VERSION 3.28)

find_program(CCACHE_PROGRAM ccache)

if (CCACHE_PROGRAM)
    set(CMAKE_C_COMPILER_LAUNCHER "${CCACHE_PROGRAM}")
    set(CMAKE_CXX_COMPILER_LAUNCHER "${CCACHE_PROGRAM}")
    message(STATUS "Ccache found: ${CCACHE_PROGRAM}")
endif ()

add_compile_definitions(
        $<$<CONFIG:Debug>:DEBUG>
        $<$<CONFIG:Debug>:_DEBUG>
        $<$<NOT:$<CONFIG:Debug>>:NDEBUG>
)

# Mobile-first project (iOS + Android; macOS kept as the Apple dev host):
# Flutter is the app shell on all three platforms.
# Third-party dependencies are provided through the vcpkg toolchain.
set(CMAKE_TOOLCHAIN_FILE $ENV{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake)

set(APP_NAME krkr2)

project(${APP_NAME})

option(ENABLE_TESTS "enable tests execute build(exclude ios/android)" ON)
option(BUILD_TOOLS "build tools execute build(exclude ios/android)" ON)
option(BUILD_ENGINE_API "build engine_api bridge library" ON)

# 渲染诊断探针（SourceSample/PostBlit/IOSurfacePixelSample/BlackScreen）编译开关。
# 默认 OFF：release 不含探针、零性能开销与日志刷屏。黑屏/渲染问题排查时
# cmake -DENABLE_RENDER_PROBE=ON 开启（见 docs/dev/rendering-diagnosis.md）。
option(ENABLE_RENDER_PROBE "enable per-frame render diagnostics (black-screen probes)" OFF)
if(ENABLE_RENDER_PROBE)
    add_compile_definitions(KRKR_RENDER_PROBE)
endif()

# 引擎运行时日志级别覆盖（独立于 debug/release）。
# empty=auto：按构建类型默认（Release→info，Debug→debug）。
# 显式设置时覆盖 NDEBUG 推断，经 KRKR_LOG_LEVEL_NUM 传给 engine_api.cpp，
# 供 CI/本地命令行在 workflow 里单独选择日志级别（排查时无需改代码）。
# 取值：trace|debug|info|warn|err|critical|off（大小写不敏感）。
set(KRKR_LOG_LEVEL "" CACHE STRING "engine runtime log level override: trace|debug|info|warn|err|critical|off (empty=auto by build type)")

if(KRKR_LOG_LEVEL)
    string(TOLOWER "${KRKR_LOG_LEVEL}" _krkr_log_level)
    if(_krkr_log_level STREQUAL "auto")
        # "auto" 等价于不设：按构建类型默认（Release→info，Debug→debug），不注入宏
        message(STATUS "KRKR_LOG_LEVEL=auto, keeping build-type default")
    elseif(_krkr_log_level STREQUAL "trace")
        set(_krkr_log_level_num 0)
    elseif(_krkr_log_level STREQUAL "debug")
        set(_krkr_log_level_num 1)
    elseif(_krkr_log_level STREQUAL "warn")
        set(_krkr_log_level_num 3)
    elseif(_krkr_log_level STREQUAL "err" OR _krkr_log_level STREQUAL "error")
        set(_krkr_log_level_num 4)
    elseif(_krkr_log_level STREQUAL "critical")
        set(_krkr_log_level_num 5)
    elseif(_krkr_log_level STREQUAL "off")
        set(_krkr_log_level_num 6)
    else()
        # "info" 或未知值：落为默认 info（spdlog 数值 2）；未知取值仅告警不报错。
        if(NOT _krkr_log_level STREQUAL "info")
            message(WARNING "Unknown KRKR_LOG_LEVEL '${KRKR_LOG_LEVEL}', falling back to info")
        endif()
        set(_krkr_log_level_num 2)
    endif()
    if(DEFINED _krkr_log_level_num)
        add_compile_definitions(KRKR_LOG_LEVEL_NUM=${_krkr_log_level_num})
        message(STATUS "KRKR_LOG_LEVEL=${KRKR_LOG_LEVEL} -> KRKR_LOG_LEVEL_NUM=${_krkr_log_level_num}")
    endif()
endif()

set(CMAKE_C_STANDARD 17)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(KRKR2CORE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cpp/core)
set(KRKR2PLUGIN_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cpp/plugins)

# iOS/macOS/Android use Flutter as the app shell; only the engine libraries are built.
# engine_api is built as a static library (iOS) / shared library (Android) and
# linked into the Flutter Runner.

# external lib
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/cpp/external)

# build library
add_subdirectory(${KRKR2CORE_PATH})
add_subdirectory(${KRKR2PLUGIN_PATH})
if(BUILD_ENGINE_API)
    add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/bridge/engine_api)
endif()

if(ENABLE_TESTS AND NOT IOS AND NOT ANDROID)
    enable_testing()
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tests/CMakeLists.txt")
        add_subdirectory(tests)
    endif()
endif()

if(BUILD_TOOLS AND NOT IOS AND NOT ANDROID)
    add_subdirectory(tools)
endif()
