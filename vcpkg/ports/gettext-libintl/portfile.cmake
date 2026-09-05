# Overlay gettext-libintl 端口（照搬 vcpkg 上游，Android arm64 分支改为强制 aarch64）。
#
# 背景：vcpkg 原厂 gettext-libintl 在 arm64-android 上同样踩 get_cmake_vars 把目标
# 错推成 `--target=armv7-none-linux-androideabi21` 的坑，产出 32 位 libintl.a；
# glib 等链接它时（即便 NLS 关闭仍残留 -lintl 到链接命令）报
#   ld.lld: error: .../libintl.a(...) is incompatible with aarch64linux
# 解法（与 overlay libiconv/libffi 一致）：仅 Android arm64 分支改用 NDK
# `aarch64-linux-android<api>-clang` 工具链直接走 autotools 构建
# `gettext-runtime/intl`，configure 命令行显式传 CC/AR/CFLAGS（行内变量优先于
# vcpkg-make 注错的 env），得到正确的 arm64 libintl.a。非 Android 走原厂 make 流程。
if(VCPKG_TARGET_IS_LINUX AND NOT X_VCPKG_FORCE_VCPKG_GETTEXT_LIBINTL)
    set(detection_results "${CURRENT_BUILDTREES_DIR}/detected-intl-${TARGET_TRIPLET}.cmake.log")
    file(REMOVE "${detection_results}")
    block(SCOPE_FOR VARIABLES)
        set(VCPKG_BUILD_TYPE release)
        vcpkg_cmake_configure(SOURCE_PATH "${CURRENT_PORT_DIR}/detect" OPTIONS "-DOUTFILE=${detection_results}")
    endblock()
    include("${detection_results}")
    message(STATUS "libintl header: ${VCPKG_DETECTED_LIBINTL_H}")
    if(NOT VCPKG_DETECTED_LIBINTL_H)
        message(FATAL_ERROR
            "When targeting Linux, `libintl.h` is expected to come from a system package. "
            "Please use the following commands or the equivalent to install development files.\n"
            "On Debian and Ubuntu derivatives: \"sudo apt-get install libc-dev\"\n"
            "On Alpine: \"apk add gettext-dev\"\n"
        )
    endif()

    set(VCPKG_POLICY_EMPTY_PACKAGE enabled)
    file(COPY "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
    return()
endif()

set(VCPKG_POLICY_ALLOW_RESTRICTED_HEADERS enabled)

vcpkg_download_distfile(ARCHIVE
    URLS "https://ftp.gnu.org/pub/gnu/gettext/gettext-${VERSION}.tar.gz"
         "https://www.mirrorservice.org/sites/ftp.gnu.org/gnu/gettext/gettext-${VERSION}.tar.gz"
    FILENAME "gettext-${VERSION}.tar.gz"
    SHA512 d8b22d7fba10052a2045f477f0a5b684d932513bdb3b295c22fbd9dfc2a9d8fccd9aefd90692136c62897149aa2f7d1145ce6618aa1f0be787cb88eba5bc09be
)

vcpkg_extract_source_archive(SOURCE_PATH
    ARCHIVE "${ARCHIVE}"
    PATCHES
        uwp.patch
        0003-Fix-win-unicode-paths.patch
)

if(VCPKG_TARGET_IS_ANDROID AND VCPKG_TARGET_ARCHITECTURE STREQUAL "arm64")
    ############################################
    # Android arm64：NDK aarch64 autotools 直构 gettext-runtime/intl
    ############################################
    if(DEFINED VCPKG_ANDROID_NDK)
        set(_ndk "${VCPKG_ANDROID_NDK}")
    elseif(DEFINED ENV{ANDROID_NDK_HOME})
        set(_ndk "$ENV{ANDROID_NDK_HOME}")
    else()
        message(FATAL_ERROR "gettext-libintl(android): 未设置 ANDROID_NDK_HOME / VCPKG_ANDROID_NDK")
    endif()

    file(GLOB _prebuilt_dir_list DIRECTORIES "${_ndk}/toolchains/llvm/prebuilt/*")
    if(NOT _prebuilt_dir_list)
        message(FATAL_ERROR "gettext-libintl(android): 在 ${_ndk}/toolchains/llvm/prebuilt 下找不到工具链目录")
    endif()
    list(GET _prebuilt_dir_list 0 _prebuilt_dir)
    set(_bin      "${_prebuilt_dir}/bin")
    set(_api      "${VCPKG_ANDROID_PLATFORM}")
    if(NOT _api)
        set(_api "24")
    endif()
    set(_triple   "aarch64-linux-android")
    set(_cc       "${_bin}/${_triple}${_api}-clang")
    set(_cxx      "${_bin}/${_triple}${_api}-clang++")
    set(_ar       "${_bin}/llvm-ar")
    set(_ranlib   "${_bin}/llvm-ranlib")
    set(_nm       "${_bin}/llvm-nm")

    set(_intl_common
        --host=${_triple}
        --disable-shared
        --enable-static
        --disable-dependency-tracking
        --with-included-gettext
        --without-libintl-prefix
        ac_cv_path_GMSGFMT=false
        ac_cv_path_MSGFMT=false
        ac_cv_path_MSGMERGE=false
        ac_cv_path_XGETTEXT=false
        ac_cv_prog_INTLBISON=false
    )

    # 分别构建 debug/release 两份归档（autotools out-of-tree），避免 post-build 校验误报
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
            COMMAND "${SOURCE_PATH}/gettext-runtime/intl/configure"
                ${_intl_common}
                --prefix=${_prefix}
                CC=${_cc}
                CXX=${_cxx}
                AR=${_ar}
                RANLIB=${_ranlib}
                NM=${_nm}
                CFLAGS=${_cflags}
            WORKING_DIRECTORY "${_build_dir}"
            LOGNAME "config-${_cfg}-${TARGET_TRIPLET}"
        )
        # 修正 autotools VPATH 构建：intl 的 Makefile 令 bindtextdom.lo 等依赖
        # `../config.h`（构建目录上一级），而 out-of-tree 下 config.h 实际在位生成于
        # 构建目录根。vcpkg 原厂也是用同样替换解决（见非 Android 分支的 Makefile 修正）。
        file(GLOB _intl_mk "${_build_dir}/Makefile" "${_build_dir}/intl/Makefile")
        foreach(_mf IN LISTS _intl_mk)
            file(READ "${_mf}" _mk_rules)
            string(REPLACE "  ../config.h" "  config.h" _mk_rules "${_mk_rules}")
            file(WRITE "${_mf}" "${_mk_rules}")
        endforeach()
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
    if(EXISTS "${CURRENT_BUILDTREES_DIR}/dbg-stage/lib/libintl.a")
        file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/debug/lib")
        file(COPY "${CURRENT_BUILDTREES_DIR}/dbg-stage/lib/libintl.a"
                   DESTINATION "${CURRENT_PACKAGES_DIR}/debug/lib")
    endif()

    # 移除 libtool 归档与二进制工具（非库所需，且易触发 post-build 校验）
    file(GLOB_RECURSE _la_files "${CURRENT_PACKAGES_DIR}/**/*.la")
    if(_la_files)
        file(REMOVE ${_la_files})
    endif()
    file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/bin" "${CURRENT_PACKAGES_DIR}/debug/bin")
    file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")

    file(COPY "${CMAKE_CURRENT_LIST_DIR}/vcpkg-cmake-wrapper.cmake" DESTINATION "${CURRENT_PACKAGES_DIR}/share/intl")
    file(COPY "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
    vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/gettext-runtime/intl/COPYING.LIB")
    return()
endif()

# ---------------------------------------------------------------------------
# 非 Android arm64：完全沿用原厂流程（保持其它平台行为不变）
# ---------------------------------------------------------------------------
if(VCPKG_HOST_IS_WINDOWS)
    message(STATUS "Modifying 'configure' to use fast bash variable expansion")
    set(ENV{CONFIG_SHELL} "/usr/bin/bash")
    vcpkg_execute_required_process(
        COMMAND "${CMAKE_COMMAND}"
            "-DSOURCE_DIRS=gettext-runtime"
            -P "${CMAKE_CURRENT_LIST_DIR}/bashify.cmake"
        WORKING_DIRECTORY "${SOURCE_PATH}"
        LOGNAME "bashify-${TARGET_TRIPLET}"
    )
endif()

set(OPTIONS
    --no-recursion
    --enable-relocatable #symbol duplication with glib-init.c?
    --with-included-gettext
    --without-libintl-prefix
    --disable-dependency-tracking
    ac_cv_path_GMSGFMT=false
    ac_cv_path_MSGFMT=false
    ac_cv_path_MSGMERGE=false
    ac_cv_path_XGETTEXT=false
    ac_cv_prog_INTLBISON=false
)
if(VCPKG_TARGET_IS_WINDOWS)
    list(APPEND OPTIONS
        am_cv_func_iconv_works=yes
        ac_cv_func_wcslen=yes
        ac_cv_func_memmove=yes
        gl_cv_func_printf_directive_n=no
    )
    if(NOT VCPKG_TARGET_IS_MINGW)
        list(APPEND OPTIONS
            ac_cv_header_getopt_h=no
            ac_cv_header_pthread_h=no
            ac_cv_func_snprintf=no
            gl_cv_func_mbrtowc_empty_input=no
            gt_cv_int_divbyzero_sigfpe=no
        )
    endif()
endif()

file(REMOVE "${CURRENT_BUILDTREES_DIR}/config.cache-${TARGET_TRIPLET}-rel.log")
file(REMOVE "${CURRENT_BUILDTREES_DIR}/config.cache-${TARGET_TRIPLET}-dbg.log")
vcpkg_make_configure(
    SOURCE_PATH "${SOURCE_PATH}/gettext-runtime/intl"
    OPTIONS
        ${OPTIONS}
    OPTIONS_RELEASE
        "--cache-file=${CURRENT_BUILDTREES_DIR}/config.cache-${TARGET_TRIPLET}-rel.log"
    OPTIONS_DEBUG
        "--cache-file=${CURRENT_BUILDTREES_DIR}/config.cache-${TARGET_TRIPLET}-dbg.log"
    )

file(GLOB_RECURSE makefiles "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}*/Makefile")
foreach(file IN LISTS makefiles)
    file(READ "${file}" rules)
    string(REGEX REPLACE "(\n\ttest -d [^ ]* [|][|] [\$][(]MKDIR_P[)][^\n;]*)(\n\t)" "\\1 || exit 1 ; \\\\\\2" rules "${rules}")
    string(REGEX REPLACE "(\n\t){ echo '/[*] [^*]* [*]/'; \\\\\n\t  cat ([^;\n]*); \\\\\n\t[}] > [\$]@-t\n\tmv -f [\$]@-t ([\$]@\n)" "\\1cp \\2 \\3" rules "${rules}")
    string(REGEX REPLACE " > [\$]@-t\n\t[\$][(]AM_V_at[)]mv [\$]@-t ([\$]@\n)" "> \\1" rules "${rules}")
    string(REGEX REPLACE "([\$}[(]COMPILE[)] -c -o [\$]@) `[\$][(]CYGPATH_W[)] '[\$]<'`" "\\1 \$<" rules "${rules}")
    string(REPLACE "  ../config.h" "  config.h" rules "${rules}")
    file(WRITE "${file}" "${rules}")
endforeach()

vcpkg_make_install()
vcpkg_copy_pdbs()

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")

file(COPY "${CMAKE_CURRENT_LIST_DIR}/vcpkg-cmake-wrapper.cmake" DESTINATION "${CURRENT_PACKAGES_DIR}/share/intl")
file(COPY "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/gettext-runtime/intl/COPYING.LIB")