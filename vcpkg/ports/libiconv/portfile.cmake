# Overlay libiconv 端口（照搬 vcpkg 上游 1.19，Android 分支改为强制 aarch64）。
#
# 背景：vcpkg 原厂 libiconv 在 Android(API<28) 用 vcpkg_make(autotools) 构建，
# 编译器/CFLAGS 取自 get_cmake_vars，而 get_vars 会把目标错推到
# `--target=armv7-none-linux-androideabi21`，于是在 arm64-android 上产出 32 位
# libiconv.a，与 arm64 的 glib 链接时报 "incompatible with aarch64linux"。
#
# 解法（与 overlay libffi 一致）：仅 Android 分支改用 NDK `aarch64-linux-android<api>-clang`
# 工具链包装器直接走 autotools，configure 命令行显式传 CC/AR/CFLAGS（行内变量优先于
# vcpkg-make 注错的 env），得到正确的 arm64 归档。非 Android 走原厂 make 流程。

vcpkg_download_distfile(ARCHIVE
    URLS "https://ftp.gnu.org/gnu/libiconv/libiconv-${VERSION}.tar.gz"
         "https://www.mirrorservice.org/sites/ftp.gnu.org/gnu/libiconv/libiconv-${VERSION}.tar.gz"
    FILENAME "libiconv-${VERSION}.tar.gz"
    SHA512 a55eb3b7b785a78ab8918db8af541c9e11deb5ff4f89d54483287711ed797d87848ce0eafffa7ce26d9a7adb4b5a9891cb484f94bd4f51d3ce97a6a47b4c719a
    SOURCE_BASE "v${VERSION}"
)
vcpkg_extract_source_archive(SOURCE_PATH
    ARCHIVE "${ARCHIVE}"
    SOURCE_BASE "v${VERSION}"
)
# 注：上游 portfile 的 3 个 MSVC 补丁（Config-for-MSVC/Add-export/ModuleFileName）
# 本项目不构建 Windows，overlay 未随附这些补丁文件，故不引用。

if(VCPKG_TARGET_IS_ANDROID)
    ############################################
    # Android：NDK aarch64 autotools 直接构建  #
    ############################################
    if(DEFINED VCPKG_ANDROID_NDK)
        set(_ndk "${VCPKG_ANDROID_NDK}")
    elseif(DEFINED ENV{ANDROID_NDK_HOME})
        set(_ndk "$ENV{ANDROID_NDK_HOME}")
    else()
        message(FATAL_ERROR "libiconv(android): 未设置 ANDROID_NDK_HOME / VCPKG_ANDROID_NDK")
    endif()

    file(GLOB _prebuilt_dir_list DIRECTORIES "${_ndk}/toolchains/llvm/prebuilt/*")
    if(NOT _prebuilt_dir_list)
        message(FATAL_ERROR "libiconv(android): 在 ${_ndk}/toolchains/llvm/prebuilt 下找不到工具链目录")
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

    # 分别构建 debug/release 两份归档（autotools out-of-tree），避免 post-build 校验误报。
    set(_configs rel dbg)
    foreach(_cfg IN LISTS _configs)
        if(_cfg STREQUAL "rel")
            set(_build_dir "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")
            set(_prefix   "${CURRENT_PACKAGES_DIR}")
            set(_cflags   "-fPIC -O3")
        else()
            set(_build_dir "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-dbg")
            set(_prefix   "${CURRENT_BUILDTREES_DIR}/dbg-stage")
            set(_cflags   "-fPIC -g")
        endif()
        file(MAKE_DIRECTORY "${_build_dir}")

        vcpkg_execute_build_process(
            COMMAND "${SOURCE_PATH}/configure"
                --host=${_triple}
                --prefix=${_prefix}
                --libdir=${_prefix}/lib
                --disable-shared
                --enable-static
                --enable-extra-encodings
                --without-libiconv-prefix
                --without-libintl-prefix
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
    if(EXISTS "${CURRENT_BUILDTREES_DIR}/dbg-stage/lib/libiconv.a")
        file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/debug/lib")
        file(COPY "${CURRENT_BUILDTREES_DIR}/dbg-stage/lib/libiconv.a"
                   DESTINATION "${CURRENT_PACKAGES_DIR}/debug/lib")
    endif()
    if(EXISTS "${CURRENT_BUILDTREES_DIR}/dbg-stage/lib/libcharset.a")
        file(COPY "${CURRENT_BUILDTREES_DIR}/dbg-stage/lib/libcharset.a"
                   DESTINATION "${CURRENT_PACKAGES_DIR}/debug/lib")
    endif()

    # 移除 libtool 归档与 iconv CLI（GPL 工具非引擎所需，且易触发 post-build 校验）
    file(GLOB_RECURSE _la_files "${CURRENT_PACKAGES_DIR}/**/*.la")
    if(_la_files)
        file(REMOVE ${_la_files})
    endif()
    file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/bin" "${CURRENT_PACKAGES_DIR}/debug/bin")

    set(VCPKG_POLICY_ALLOW_RESTRICTED_HEADERS enabled)
    file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")
    file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/share/${PORT}")
    vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING.LIB" "${SOURCE_PATH}/COPYING")
else()
    ############################################
    # 非 Android：照搬原厂 make 流程           #
    ############################################
    vcpkg_list(SET OPTIONS)
    if (NOT VCPKG_TARGET_IS_ANDROID)
        vcpkg_list(APPEND OPTIONS --enable-relocatable)
    endif()
    vcpkg_make_configure(
        SOURCE_PATH "${SOURCE_PATH}"
        OPTIONS
            --enable-extra-encodings
            --without-libiconv-prefix
            --without-libintl-prefix
            ${OPTIONS}
    )
    vcpkg_make_install()

    vcpkg_copy_pdbs()
    vcpkg_copy_tool_dependencies("${CURRENT_PACKAGES_DIR}/tools/${PORT}/bin")
    vcpkg_copy_tool_dependencies("${CURRENT_PACKAGES_DIR}/tools/${PORT}/debug/bin")

    set(VCPKG_POLICY_ALLOW_RESTRICTED_HEADERS enabled)
    file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")
    file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/share/${PORT}")
    vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING.LIB" "${SOURCE_PATH}/COPYING")
endif()