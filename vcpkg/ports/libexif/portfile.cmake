# Overlay libexif 端口（照搬 vcpkg 上游 baseline b1e15ef，Android 分支改为强制 aarch64）。
#
# 背景：与 overlay libiconv 同根因——libexif 走 vcpkg_make(autotools)，编译器/CFLAGS
# 取自 get_cmake_vars，而 get_vars 在 arm64-android 上会把目标错推到
# `--target=armv7-none-linux-androideabi21`，于是产出 32 位 libexif.a，与 arm64 的
# cairo 等链接时报 "incompatible with aarch64linux"。
#
# 解法（与 overlay libiconv 一致）：仅 Android 分支改用 NDK `aarch64-linux-android<api>-clang`
# 工具链包装器直接走 autotools，configure 命令行显式传 CC/AR/CFLAGS（行内变量优先于
# vcpkg-make 注错的 env），得到正确的 arm64 归档。libexif 从 GitHub 拉 git 快照（不含
# 生成的 configure），故先 vcpkg_find_acquire_program 取 autoconf/automake/libtool 并
# 跑 autoreconf。非 Android 走原厂 make 流程。

vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO libexif/libexif
    REF "v${VERSION}"
    SHA512 6e50134eab2fcf93036ecf8a9a9f89273ab8ddc4a171523f1f88f6d90bda799ef8f6a597c1c308fe8153dcc685a2d2b473e758e2286ce4d3143dd829e07a8c80
    HEAD_REF master
    PATCHES
        fix-ssize.patch
)

vcpkg_list(SET options)
if("nls" IN_LIST FEATURES)
    vcpkg_list(APPEND options "--enable-nls")
else()
    vcpkg_list(APPEND options "--disable-nls")
endif()

if(VCPKG_TARGET_IS_ANDROID)
    ############################################
    # Android：NDK aarch64 autotools 直接构建  #
    ############################################
    if(DEFINED VCPKG_ANDROID_NDK)
        set(_ndk "${VCPKG_ANDROID_NDK}")
    elseif(DEFINED ENV{ANDROID_NDK_HOME})
        set(_ndk "$ENV{ANDROID_NDK_HOME}")
    else()
        message(FATAL_ERROR "libexif(android): 未设置 ANDROID_NDK_HOME / VCPKG_ANDROID_NDK")
    endif()

    file(GLOB _prebuilt_dir_list DIRECTORIES "${_ndk}/toolchains/llvm/prebuilt/*")
    if(NOT _prebuilt_dir_list)
        message(FATAL_ERROR "libexif(android): 在 ${_ndk}/toolchains/llvm/prebuilt 下找不到工具链目录")
    endif()
    list(GET _prebuilt_dir_list 0 _prebuilt_dir)
    set(_bin      "${_prebuilt_dir}/bin")
    set(_api      "${VCPKG_ANDROID_PLATFORM}")
    set(_triple   "aarch64-linux-android")
    set(_cc       "${_bin}/${_triple}${_api}-clang")
    set(_cxx      "${_bin}/${_triple}${_api}-clang++")
    set(_ar       "${_bin}/llvm-ar")
    set(_ranlib   "${_bin}/llvm-ranlib")
    set(_nm       "${_bin}/llvm-nm")

    # libexif 从 git 快照构建（github 归档不含生成的 configure），需用 autotools 先
    # autoreconf 生成 configure。vcpkg_find_acquire_program 不认识 AUTOCONF/AUTOMAKE/
    # LIBTOOL 这类 tool 名（官方 vcpkg_configure_make 的 AUTOCONFIG 也是
    # find_program(AUTORECONF autoreconf) 并依赖系统 autotools），故这里同样依赖
    # 宿主系统已装的 autoreconf（android workflow 已 apt 安装 autoconf/automake/libtool；
    # iOS/macOS workflow 已 brew 安装）。gettext 的 autopoint 与 m4 由 host 依赖提供，
    # 通过 PATH / ACLOCAL_PATH 注入，供 AM_GNU_GETTEXT 使用。
    find_program(_libexif_autoreconf autoreconf)
    if(NOT _libexif_autoreconf)
        message(FATAL_ERROR "libexif(android): 找不到 autoreconf，请安装 autoconf/automake/libtool")
    endif()
    list(PREPEND ENV{PATH} "${CURRENT_HOST_INSTALLED_DIR}/bin")
    list(PREPEND ENV{ACLOCAL_PATH} "${CURRENT_HOST_INSTALLED_DIR}/share/aclocal")

    vcpkg_execute_build_process(
        COMMAND "${_libexif_autoreconf}" -i -f
        WORKING_DIRECTORY "${SOURCE_PATH}"
        LOGNAME "autoreconf-${TARGET_TRIPLET}"
    )

    # 分别构建 debug/release 两份归档（autotools out-of-tree），避免 post-build 校验误报。
    set(_configs rel dbg)
    foreach(_cfg IN LISTS _configs)
        if(_cfg STREQUAL "rel")
            set(_build_dir "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")
            set(_prefix   "${CURRENT_PACKAGES_DIR}")
            set(_cflags   "-fPIC -O3 -DANDROID -D_FILE_OFFSET_BITS=64")
        else()
            set(_build_dir "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-dbg")
            set(_prefix   "${CURRENT_BUILDTREES_DIR}/dbg-stage")
            set(_cflags   "-fPIC -g -DANDROID -D_FILE_OFFSET_BITS=64")
        endif()
        file(MAKE_DIRECTORY "${_build_dir}")

        vcpkg_execute_build_process(
            COMMAND "${SOURCE_PATH}/configure"
                --host=${_triple}
                --prefix=${_prefix}
                --libdir=${_prefix}/lib
                --disable-shared
                --enable-static
                --enable-internal-docs=no
                --enable-ship-binaries=no
                ${options}
                CC=${_cc}
                CXX=${_cxx}
                AR=${_ar}
                RANLIB=${_ranlib}
                NM=${_nm}
                CFLAGS=${_cflags}
            WORKING_DIRECTORY "${_build_dir}"
            LOGNAME "config-${_cfg}-${TARGET_TRIPLET}"
        )

        vcpkg_execute_build_process(
            COMMAND make -j ${VCPKG_CONCURRENCY}
            WORKING_DIRECTORY "${_build_dir}"
            LOGNAME "build-${_cfg}-${TARGET_TRIPLET}"
        )

        vcpkg_execute_build_process(
            COMMAND make install
            WORKING_DIRECTORY "${_build_dir}"
            LOGNAME "install-${_cfg}-${TARGET_TRIPLET}"
        )
    endforeach()

    # 把 debug 归档从临时 stage 拷到 debug/lib
    if(EXISTS "${CURRENT_BUILDTREES_DIR}/dbg-stage/lib/libexif.a")
        file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/debug/lib")
        file(COPY "${CURRENT_BUILDTREES_DIR}/dbg-stage/lib/libexif.a"
                   DESTINATION "${CURRENT_PACKAGES_DIR}/debug/lib")
    endif()

    # 移除 libtool 归档与 CLI 工具（非引擎所需，且易触发 post-build 校验）
    file(GLOB_RECURSE _la_files "${CURRENT_PACKAGES_DIR}/**/*.la")
    if(_la_files)
        file(REMOVE ${_la_files})
    endif()
    file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/bin" "${CURRENT_PACKAGES_DIR}/debug/bin")

    file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/unofficial-libexif-config.cmake" DESTINATION "${CURRENT_PACKAGES_DIR}/share/unofficial-${PORT}")
    file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")
    vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
else()
    ############################################
    # 非 Android：照搬原厂 make 流程           #
    ############################################
    vcpkg_configure_make(
        SOURCE_PATH "${SOURCE_PATH}"
        AUTOCONFIG
        OPTIONS
            ${options}
            --enable-internal-docs=no
            --enable-ship-binaries=no
    )

    vcpkg_install_make()
    vcpkg_fixup_pkgconfig()

    file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/unofficial-libexif-config.cmake" DESTINATION "${CURRENT_PACKAGES_DIR}/share/unofficial-${PORT}")
    file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")

    vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
endif()