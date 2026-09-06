cmake_minimum_required(VERSION 3.19)
project(core_environ_module LANGUAGES CXX)

if(APPLE)
    enable_language(OBJC OBJCXX)
endif()

set(ENVIRON_PATH ${CMAKE_CURRENT_LIST_DIR})
set(ENVIRON_SOURCE_FILES
    ${ENVIRON_PATH}/Application.cpp
    ${ENVIRON_PATH}/DetectCPU.cpp
    ${ENVIRON_PATH}/DumpSend.cpp
    ${ENVIRON_PATH}/EngineBootstrap.cpp
    ${ENVIRON_PATH}/EngineLoop.cpp
    ${ENVIRON_PATH}/XP3ArchiveRepack.cpp

    $<$<BOOL:${MACOS}>:${ENVIRON_PATH}/apple/macos/platform.mm>

    $<$<BOOL:${IOS}>:${ENVIRON_PATH}/apple/ios/platform.mm>

    ${ENVIRON_PATH}/MainScene.cpp

    ${ENVIRON_PATH}/ConfigManager/GlobalConfigManager.cpp
    ${ENVIRON_PATH}/ConfigManager/IndividualConfigManager.cpp
    ${ENVIRON_PATH}/ConfigManager/LocaleConfigManager.cpp
    ${ENVIRON_PATH}/sdl/tvpsdl.cpp

    # ui/ — all removed (Flutter handles UI now).
    # Stub implementations are in stubs/ui_stubs.cpp
    ${ENVIRON_PATH}/stubs/ui_stubs.cpp

    # Linux 宿主平台实现（CI 引擎核心验证用）。文件体有 #if defined(__linux__)
    # 守卫，在 Apple/Android 上为空翻译单元，不影响各平台原生实现。
    ${ENVIRON_PATH}/stubs/platform_linux.cpp

    # Android 平台实现（文件体有 #if defined(__ANDROID__) 守卫）。
    # 移动端 UI 由 Flutter 接管，其余平台函数(文件/时钟/内存/生命周期)与 Linux 同源，
    # 具体见 android/platform_android.cpp。
    ${ENVIRON_PATH}/android/platform_android.cpp

    ${ENVIRON_PATH}/win32/SystemControl.cpp
)

set(ENVIRON_HEADERS_DIR
    ${ENVIRON_PATH}/
    ${ENVIRON_PATH}/win32
    ${ENVIRON_PATH}/sdl
)

add_library(${PROJECT_NAME} STATIC ${ENVIRON_SOURCE_FILES})
target_include_directories(${PROJECT_NAME} PUBLIC ${ENVIRON_HEADERS_DIR})
target_link_libraries(${PROJECT_NAME} PUBLIC tjs2 PRIVATE core_base_module core_visual_module core_sound_module core_plugin_module core_movie_module core_utils_module)

find_package(7zip CONFIG REQUIRED)
find_package(tinyxml2 CONFIG REQUIRED)
find_package(unofficial-minizip CONFIG REQUIRED)

target_link_libraries(${PROJECT_NAME} PRIVATE
        7zip::7zip
        unofficial::minizip::minizip
        tinyxml2::tinyxml2
)
