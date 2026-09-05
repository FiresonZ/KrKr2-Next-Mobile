# Overlay pcre2 端口（照搬 vcpkg 上游，Android arm64 分支强制 aarch64）。
#
# 背景：vcpkg 原厂 pcre2 走 vcpkg_cmake_configure + vcpkg 的 android toolchain，
# 但在 arm64-android 上仍被错推成 armv7，产出 32 位 libpcre2-8.a；glib 链接它时
# 报
#   ld.lld: error: .../libpcre2-8.a(pcre2_*.o) is incompatible with aarch64linux
# 解法：仅 Android arm64 分支，显式指定 NDK 的 `aarch64-linux-android<api>-clang`
# 编译器并强制 ANDROID_ABI=arm64-v8a / CMAKE_ANDROID_ARCH_ABI / CMAKE_SYSTEM_PROCESSOR，
# 令 NDK toolchain 按 aarch64 构建（与 overlay libiconv/libffi/gettext-libintl 同一思路）。
# 非 Android 走原厂流程，行为不变。

vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO PCRE2Project/pcre2
    REF "pcre2-${VERSION}"
    SHA512 c945dfcf31795ab9ed2a19fec775087b3daaa64235a632260e7d8c7fc9fcb7f47321540670bd05cf691af52dd8df5679d148ef0829276163d5db3cecd0e7c2da
    HEAD_REF master
    PATCHES
        pcre2-10.35_fix-uwp.patch
        no-static-suffix.patch
        fix-cmake.patch
)

vcpkg_from_github(
    OUT_SOURCE_PATH SLJIT_SOURCE_PATH
    REPO zherczeg/sljit
    REF 8481dde366d0346ac5475aa03ae48ee44fa74ca4
    SHA512 99a6ab54ee6b9b3b2e241d2f29eb24217c8385bb3b756411116eaed0d91f008401822406710431ccf17ddf687828b8ab6933230e44144bea03f550c0f5ac9210
    HEAD_REF main
)

file(REMOVE_RECURSE "${SOURCE_PATH}/deps/sljit")
file(MAKE_DIRECTORY "${SOURCE_PATH}/deps")
file(RENAME "${SLJIT_SOURCE_PATH}" "${SOURCE_PATH}/deps/sljit")

string(COMPARE EQUAL "${VCPKG_LIBRARY_LINKAGE}" "static" BUILD_STATIC)
string(COMPARE EQUAL "${VCPKG_LIBRARY_LINKAGE}" "dynamic" INSTALL_PDB)
string(COMPARE EQUAL "${VCPKG_CRT_LINKAGE}" "static" BUILD_STATIC_CRT)

vcpkg_check_features(
    OUT_FEATURE_OPTIONS FEATURE_OPTIONS
    FEATURES
        jit   PCRE2_SUPPORT_JIT
)

if(VCPKG_TARGET_IS_ANDROID AND VCPKG_TARGET_ARCHITECTURE STREQUAL "arm64")
    # -------------------------------------------------------------------------
    # Android arm64：强制 NDK aarch64，避免 vcpkg android toolchain 错推 armv7
    # -------------------------------------------------------------------------
    if(DEFINED VCPKG_ANDROID_NDK)
        set(_ndk "${VCPKG_ANDROID_NDK}")
    elseif(DEFINED ENV{ANDROID_NDK_HOME})
        set(_ndk "$ENV{ANDROID_NDK_HOME}")
    else()
        message(FATAL_ERROR "pcre2(android): 未设置 ANDROID_NDK_HOME / VCPKG_ANDROID_NDK")
    endif()
    file(GLOB _prebuilt_dir_list DIRECTORIES "${_ndk}/toolchains/llvm/prebuilt/*")
    if(NOT _prebuilt_dir_list)
        message(FATAL_ERROR "pcre2(android): 在 ${_ndk}/toolchains/llvm/prebuilt 下找不到工具链目录")
    endif()
    list(GET _prebuilt_dir_list 0 _prebuilt_dir)
    set(_bin  "${_prebuilt_dir}/bin")
    set(_api  "${VCPKG_ANDROID_PLATFORM}")
    if(NOT _api)
        set(_api "24")
    endif()
    set(_triple "aarch64-linux-android")
    set(_cc  "${_bin}/${_triple}${_api}-clang")
    set(_cxx "${_bin}/${_triple}${_api}-clang++")
    # 环境变量 CC/CXX 让 NDK toolchain 优先选 arm64 编译器
    set(ENV{CC}  "${_cc}")
    set(ENV{CXX} "${_cxx}")
    list(APPEND FEATURE_OPTIONS
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
        ${FEATURE_OPTIONS}
        -DBUILD_STATIC_LIBS=${BUILD_STATIC}
        -DPCRE2_STATIC_RUNTIME=${BUILD_STATIC_CRT}
        -DPCRE2_BUILD_PCRE2_8=ON
        -DPCRE2_BUILD_PCRE2_16=ON
        -DPCRE2_BUILD_PCRE2_32=ON
        -DPCRE2_SUPPORT_UNICODE=ON
        -DPCRE2_BUILD_TESTS=OFF
        -DPCRE2_BUILD_PCRE2GREP=OFF
        -DCMAKE_DISABLE_FIND_PACKAGE_BZip2=ON
        -DCMAKE_DISABLE_FIND_PACKAGE_ZLIB=ON
        -DCMAKE_DISABLE_FIND_PACKAGE_Readline=ON
        -DCMAKE_DISABLE_FIND_PACKAGE_Editline=ON
        -DINSTALL_MSVC_PDB=${INSTALL_PDB}
    )

vcpkg_cmake_install()
vcpkg_copy_pdbs()

file(READ "${CURRENT_PACKAGES_DIR}/include/pcre2.h" PCRE2_H)
if(BUILD_STATIC)
    string(REPLACE "defined(PCRE2_STATIC)" "1" PCRE2_H "${PCRE2_H}")
else()
    string(REPLACE "defined(PCRE2_STATIC)" "0" PCRE2_H "${PCRE2_H}")
endif()
file(WRITE "${CURRENT_PACKAGES_DIR}/include/pcre2.h" "${PCRE2_H}")

vcpkg_fixup_pkgconfig()
vcpkg_cmake_config_fixup(CONFIG_PATH lib/cmake/${PORT})

file(REMOVE_RECURSE
    "${CURRENT_PACKAGES_DIR}/man"
    "${CURRENT_PACKAGES_DIR}/share/doc"
    "${CURRENT_PACKAGES_DIR}/debug/include"
    "${CURRENT_PACKAGES_DIR}/debug/man"
    "${CURRENT_PACKAGES_DIR}/debug/share")

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/tools/pcre2")
file(RENAME "${CURRENT_PACKAGES_DIR}/bin/pcre2-config" "${CURRENT_PACKAGES_DIR}/tools/pcre2/pcre2-config")
vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/tools/pcre2/pcre2-config" "${CURRENT_PACKAGES_DIR}" [[$(cd "$(dirname "$0")/../.."; pwd -P)]])
if(NOT VCPKG_BUILD_TYPE)
    file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/tools/pcre2/debug")
    file(RENAME "${CURRENT_PACKAGES_DIR}/debug/bin/pcre2-config" "${CURRENT_PACKAGES_DIR}/tools/pcre2/debug/pcre2-config")
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/tools/pcre2/debug/pcre2-config" "${CURRENT_PACKAGES_DIR}/debug" [[$(cd "$(dirname "$0")/../../../debug"; pwd -P)]])
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/tools/pcre2/debug/pcre2-config" [[${prefix}/include]] [[${prefix}/../include]])
endif()
if(VCPKG_LIBRARY_LINKAGE STREQUAL "static")
    file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/bin" "${CURRENT_PACKAGES_DIR}/bin")
endif()

file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")