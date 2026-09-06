cmake_minimum_required(VERSION 3.19)
project(core_sound_module LANGUAGES CXX)

set(SOUND_PATH ${CMAKE_CURRENT_LIST_DIR})
set(SOUND_SOURCE_FILES
    ${SOUND_PATH}/CDDAIntf.cpp
    ${SOUND_PATH}/FFWaveDecoder.cpp
    # MathAlgorithms.cpp removed: same functions already defined in
    # core_utils_module/MathAlgorithms_Default.cpp (linked via core_utils_module dep)
    ${SOUND_PATH}/MIDIIntf.cpp
    ${SOUND_PATH}/PhaseVocoderDSP.cpp
    ${SOUND_PATH}/PhaseVocoderFilter.cpp
    ${SOUND_PATH}/SoundBufferBaseIntf.cpp
    ${SOUND_PATH}/VorbisWaveDecoder.cpp
    ${SOUND_PATH}/WaveFormatConverter.cpp
#    ${SOUND_PATH}/WaveFormatConverter_SSE.cpp
    ${SOUND_PATH}/WaveIntf.cpp
    ${SOUND_PATH}/WaveLoopManager.cpp
    ${SOUND_PATH}/WaveSegmentQueue.cpp
#    ${SOUND_PATH}/xmmlib.cpp

    ${SOUND_PATH}/win32/CDDAImpl.cpp
    ${SOUND_PATH}/win32/MIDIImpl.cpp
    ${SOUND_PATH}/win32/SoundBufferBaseImpl.cpp
#    ${SOUND_PATH}/win32/tvpsnd.c
    ${SOUND_PATH}/win32/tvpsnd.cpp
#    ${SOUND_PATH}/win32/tvpsnd.idl
    ${SOUND_PATH}/win32/WaveImpl.cpp
    ${SOUND_PATH}/win32/WaveMixer.cpp
)

set(SOUND_HEADERS_DIR
    ${SOUND_PATH}/
    ${SOUND_PATH}/win32
)

add_library(${PROJECT_NAME} STATIC ${SOUND_SOURCE_FILES})
target_include_directories(${PROJECT_NAME} PUBLIC ${SOUND_HEADERS_DIR})
target_link_libraries(${PROJECT_NAME} PUBLIC tjs2 PRIVATE core_base_module core_movie_module core_utils_module core_environ_module)

find_package(Vorbis CONFIG REQUIRED)
find_package(Opus CONFIG REQUIRED)
find_package(OpusFile CONFIG REQUIRED)

find_package(OpenAL CONFIG REQUIRED)

# WaveMixer.cpp 在 Android 上用 oboe 作为低延迟音频渲染后端（头文件 oboe/Oboe.h，
# 类 tTVPAudioRendererOboe），运行时失败回退到 tTVPAudioRendererAL（OpenAL）。
# 依赖已加在 vcpkg.json（platform=android）。
#
# 注意：vcpkg 的 oboe 端口（1.8.0）只提供 pkg-config、不输出 CMake config 文件，
# 因此不能用 find_package(oboe CONFIG)；头文件 oboe/Oboe.h 已在 vcpkg_installed/include
# 全局 include 路径里，这里直接用 find_library 定位静态库 liboboe.a 并链接。
# oboe 的 OpenSLES 后端还需要链接系统平台库 libOpenSLES.so。
if(ANDROID)
    find_library(OBOE_STATIC_LIB oboe)
    if(NOT OBOE_STATIC_LIB)
        message(FATAL_ERROR "oboe static library not found via find_library(oboe); check vcpkg oboe install")
    endif()
endif()

target_link_libraries(${PROJECT_NAME} PRIVATE
    Vorbis::vorbis
    Vorbis::vorbisfile
    Vorbis::vorbisenc

    Opus::opus
    OpusFile::opusfile
    OpenAL::OpenAL
)

if(ANDROID)
    target_link_libraries(${PROJECT_NAME} PRIVATE ${OBOE_STATIC_LIB} OpenSLES)
endif()
