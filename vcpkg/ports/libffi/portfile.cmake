# Overlay libffi 端口。
#
# 背景：vcpkg 原厂 libffi 用 vcpkg_make（autotools）构建。在 arm64-android 上，
# vcpkg-make 把编译器目标错误推导成 `-target armv7-none-linux-androideabi21`
# （armv7-32 + API21），却去编译 libffi 的 AArch64 后端（src/aarch64/sysv.S 等），
# 导致汇编失败、BUILD_FAILED。该问题与 NDK 版本无关（NDK 27/29 均复现），
# 上游 vcpkg 亦未修复（libffi 无 CMake/Meson 工程，无法简单切换构建系统）。
#
# 本 overlay 解法：
#   - 非 Android：完全沿用原厂 make 流程（vcpkg_make_configure/install），不引入回归。
#   - Android：改用 NDK 的 `aarch64-linux-android<api>-clang` 工具链包装器，
#     在 autotools `./configure` 命令行显式传入 CC/CXX/AR/AS 等（configure 命令行李
#     优先于环境变量，可压下 vcpkg-make 注错的 CC），从而以正确的 aarch64 目标完成构建。

vcpkg_download_distfile(ARCHIVE
    URLS "https://github.com/libffi/libffi/releases/download/v${VERSION}/libffi-${VERSION}.tar.gz"
    FILENAME "libffi-${VERSION}.tar.gz"
    SHA512 76974a84e3aee6bbd646a6da2e641825ae0b791ca6efdc479b2d4cbcd3ad607df59cffcf5031ad5bd30822961a8c6de164ac8ae379d1804acd388b1975cdbf4d
)
vcpkg_extract_source_archive(
    SOURCE_PATH
    ARCHIVE "${ARCHIVE}"
    PATCHES
        dll-bindir.diff
)

if(VCPKG_TARGET_IS_ANDROID)
    ############################################
    # Android：NDK aarch64 autotools 直接构建  #
    ############################################

    if(DEFINED VCPKG_ANDROID_NDK)
        set(_ndk "${VCPKG_ANDROID_NDK}")
    elseif(DEFINED ENV{ANDROID_NDK_HOME})
        set(_ndk "$ENV{ANDROID_NDK_HOME}")
    else()
        message(FATAL_ERROR "libffi(android): 未设置 ANDROID_NDK_HOME / VCPKG_ANDROID_NDK")
    endif()

    file(GLOB _prebuilt_dir_list DIRECTORIES "${_ndk}/toolchains/llvm/prebuilt/*")
    if(NOT _prebuilt_dir_list)
        message(FATAL_ERROR "libffi(android): 在 ${_ndk}/toolchains/llvm/prebuilt 下找不到工具链目录")
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
    set(_strip    "${_bin}/llvm-strip")
    set(_sysroot  "${_prebuilt_dir}/sysroot")

    # 分别构建 debug/release 两份归档（autotools out-of-tree），避免
    # vcpkg post-build 对“debug/release 二进制相同”或“debug 下含头文件”的校验误报。
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

        # configure 命令行显式传工具 + CFLAGS，覆盖 vcpkg-make 注错的 CC（行内变量优先于 env）
        vcpkg_execute_build_process(
            COMMAND "${SOURCE_PATH}/configure"
                --host=${_triple}
                --prefix=${_prefix}
                --disable-docs
                --disable-multi-os-directory
                --enable-portable-binary
                CC=${_cc}
                CXX=${_cxx}
                AR=${_ar}
                RANLIB=${_ranlib}
                NM=${_nm}
                CCAS=${_cc}
                CFLAGS=${_cflags}
                CCASFLAGS=-fPIC
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

    # 把 debug 归档从临时 stage 拷到 debug/lib（debug 阶段未把头文件装入 debug/ 以规避校验）
    if(EXISTS "${CURRENT_BUILDTREES_DIR}/dbg-stage/lib/libffi.a" AND
       EXISTS "${CURRENT_PACKAGES_DIR}/lib/libffi.a")
        file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/debug/lib")
        file(COPY "${CURRENT_BUILDTREES_DIR}/dbg-stage/lib/libffi.a"
                   DESTINATION "${CURRENT_PACKAGES_DIR}/debug/lib")
    endif()

    # 移除 libtool 归档(.la)，否则 vcpkg post-build 校验会报错
    file(GLOB_RECURSE _la_files "${CURRENT_PACKAGES_DIR}/**/*.la")
    if(_la_files)
        file(REMOVE ${_la_files})
    endif()

    vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
else()
    ############################################
    # 非 Android：照搬原厂 make 流程（见上游） #
    ############################################
    vcpkg_list(SET options)
    if(VCPKG_TARGET_IS_WINDOWS)
        set(linkage_flag "-DFFI_STATIC_BUILD")
        if(VCPKG_LIBRARY_LINKAGE STREQUAL "dynamic")
            set(linkage_flag "-DFFI_BUILDING_DLL")
        endif()
        vcpkg_list(APPEND options "CFLAGS=\${CFLAGS} ${linkage_flag}")
    endif()
    vcpkg_cmake_get_vars(cmake_vars_file ADDITIONAL_LANGUAGES ASM)
    include("${cmake_vars_file}")
    if(VCPKG_DETECTED_CMAKE_C_COMPILER_ID STREQUAL "MSVC")
        vcpkg_add_to_path("${SOURCE_PATH}")
        vcpkg_list(APPEND options "CCAS=msvcc.sh")
        set(ccas_options "")
        if(VCPKG_TARGET_ARCHITECTURE STREQUAL "x86")
            string(APPEND ccas_options " -m32")
        elseif(VCPKG_TARGET_ARCHITECTURE STREQUAL "x64")
            string(APPEND ccas_options " -m64")
        elseif(VCPKG_TARGET_ARCHITECTURE STREQUAL "arm")
            string(APPEND ccas_options " -marm")
        elseif(VCPKG_TARGET_ARCHITECTURE STREQUAL "arm64")
            string(APPEND ccas_options " -marm64")
        endif()
        if(ccas_options)
            vcpkg_list(APPEND options "CCASFLAGS=\${CCASFLAGS}${ccas_options}")
        endif()
    endif()
    vcpkg_make_configure(
        SOURCE_PATH "${SOURCE_PATH}"
        LANGUAGES C CXX ASM
        OPTIONS
            --enable-portable-binary
            --disable-docs
            --disable-multi-os-directory
            ${options}
    )
    vcpkg_make_install()
    vcpkg_copy_pdbs()
    vcpkg_fixup_pkgconfig()
    if(VCPKG_LIBRARY_LINKAGE STREQUAL "static")
        vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/include/ffi.h" "defined(FFI_STATIC_BUILD)" "1")
    endif()
    file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
    file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/unofficial-libffi-config.cmake" DESTINATION "${CURRENT_PACKAGES_DIR}/share/unofficial-libffi")
    file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/libffiConfig.cmake" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
    file(REMOVE_RECURSE
        "${CURRENT_PACKAGES_DIR}/debug/share"
        "${CURRENT_PACKAGES_DIR}/share/man3"
    )
    vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
endif()