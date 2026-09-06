# Overlay pixman 端口（照搬 vcpkg 上游 baseline b1e15ef）。
#
# 修复：vcpkg meson 交叉编译在 Android arm64 上被错推为 armv7，链接时报
#   ld.lld: error: .../lib...(xxx) is incompatible with armelf_linux_eabi
# 与 glib/fontconfig/cairo 同根因。在 vcpkg_configure_meson 之前 include 共享
# 模块 _meson_android_arm64.cmake 注入 aarch64 交叉覆盖，见该文件注释。
include("${CMAKE_CURRENT_LIST_DIR}/../_meson_android_arm64.cmake")

vcpkg_from_gitlab(
    OUT_SOURCE_PATH SOURCE_PATH
    GITLAB_URL https://gitlab.freedesktop.org
    REPO pixman/pixman
    REF "pixman-${VERSION}"
    SHA512 a878d866fbd4d609fabac6a5acac4d0a5ffd0226d926c09d3557261b770f1ad85b2f2d90a48b7621ad20654e52ecccbca9f1a57a36bd5e58ecbe59cca9e3f25d
    PATCHES
        no-host-cpu-checks.patch
        missing_intrin_include.patch
)

set(x86_architectures x86 x64)
if(VCPKG_TARGET_ARCHITECTURE IN_LIST x86_architectures AND NOT VCPKG_TARGET_IS_UWP)
    list(APPEND OPTIONS
        -Dmmx=enabled
        -Dsse2=enabled
        -Dssse3=enabled
    )
else()
    list(APPEND OPTIONS
        -Dmmx=disabled
        -Dsse2=disabled
        -Dssse3=disabled
    )
    if(VCPKG_TARGET_IS_ANDROID)
        vcpkg_cmake_get_vars(cmake_vars_file)
        include("${cmake_vars_file}")
        find_path(cpu_features_dir
            NAMES cpu-features.c
            PATHS "${VCPKG_DETECTED_CMAKE_ANDROID_NDK}"
            PATH_SUFFIXES
                "sources/android/cpufeatures" # NDK r27c
            NO_DEFAULT_PATH
        )
        if(VCPKG_DETECTED_CMAKE_ANDROID_ARM_NEON AND cpu_features_dir)
            list(APPEND OPTIONS
                "-Dcpu-features-path=${cpu_features_dir}"
            )
        endif()
    endif()
    if(VCPKG_TARGET_IS_WINDOWS)
        # -Darm-simd=enabled does not work with arm64-windows
        list(APPEND OPTIONS
            -Da64-neon=disabled
            -Darm-simd=disabled
            -Dneon=disabled
        )
    endif()
endif()

vcpkg_configure_meson(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS ${OPTIONS}
        -Ddemos=disabled
        -Dgtk=disabled
        -Dlibpng=enabled
        -Dtests=disabled
)
vcpkg_install_meson()
vcpkg_fixup_pkgconfig()

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")

set(licenses "${SOURCE_PATH}/COPYING")
if(VCPKG_DETECTED_CMAKE_ANDROID_ARM_NEON AND cpu_features_dir)
    file(READ "${cpu_features_dir}/cpu-features.c" cpu_features_c)
    string(REGEX REPLACE "[*]/.*" "*/\n" cpu_features_license "${cpu_features_c}")
    file(WRITE "${CURRENT_PACKAGES_DIR}/${TARGET_TRIPLET}-rel/cpu-features (BSD-2-Clause)" "${cpu_features_license}")
    list(APPEND licenses "${CURRENT_PACKAGES_DIR}/${TARGET_TRIPLET}-rel/cpu-features (BSD-2-Clause)")
endif()
vcpkg_install_copyright(FILE_LIST ${licenses})
