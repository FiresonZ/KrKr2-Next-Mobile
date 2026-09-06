# 共享函数：Android arm64 下为 CMake 型 overlay 端口强制 NDK aarch64 工具链。
#
# 背景（缓存）：项目 baseline 之前的多次构建在 arm64-android triplet 里产出了
# armv7 静态库并进了 vcpkg 二进制缓存（vcpkg 的 ABI 不感知 triplet 变量
# CMAKE_ANDROID_ARCH_ABI/ANDROID_ABI 的取值变化）。CMake 型端口链接该类库时报：
#   ld.lld: error: .../libbz2.a(...) is incompatible with aarch64linux
# 所以每个受影响端口都 bump port-version 强制重建（vcpkg ABI 含 port-version），
# 让其在以下修正后的构建参数下重新产出 arm64 版本。
#
# 背景（架构）：即便 triplet 已设置 CMAKE_ANDROID_ARCH_ABI=arm64-v8a，个别
# vcpkg_cmake_configure 路径仍可能回落 NDK 默认的 armeabi-v7a，故在此显式指定
# NDK 的 aarch64 编译器并强制 ANDROID_ABI / CMAKE_ANDROID_ARCH_ABI /
# CMAKE_SYSTEM_PROCESSOR，确保产出 arm64。
#
# 用法：在需要强制 arm64 的 CMake 型 overlay 端口 portfile.cmake 里，于
# vcpkg_cmake_configure 之前调用：
#   include("${CMAKE_CURRENT_LIST_DIR}/../_cmake_android_arm64.cmake")
#   set(_AT_OPTIONS "")
#   append_cmake_android_arm64_options(_AT_OPTIONS)
#   vcpkg_cmake_configure(SOURCE_PATH "${SOURCE_PATH}" OPTIONS ... ${_AT_OPTIONS})
# 仅当 Android 且 arm64 时生效；其余平台该函数不追加任何选项、不改环境，无副作用。

function(append_cmake_android_arm64_options OUT_VAR)
    if(NOT VCPKG_TARGET_IS_ANDROID OR NOT VCPKG_TARGET_ARCHITECTURE STREQUAL "arm64")
        return()
    endif()

    if(DEFINED VCPKG_ANDROID_NDK)
        set(_ndk "${VCPKG_ANDROID_NDK}")
    elseif(DEFINED ENV{ANDROID_NDK_HOME})
        set(_ndk "$ENV{ANDROID_NDK_HOME}")
    else()
        message(FATAL_ERROR "${PORT}(android): 未设置 ANDROID_NDK_HOME / VCPKG_ANDROID_NDK")
    endif()
    file(GLOB _prebuilt_dir_list DIRECTORIES "${_ndk}/toolchains/llvm/prebuilt/*")
    if(NOT _prebuilt_dir_list)
        message(FATAL_ERROR "${PORT}(android): 在 ${_ndk}/toolchains/llvm/prebuilt 下找不到工具链目录")
    endif()
    list(GET _prebuilt_dir_list 0 _prebuilt_dir)
    set(_bin  "${_prebuilt_dir}/bin")
    set(_api  "${VCPKG_ANDROID_PLATFORM}")
    if(NOT _api)
        set(_api "24")
    endif()
    set(_triple "aarch64-linux-android")
    set(ENV{CC}  "${_bin}/${_triple}${_api}-clang")
    set(ENV{CXX} "${_bin}/${_triple}${_api}-clang++")
    set(${OUT_VAR}
        -DANDROID_ABI=arm64-v8a
        -DCMAKE_ANDROID_ARCH_ABI=arm64-v8a
        -DCMAKE_SYSTEM_PROCESSOR=aarch64
        -DANDROID_NDK=${_ndk}
        -DCMAKE_SYSTEM_NAME=Android
        PARENT_SCOPE
    )
endfunction()