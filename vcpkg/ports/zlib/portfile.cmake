# Overlay zlib 端口（照搬 vcpkg 上游 baseline b1e15ef，port-version bump 到 1）。
#
# 背景一（缓存）：CI 的 vcpkg 二进制缓存里存有 triplet 修复（CMAKE_ANDROID_ARCH_ABI
# arm64-v8a）之前产出的 armv7 libz.a，glib/gio 链接时报
#   ld.lld: error: .../lib/libz.a(...) is incompatible with aarch64linux
# bump port-version 令缓存 key 变化，强制重建 arm64 版本。
#
# 背景二（架构）：与 pcre2 同源——zlib 走 vcpkg_cmake_configure + vcpkg android
# toolchain，在 arm64-android 上仍可能被错推成 armv7，故 Android arm64 分支显式
# 指定 NDK 的 aarch64 编译器并强制 ANDROID_ABI/CMAKE_ANDROID_ARCH_ABI。
# 非 Android 走原厂流程，行为不变。

# When this port is updated, the minizip port should be updated at the same time
vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO madler/zlib
    REF v${VERSION}
    SHA512 8c9642495bafd6fad4ab9fb67f09b268c69ff9af0f4f20cf15dfc18852ff1f312bd8ca41de761b3f8d8e90e77d79f2ccacd3d4c5b19e475ecf09d021fdfe9088
    HEAD_REF master
    PATCHES
        0001-Prevent-invalid-inclusions-when-HAVE_-is-set-to-0.patch
        0002-build-static-or-shared-not-both.patch
        0003-android-and-mingw-fixes.patch
)

# This is generated during the cmake build
file(REMOVE "${SOURCE_PATH}/zconf.h")

set(_ZLIB_OPTIONS
    -DSKIP_INSTALL_FILES=ON
    -DZLIB_BUILD_EXAMPLES=OFF)

if(VCPKG_TARGET_IS_ANDROID AND VCPKG_TARGET_ARCHITECTURE STREQUAL "arm64")
    # -------------------------------------------------------------------------
    # Android arm64：强制 NDK aarch64，避免 vcpkg android toolchain 错推 armv7
    # -------------------------------------------------------------------------
    if(DEFINED VCPKG_ANDROID_NDK)
        set(_ndk "${VCPKG_ANDROID_NDK}")
    elseif(DEFINED ENV{ANDROID_NDK_HOME})
        set(_ndk "$ENV{ANDROID_NDK_HOME}")
    else()
        message(FATAL_ERROR "zlib(android): 未设置 ANDROID_NDK_HOME / VCPKG_ANDROID_NDK")
    endif()
    file(GLOB _prebuilt_dir_list DIRECTORIES "${_ndk}/toolchains/llvm/prebuilt/*")
    if(NOT _prebuilt_dir_list)
        message(FATAL_ERROR "zlib(android): 在 ${_ndk}/toolchains/llvm/prebuilt 下找不到工具链目录")
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
    list(APPEND _ZLIB_OPTIONS
        -DANDROID_ABI=arm64-v8a
        -DCMAKE_ANDROID_ARCH_ABI=arm64-v8a
        -DCMAKE_SYSTEM_PROCESSOR=aarch64
        -DANDROID_NDK=${_ndk}
        -DCMAKE_SYSTEM_NAME=Android
    )
endif()

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        ${_ZLIB_OPTIONS}
    OPTIONS_DEBUG
        -DSKIP_INSTALL_HEADERS=ON
)

vcpkg_cmake_install()
file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/vcpkg-cmake-wrapper.cmake" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")

# Install the pkgconfig file
if(NOT DEFINED VCPKG_BUILD_TYPE OR VCPKG_BUILD_TYPE STREQUAL "release")
    if(VCPKG_TARGET_IS_WINDOWS)
        vcpkg_replace_string("${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel/zlib.pc" "-lz" "-lzlib")
    endif()
    file(COPY "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel/zlib.pc" DESTINATION "${CURRENT_PACKAGES_DIR}/lib/pkgconfig")
endif()
if(NOT DEFINED VCPKG_BUILD_TYPE OR VCPKG_BUILD_TYPE STREQUAL "debug")
    if(VCPKG_TARGET_IS_WINDOWS)
        vcpkg_replace_string("${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-dbg/zlib.pc" "-lz" "-lzlibd")
    endif()
    file(COPY "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-dbg/zlib.pc" DESTINATION "${CURRENT_PACKAGES_DIR}/debug/lib/pkgconfig")
endif()

vcpkg_fixup_pkgconfig()
vcpkg_copy_pdbs()

if(VCPKG_LIBRARY_LINKAGE STREQUAL "static")
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/include/zconf.h" "ifdef ZLIB_DLL" "if 0")
else()
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/include/zconf.h" "ifdef ZLIB_DLL" "if 1")
endif()

file(COPY "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
file(INSTALL "${SOURCE_PATH}/LICENSE" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}" RENAME copyright)
