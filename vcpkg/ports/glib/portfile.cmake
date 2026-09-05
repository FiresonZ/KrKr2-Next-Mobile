# vcpkg_from_* is not used because the project uses submodules.
string(REGEX MATCH "^([0-9]*[.][0-9]*)" GLIB_MAJOR_MINOR "${VERSION}")
vcpkg_download_distfile(GLIB_ARCHIVE
    URLS "https://download.gnome.org/sources/glib/${GLIB_MAJOR_MINOR}/glib-${VERSION}.tar.xz"
    FILENAME "glib-${VERSION}.tar.xz"
    SHA512 430928d7d7a442fc3927ca943f2569035fe8768768a0ebc6720ae1ef152b56fc5f8d4215d21b4828cc2f39a8632c907ed2c52a0c8566da1c533a2e049a1a121f
)

vcpkg_extract_source_archive(SOURCE_PATH
    ARCHIVE "${GLIB_ARCHIVE}"
    PATCHES
        use-libiconv-on-windows.patch
        libintl.patch
)

set(LANGUAGES C CXX)
if(VCPKG_TARGET_IS_OSX OR VCPKG_TARGET_IS_IOS)
    list(APPEND LANGUAGES OBJC OBJCXX)
endif()

vcpkg_list(SET OPTIONS)
if (selinux IN_LIST FEATURES)
    if(NOT EXISTS "/usr/include/selinux")
        message(WARNING "SELinux was not found in its typical system location. Your build may fail. You can install SELinux with \"apt-get install selinux libselinux1-dev\".")
    endif()
    list(APPEND OPTIONS -Dselinux=enabled)
else()
    list(APPEND OPTIONS -Dselinux=disabled)
endif()

if (libmount IN_LIST FEATURES)
    list(APPEND OPTIONS -Dlibmount=enabled)
else()
    list(APPEND OPTIONS -Dlibmount=disabled)
endif()

# ---------------------------------------------------------------------------
# Android arm64 meson 交叉编译修复
#
# 背景：vcpkg 的 meson 交叉编译在 Android 上存在缺陷——构建系统生成 meson
# 交叉文件所需的编译参数取自 `get_cmake_vars`（z_vcpkg_get_cmake_vars +
# _vcpkg_adjust_flags），该流程无论 triplet 是否设置 ANDROID_ABI=arm64-v8a，
# 都会回落 NDK 默认的 `--target=armv7-none-linux-androideabi21`（armv7/API21）。
# 结果 glib 及其工具（gobject-query/gio/gtester…）全部按 32 位 ARM 编译、链接，
# 而其它端口（libffi 走 autotools --host、pcre2 走 cmake）都正确产出了 arm64 静态库，
# 于是在链接时报：
#   ld.lld: error: .../libffi.a(...) is incompatible with armelf_linux_eabi
#
# 修复方案：仅对 arm64-android，在 vcpkg 生成的交叉文件之后追加一个补充 meson
# 交叉文件（VCPKG_MESON_CROSS_FILE/…_DEBUG/…_RELEASE）。meson 对后出现的交叉文件
# 取覆盖优先级：我们覆盖 [binaries] c/cpp 为 NDK 的 aarch64 编译器包装器（内嵌
# target+sysroot），并覆盖 c_args/cpp_args 去掉错误的 --target=armv7，从而保证
# glib 按 arm64 编译/链接，与 libffi/pcre2 一致。其余二进制/属性/host_machine 仍
# 复用 vcpkg 生成的交叉文件。
if(VCPKG_TARGET_IS_ANDROID AND VCPKG_TARGET_ARCHITECTURE STREQUAL "arm64")
    if(DEFINED ENV{ANDROID_NDK_HOME} AND EXISTS "$ENV{ANDROID_NDK_HOME}")
        set(_glib_ndk_root "$ENV{ANDROID_NDK_HOME}")
    elseif(DEFINED VCPKG_ANDROID_NDK AND EXISTS "${VCPKG_ANDROID_NDK}")
        set(_glib_ndk_root "${VCPKG_ANDROID_NDK}")
    else()
        set(_glib_ndk_root "")
    endif()
    if(_glib_ndk_root)
        if(CMAKE_HOST_APPLE)
            if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "arm64|aarch64")
                set(_glib_host_dir "darwin-arm64")
            else()
                set(_glib_host_dir "darwin-x86_64")
            endif()
        elseif(CMAKE_HOST_WIN32)
            set(_glib_host_dir "windows-x86_64")
        else()
            set(_glib_host_dir "linux-x86_64")
        endif()
        set(_glib_api "${VCPKG_ANDROID_PLATFORM}")
        if(NOT _glib_api)
            set(_glib_api "24")
        endif()
        set(_glib_bin "${_glib_ndk_root}/toolchains/llvm/prebuilt/${_glib_host_dir}/bin")
        set(_glib_sysroot "${_glib_ndk_root}/toolchains/llvm/prebuilt/${_glib_host_dir}/sysroot")
        set(_glib_target "aarch64-linux-android${_glib_api}")
        set(_glib_c_wrap "${_glib_bin}/aarch64-linux-android${_glib_api}-clang")
        set(_glib_cpp_wrap "${_glib_bin}/aarch64-linux-android${_glib_api}-clang++")
        if(EXISTS "${_glib_c_wrap}" AND EXISTS "${_glib_cpp_wrap}")
            # NDK 多架构包装器：内嵌 --target 与 --sysroot，编译最稳。
            # 注意：不能设置 c_ld/cpp_ld 为编译器包装器——meson 会把它当作
            # "GNU 链接器" 去探测，向 clang 传 --fix-cortex-a53-843419 等 GNU
            # 参数导致 linker detection 失败。链路目标由下方 c_link_args 强制。
            set(_glib_cc_line "c = ['${_glib_c_wrap}']\ncpp = ['${_glib_cpp_wrap}']")
        else()
            # 退路：通用 clang + 显式 target/sysroot/isystem
            set(_glib_cc_line "c = ['${_glib_bin}/clang', '--target=${_glib_target}', '--sysroot=${_glib_sysroot}', '-isystem', '${_glib_sysroot}/usr/include/aarch64-linux-android']\ncpp = ['${_glib_bin}/clang++', '--target=${_glib_target}', '--sysroot=${_glib_sysroot}', '-isystem', '${_glib_sysroot}/usr/include/aarch64-linux-android']")
        endif()
        # 关键：vcpkg 生成的交叉文件会在 c_link_args 里注入 --target=armv7...，
        # 覆盖链接器默认目标，导致已按 arm64 编译的 .o/.a 链接时仍按 armv7 报
        # "incompatible with armelf_linux_eabi"。这里覆盖 c_link_args，强制
        # 链接目标为 aarch64（wrapper 或显式参数都附带上正确的 target/sysroot）。
        set(_glib_link_args "c_link_args = ['--target=${_glib_target}', '--sysroot=${_glib_sysroot}']\ncpp_link_args = ['--target=${_glib_target}', '--sysroot=${_glib_sysroot}']")
        set(_glib_builtin_opts "c_args = ['-fPIC', '-g', '-DANDROID', '-D_FILE_OFFSET_BITS=64']\ncpp_args = ['-fPIC', '-g', '-DANDROID', '-D_FILE_OFFSET_BITS=64']\n${_glib_link_args}")
        if(NOT DEFINED VCPKG_BUILD_TYPE OR VCPKG_BUILD_TYPE STREQUAL "debug")
            set(_glib_cross_dbg "${CURRENT_BUILDTREES_DIR}/meson-cross-arm64-android-dbg.ini")
            file(WRITE "${_glib_cross_dbg}" "[binaries]\n${_glib_cc_line}\n\n[built-in options]\n${_glib_builtin_opts}\n")
            set(VCPKG_MESON_CROSS_FILE_DEBUG "${_glib_cross_dbg}")
        endif()
        if(NOT DEFINED VCPKG_BUILD_TYPE OR VCPKG_BUILD_TYPE STREQUAL "release")
            set(_glib_cross_rel "${CURRENT_BUILDTREES_DIR}/meson-cross-arm64-android-rel.ini")
            file(WRITE "${_glib_cross_rel}" "[binaries]\n${_glib_cc_line}\n\n[built-in options]\n${_glib_builtin_opts}\n")
            set(VCPKG_MESON_CROSS_FILE "${_glib_cross_rel}")
            set(VCPKG_MESON_CROSS_FILE_RELEASE "${_glib_cross_rel}")
        endif()
        message(STATUS "glib: android arm64 meson cross override -> ${_glib_cross_rel}")
    endif()
endif()

vcpkg_list(SET ADDITIONAL_BINARIES)
if(VCPKG_HOST_IS_WINDOWS)
    # Presence of bash and sh enables installation of auxiliary components.
    vcpkg_list(APPEND ADDITIONAL_BINARIES "bash = ['${CMAKE_COMMAND}', '-E', 'false']")
    vcpkg_list(APPEND ADDITIONAL_BINARIES "sh = ['${CMAKE_COMMAND}', '-E', 'false']")
endif()

vcpkg_configure_meson(
    SOURCE_PATH "${SOURCE_PATH}"
    LANGUAGES ${LANGUAGES}
    ADDITIONAL_BINARIES
        ${ADDITIONAL_BINARIES}
    OPTIONS
        ${OPTIONS}
        -Ddocumentation=false
        -Ddtrace=disabled
        -Dinstalled_tests=false
        -Dintrospection=disabled
        -Dlibelf=disabled
        -Dman-pages=disabled
        -Dsysprof=disabled
        -Dtests=false
        -Dxattr=false
)
vcpkg_install_meson(ADD_BIN_TO_PATH)
vcpkg_copy_pdbs()

file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/tools/${PORT}")
set(GLIB_SCRIPTS
    gdbus-codegen
    glib-genmarshal
    glib-gettextize
    glib-mkenums
    gtester-report
)
foreach(script IN LISTS GLIB_SCRIPTS)
    file(RENAME "${CURRENT_PACKAGES_DIR}/bin/${script}" "${CURRENT_PACKAGES_DIR}/tools/${PORT}/${script}")
    file(REMOVE "${CURRENT_PACKAGES_DIR}/debug/bin/${script}")
endforeach()

set(GLIB_TOOLS
    gapplication
    gdbus
    gi-compile-repository
    gi-decompile-typelib
    gi-inspect-typelib
    gio
    gio-querymodules
    glib-compile-resources
    glib-compile-schemas
    gobject-query
    gresource
    gsettings
    gtester
)
if(VCPKG_TARGET_IS_WINDOWS)
    list(REMOVE_ITEM GLIB_TOOLS gapplication gtester)
    if(VCPKG_TARGET_ARCHITECTURE MATCHES "x64|arm64")
        list(APPEND GLIB_TOOLS gspawn-win64-helper gspawn-win64-helper-console)
    elseif(VCPKG_TARGET_ARCHITECTURE STREQUAL "x86")
        list(APPEND GLIB_TOOLS gspawn-win32-helper gspawn-win32-helper-console)
    endif()
elseif(VCPKG_TARGET_IS_OSX)
    list(REMOVE_ITEM GLIB_TOOLS gapplication)
elseif(VCPKG_TARGET_IS_IOS)
    list(REMOVE_ITEM GLIB_TOOLS gapplication)
endif()
vcpkg_copy_tools(TOOL_NAMES ${GLIB_TOOLS} AUTO_CLEAN)

vcpkg_fixup_pkgconfig()

if(VCPKG_TARGET_IS_WINDOWS)
    set(LIBINTL_NAME "intl.lib")
else()
    set(LIBINTL_NAME "libintl")
    if(VCPKG_LIBRARY_LINKAGE STREQUAL dynamic)
        string(APPEND LIBINTL_NAME "${VCPKG_TARGET_SHARED_LIBRARY_SUFFIX}")
    else()
        string(APPEND LIBINTL_NAME "${VCPKG_TARGET_STATIC_LIBRARY_SUFFIX}")
    endif()
endif()

set(pc_replace_intl_path gio glib gmodule-no-export gobject gthread)
foreach(pc_prefix IN LISTS pc_replace_intl_path)
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/lib/pkgconfig/${pc_prefix}-2.0.pc" "\"" "")
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/lib/pkgconfig/${pc_prefix}-2.0.pc" "\${prefix}/debug/lib/${LIBINTL_NAME}" "-lintl" IGNORE_UNCHANGED)
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/lib/pkgconfig/${pc_prefix}-2.0.pc" "\${prefix}/lib/${LIBINTL_NAME}" "-lintl" IGNORE_UNCHANGED)
    if(NOT VCPKG_BUILD_TYPE)
        vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/debug/lib/pkgconfig/${pc_prefix}-2.0.pc" "\"" "")
        vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/debug/lib/pkgconfig/${pc_prefix}-2.0.pc" "\${prefix}/lib/${LIBINTL_NAME}" "-lintl" IGNORE_UNCHANGED)
    endif()
endforeach()

vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/lib/pkgconfig/gio-2.0.pc" "\${bindir}" "\${prefix}/tools/${PORT}")
vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/lib/pkgconfig/glib-2.0.pc" "\${bindir}" "\${prefix}/tools/${PORT}")
if(NOT VCPKG_BUILD_TYPE)
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/debug/lib/pkgconfig/gio-2.0.pc" "\${bindir}" "\${prefix}/../tools/${PORT}")
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/debug/lib/pkgconfig/glib-2.0.pc" "\${bindir}" "\${prefix}/../tools/${PORT}")
endif()

# Fix python scripts
set(_file "${CURRENT_PACKAGES_DIR}/tools/${PORT}/gdbus-codegen")
file(READ "${_file}" _contents)
string(REPLACE "elif os.path.basename(filedir) == 'bin':" "elif os.path.basename(filedir) == 'tools':" _contents "${_contents}")
string(REPLACE "path = os.path.join(filedir, '..', 'share', 'glib-2.0')" "path = os.path.join(filedir, '../..', 'share', 'glib-2.0')" _contents "${_contents}")
string(REPLACE "path = os.path.join(filedir, '..')" "path = os.path.join(filedir, '../../share/glib-2.0')" _contents "${_contents}")
string(REPLACE "path = os.path.join('${CURRENT_PACKAGES_DIR}/share', 'glib-2.0')" "path = os.path.join('unuseable/share', 'glib-2.0')" _contents "${_contents}")
file(WRITE "${_file}" "${_contents}")

if(EXISTS "${CURRENT_PACKAGES_DIR}/tools/${PORT}/glib-gettextize")
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/tools/${PORT}/glib-gettextize" "${CURRENT_PACKAGES_DIR}" "`dirname $0`/../..")
endif()

file(REMOVE_RECURSE
    "${CURRENT_PACKAGES_DIR}/debug/include"
    "${CURRENT_PACKAGES_DIR}/debug/share"
    "${CURRENT_PACKAGES_DIR}/share/gdb"
    "${CURRENT_PACKAGES_DIR}/debug/lib/gio"
    "${CURRENT_PACKAGES_DIR}/lib/gio"
)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSES/LGPL-2.1-or-later.txt")
