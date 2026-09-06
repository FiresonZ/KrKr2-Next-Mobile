cmake_minimum_required(VERSION 3.16)

project(engine_api LANGUAGES C CXX)

if(IOS)
    add_library(engine_api STATIC
        src/engine_api.cpp
    )
elseif(ANDROID)
    # Android: build as a self-contained shared library. Everything the engine
    # needs (core + plugins + vcpkg static deps) is linked into libengine_api.so
    # so the APK only has to ship one native library, loaded via dart:ffi.
    add_library(engine_api SHARED
        src/engine_api.cpp
        src/engine_api_android_jni.cpp
    )
else()
    add_library(engine_api SHARED
        src/engine_api.cpp
    )
endif()

target_compile_features(engine_api PRIVATE cxx_std_17)

if(IOS)
    # iOS static library: ensure symbols are visible so Dart FFI
    # DynamicLibrary.process() can find them when linked into Runner
    target_compile_definitions(engine_api PRIVATE ENGINE_API_EXPORT_SYMBOLS)
else()
    target_compile_definitions(engine_api PRIVATE ENGINE_API_BUILD_SHARED)
endif()
target_include_directories(engine_api
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
)

if(TARGET krkr2core AND TARGET krkr2plugin)
    target_compile_definitions(engine_api PRIVATE ENGINE_API_USE_KRKR2_RUNTIME)
    if(ANDROID)
        # 与上游(reAAAq/KrKr2-Next)一致：插件子库(krkr2plugin/psbfile/motionplayer/…)
        # 均用 target_sources(PUBLIC)，源码会经 INTERFACE_SOURCES 直接编进 engine_api.so，
        # 插件注册/全局构造器天然保留，因此这里必须普通链接 krkr2core + krkr2plugin，
        # 不能再包 "--whole-archive"。（曾经的 whole-archive 会强制把 psbfile.a/motionplayer.a
        # 的对象再拉一份，与 engine_api 里已编译的那份重复 → ld.lld duplicate symbol：
        # motion::ResourceManager / PSB::ArchiveType 等。）
        target_link_libraries(engine_api PRIVATE krkr2core krkr2plugin)
        # ANativeWindow (libandroid) + __android_log_print (liblog)
        target_link_libraries(engine_api PRIVATE android log)
    else()
        target_link_libraries(engine_api PRIVATE krkr2core krkr2plugin)
    endif()
endif()

# On Apple platforms, ANGLE GL symbols conflict with system OpenGL.framework.
# Use -force_load to ensure ANGLE's libGLESv2 and libEGL are fully linked
# so their GL/EGL functions take priority over system equivalents.
if(APPLE)
    find_package(unofficial-angle CONFIG QUIET)
    if(unofficial-angle_FOUND)
        # Get the actual .a file paths from the imported targets
        get_target_property(_ANGLE_GLES_LOC unofficial::angle::libGLESv2 IMPORTED_LOCATION_DEBUG)
        if(NOT _ANGLE_GLES_LOC)
            get_target_property(_ANGLE_GLES_LOC unofficial::angle::libGLESv2 IMPORTED_LOCATION_RELEASE)
        endif()
        get_target_property(_ANGLE_EGL_LOC unofficial::angle::libEGL IMPORTED_LOCATION_DEBUG)
        if(NOT _ANGLE_EGL_LOC)
            get_target_property(_ANGLE_EGL_LOC unofficial::angle::libEGL IMPORTED_LOCATION_RELEASE)
        endif()
        get_target_property(_ANGLE_LIB_LOC unofficial::angle::libANGLE IMPORTED_LOCATION_DEBUG)
        if(NOT _ANGLE_LIB_LOC)
            get_target_property(_ANGLE_LIB_LOC unofficial::angle::libANGLE IMPORTED_LOCATION_RELEASE)
        endif()

        if(_ANGLE_GLES_LOC)
            target_link_options(engine_api PRIVATE
                "LINKER:-force_load,${_ANGLE_GLES_LOC}"
            )
            message(STATUS "engine_api: force_load ANGLE libGLESv2: ${_ANGLE_GLES_LOC}")
        endif()
        if(_ANGLE_EGL_LOC)
            target_link_options(engine_api PRIVATE
                "LINKER:-force_load,${_ANGLE_EGL_LOC}"
            )
            message(STATUS "engine_api: force_load ANGLE libEGL: ${_ANGLE_EGL_LOC}")
        endif()
        if(_ANGLE_LIB_LOC)
            target_link_options(engine_api PRIVATE
                "LINKER:-force_load,${_ANGLE_LIB_LOC}"
            )
            message(STATUS "engine_api: force_load ANGLE libANGLE: ${_ANGLE_LIB_LOC}")
        endif()
    endif()
endif()

set_target_properties(engine_api PROPERTIES
    OUTPUT_NAME "engine_api"
)
