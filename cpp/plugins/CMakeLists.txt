cmake_minimum_required(VERSION 3.19)
project(krkr2plugin)

add_library(${PROJECT_NAME} STATIC)

target_sources(${PROJECT_NAME} PUBLIC
    scriptsEx.cpp
    win32dialog.cpp
    dirlist.cpp
    csvParser.cpp
    layerExMovie.cpp
    varfile.cpp
    saveStruct.cpp
    getabout.cpp
    addFont.cpp
    wutcwf.cpp
    windowEx.cpp
    getSample.cpp
    layerExPerspective.cpp
    fftgraph.cpp
    LayerExBase.cpp
    xp3filter.cpp
    extrans.cpp
    textrender.cpp
    alphamovie.cpp
    layerExBTOA.cpp
    layerExImage.cpp
    layerExRaster.cpp
    layerExAreaAverage.cpp
    layerExLongExposure.cpp
    krkrgles.cpp
    drawDeviceD2DCompat.cpp
    wfBasicEffectCompat.cpp
    wfTypicalDSPCompat.cpp
)

target_include_directories(${PROJECT_NAME} PUBLIC
    ${KRKR2CORE_PATH}/
    ${KRKR2CORE_PATH}/base
    ${KRKR2CORE_PATH}/environ
    ${KRKR2CORE_PATH}/environ/win32
    ${KRKR2CORE_PATH}/environ/sdl
    ${KRKR2CORE_PATH}/extension
    ${KRKR2CORE_PATH}/sound
    ${KRKR2CORE_PATH}/sound/win32
    ${KRKR2CORE_PATH}/tjs2
    ${KRKR2CORE_PATH}/utils
    ${KRKR2CORE_PATH}/utils/win32
    ${KRKR2CORE_PATH}/visual
)

add_definitions(-D__STDC_CONSTANT_MACROS -DTJS_TEXT_OUT_CRLF)

# ---------------------------------------------------------------------------
# Live2D Cubism SDK
# ---------------------------------------------------------------------------
# NOTE: cpp/plugins/cubism/{Framework,Core/lib} are gitignored (proprietary
# binary SDK, download from live2d.com — see docs/dev/conventions.md §4).
# CI machines do not have them, so Live2D support is built ONLY when the SDK
# is present on disk; otherwise krkrlive2d.cpp is excluded from the plugin
# and CubismFramework becomes an empty INTERFACE target so downstream
# target_link_libraries() calls keep working.
set(CUBISM_DIR ${CMAKE_CURRENT_SOURCE_DIR}/cubism)
set(CUBISM_CORE_DIR ${CUBISM_DIR}/Core)
set(CUBISM_FW_DIR ${CUBISM_DIR}/Framework)

file(GLOB_RECURSE CUBISM_FW_SOURCES
    ${CUBISM_FW_DIR}/*.cpp
)
# Exclude non-OpenGL renderers (already removed from tree, but safety net)
list(FILTER CUBISM_FW_SOURCES EXCLUDE REGEX ".*/D3D9/.*|.*/D3D11/.*|.*/Vulkan/.*|.*/Metal/.*|.*/Cocos2d/.*")

set(CUBISM_CORE_LIB "")
if(IOS)
    set(CUBISM_CORE_LIB ${CUBISM_CORE_DIR}/lib/ios/Release-iphoneos/libLive2DCubismCore.a)
elseif(APPLE)
    if(CMAKE_OSX_ARCHITECTURES STREQUAL "x86_64")
        set(CUBISM_CORE_LIB ${CUBISM_CORE_DIR}/lib/macos/x86_64/libLive2DCubismCore.a)
    else()
        set(CUBISM_CORE_LIB ${CUBISM_CORE_DIR}/lib/macos/arm64/libLive2DCubismCore.a)
    endif()
endif()

if(CUBISM_FW_SOURCES AND CUBISM_CORE_LIB AND EXISTS "${CUBISM_CORE_LIB}")
    add_library(CubismFramework STATIC ${CUBISM_FW_SOURCES})
    target_include_directories(CubismFramework PUBLIC
        ${CUBISM_FW_DIR}
        ${CUBISM_CORE_DIR}/include
    )
    target_compile_definitions(CubismFramework PUBLIC CSM_TARGET_ANGLE_ES2)

    # ANGLE headers for CubismFramework's OpenGLES2 renderer
    find_package(unofficial-angle CONFIG QUIET)
    if(unofficial-angle_FOUND)
        target_link_libraries(CubismFramework PRIVATE
            unofficial::angle::libEGL
            unofficial::angle::libGLESv2
        )
        # EGL/GLES2 headers come from egl-registry/opengl-registry via vcpkg
        # but aren't automatically propagated to standalone static library targets.
        get_target_property(_EGL_INCS unofficial::angle::libEGL INTERFACE_INCLUDE_DIRECTORIES)
        if(_EGL_INCS)
            target_include_directories(CubismFramework PRIVATE ${_EGL_INCS})
        endif()
        if(VCPKG_INSTALLED_DIR AND VCPKG_TARGET_TRIPLET)
            target_include_directories(CubismFramework PRIVATE
                ${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/include)
        endif()
    endif()

    target_link_libraries(CubismFramework PUBLIC ${CUBISM_CORE_LIB})

    # krkrlive2d.cpp (Live2D TJS plugin) compiles only when the SDK is present
    target_sources(${PROJECT_NAME} PRIVATE krkrlive2d.cpp)
    target_include_directories(${PROJECT_NAME} PUBLIC
        ${CUBISM_FW_DIR}
        ${CUBISM_CORE_DIR}/include
    )
    target_compile_definitions(${PROJECT_NAME} PUBLIC CSM_TARGET_ANGLE_ES2)
    # 显式“Live2D 已启用”信号：cubism 缺失时（CI/缺 SDK/被 gitignore）krkrlive2d.cpp
    # 不参与编译，其余引用侧（engine_api / krkrgles）需以此宏保护对
    # TVPRegisterKrkrLive2DPluginAnchor / g_live2dRenderTarget 的引用，避免链接期未定义符号。
    target_compile_definitions(${PROJECT_NAME} PUBLIC KRKR2_LIVE2D)
else()
    # SDK absent on disk (gitignored) — stub the target so downstream links work
    add_library(CubismFramework INTERFACE)
    target_include_directories(CubismFramework INTERFACE ${CUBISM_CORE_DIR}/include)
    message(WARNING "Live2D Cubism SDK not found (cubism/Framework + Core/lib) — Live2D plugin disabled")
endif()

target_link_libraries(${PROJECT_NAME} PUBLIC CubismFramework)

target_include_directories(${PROJECT_NAME} PUBLIC ${KRKR2PLUGIN_PATH} ${KRKR2PLUGIN_PATH}/simplebinder})
target_link_libraries(${PROJECT_NAME} PUBLIC krkr2core)

add_subdirectory(psdfile)
add_subdirectory(psbfile)
add_subdirectory(layerex_draw)
add_subdirectory(motionplayer)
add_subdirectory(kagparserex)

#add_subdirectory(json)
add_subdirectory(fstat)
#add_subdirectory(steam)
#add_subdirectory(DrawDeviceForSteam)
target_link_libraries(${PROJECT_NAME} PUBLIC
        psdfile
        psbfile
        layerExDraw
        motionplayer
        kagparserex
        fstat
#        json steam DrawDeviceForSteam
)

find_package(fmt CONFIG REQUIRED)
target_link_libraries(${PROJECT_NAME} PRIVATE fmt::fmt)

find_package(spdlog CONFIG REQUIRED)
target_link_libraries(${PROJECT_NAME} PRIVATE spdlog::spdlog)
