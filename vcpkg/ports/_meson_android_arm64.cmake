# 共享模块：Android arm64 下修复 vcpkg meson 交叉编译被错推为 armv7。
#
# 背景：vcpkg 的 meson 交叉编译在 Android 上存在缺陷——vcpkg_configure_meson 所用的
# 交叉文件编译参数取自 get_cmake_vars（z_vcpkg_get_cmake_vars + _vcpkg_adjust_flags），
# 该流程无论 triplet 是否设置 ANDROID_ABI=arm64-v8a，都会回落 NDK 默认的
# `--target=armv7-none-linux-androideabi21`（armv7/API21）并把它写进交叉文件的
# c_link_args/cpp_link_args。结果本应按 arm64 编译的 meson 端口（glib/fontconfig/
# cairo/pixman 等）全部按 32 位 ARM 编译、链接；而 libffi/pcre2/cmake 型端口都正确
# 产出 arm64 静态库，链接时报：
#   ld.lld: error: .../libiconv.a(...) is incompatible with armelf_linux_eabi
#   ld.lld: error: undefined symbol: libiconv_open
#
# 修复原理：在 vcpkg 生成的交叉文件之后追加一个补充 meson 交叉文件
# （VCPKG_MESON_CROSS_FILE / _DEBUG / _RELEASE）。meson 对后出现的交叉文件取覆盖
# 优先级：我们覆盖 [binaries] c/cpp 为 NDK 的 aarch64 编译器包装器（内嵌 target+
# sysroot），并覆盖 c_link_args/cpp_link_args 去掉错误的 --target=armv7、强制 aarch64。
# 其余二进制/属性/host_machine 仍复用 vcpkg 生成的交叉文件。
#
# 调用方式：meson 型 overlay 端口在 vcpkg_configure_meson 之前 `include(.../../_meson_android_arm64.cmake)`。
# 仅当 VCPKG_TARGET_IS_ANDROID 且架构为 arm64 时生效；其余平台无副作用。

if(VCPKG_TARGET_IS_ANDROID AND VCPKG_TARGET_ARCHITECTURE STREQUAL "arm64")
    if(DEFINED ENV{ANDROID_NDK_HOME} AND EXISTS "$ENV{ANDROID_NDK_HOME}")
        set(_mma_ndk_root "$ENV{ANDROID_NDK_HOME}")
    elseif(DEFINED VCPKG_ANDROID_NDK AND EXISTS "${VCPKG_ANDROID_NDK}")
        set(_mma_ndk_root "${VCPKG_ANDROID_NDK}")
    else()
        set(_mma_ndk_root "")
    endif()
    if(_mma_ndk_root)
        if(CMAKE_HOST_APPLE)
            if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "arm64|aarch64")
                set(_mma_host_dir "darwin-arm64")
            else()
                set(_mma_host_dir "darwin-x86_64")
            endif()
        elseif(CMAKE_HOST_WIN32)
            set(_mma_host_dir "windows-x86_64")
        else()
            set(_mma_host_dir "linux-x86_64")
        endif()
        set(_mma_api "${VCPKG_ANDROID_PLATFORM}")
        if(NOT _mma_api)
            set(_mma_api "24")
        endif()
        set(_mma_bin "${_mma_ndk_root}/toolchains/llvm/prebuilt/${_mma_host_dir}/bin")
        set(_mma_sysroot "${_mma_ndk_root}/toolchains/llvm/prebuilt/${_mma_host_dir}/sysroot")
        set(_mma_target "aarch64-linux-android${_mma_api}")
        set(_mma_c_wrap "${_mma_bin}/aarch64-linux-android${_mma_api}-clang")
        set(_mma_cpp_wrap "${_mma_bin}/aarch64-linux-android${_mma_api}-clang++")
        if(EXISTS "${_mma_c_wrap}" AND EXISTS "${_mma_cpp_wrap}")
            # NDK 多架构包装器：内嵌 --target 与 --sysroot，编译最稳。
            # 不能设 c_ld/cpp_ld 为编译器包装器——meson 会把它当 GNU 链接器探测，
            # 向 clang 传 --fix-cortex-a53-843419 等 GNU 参数导致 linker detection 失败。
            # 链路目标由下方 c_link_args 强制。
            set(_mma_cc_line "c = ['${_mma_c_wrap}']\ncpp = ['${_mma_cpp_wrap}']")
        else()
            # 退路：通用 clang + 显式 target/sysroot/isystem
            set(_mma_cc_line "c = ['${_mma_bin}/clang', '--target=${_mma_target}', '--sysroot=${_mma_sysroot}', '-isystem', '${_mma_sysroot}/usr/include/aarch64-linux-android']\ncpp = ['${_mma_bin}/clang++', '--target=${_mma_target}', '--sysroot=${_mma_sysroot}', '-isystem', '${_mma_sysroot}/usr/include/aarch64-linux-android']")
        endif()
        # 关键：
        # 1) vcpkg 交叉文件会在 c_link_args 注入 --target=armv7...，覆盖链接默认目标，
        #    使已按 arm64 编译的 .o/.a 链接时仍报 incompatible with armelf_linux_eabi。
        #    这里覆盖 c_link_args 强制 aarch64。
        # 2) Android(Bionic) 无内置 iconv，meson 探测 iconv 时用 -I/-L 找 iconv.h 与
        #    -liconv，但 vcpkg 不会把 installed 头/库路径注入 meson 的依赖探测（probe），
        #    故在 c_args/c_link_args 显式追加 vcpkg installed 的 include/lib。
        set(_mma_inc "${CURRENT_INSTALLED_DIR}/include")
        set(_mma_common_args "'-fPIC', '-g', '-DANDROID', '-D_FILE_OFFSET_BITS=64', '-I${_mma_inc}'")
        set(_mma_link_base "'--target=${_mma_target}', '--sysroot=${_mma_sysroot}'")
        if(NOT DEFINED VCPKG_BUILD_TYPE OR VCPKG_BUILD_TYPE STREQUAL "debug")
            set(_mma_link_dbg "${_mma_link_base}, '-L${CURRENT_INSTALLED_DIR}/debug/lib'")
            set(_mma_cross_dbg "${CURRENT_BUILDTREES_DIR}/meson-cross-arm64-android-dbg.ini")
            file(WRITE "${_mma_cross_dbg}" "[binaries]\n${_mma_cc_line}\n\n[built-in options]\nc_args = [${_mma_common_args}]\ncpp_args = [${_mma_common_args}]\nc_link_args = [${_mma_link_dbg}]\ncpp_link_args = [${_mma_link_dbg}]\n")
            set(VCPKG_MESON_CROSS_FILE_DEBUG "${_mma_cross_dbg}")
        endif()
        if(NOT DEFINED VCPKG_BUILD_TYPE OR VCPKG_BUILD_TYPE STREQUAL "release")
            set(_mma_link_rel "${_mma_link_base}, '-L${CURRENT_INSTALLED_DIR}/lib'")
            set(_mma_cross_rel "${CURRENT_BUILDTREES_DIR}/meson-cross-arm64-android-rel.ini")
            file(WRITE "${_mma_cross_rel}" "[binaries]\n${_mma_cc_line}\n\n[built-in options]\nc_args = [${_mma_common_args}]\ncpp_args = [${_mma_common_args}]\nc_link_args = [${_mma_link_rel}]\ncpp_link_args = [${_mma_link_rel}]\n")
            set(VCPKG_MESON_CROSS_FILE "${_mma_cross_rel}")
            set(VCPKG_MESON_CROSS_FILE_RELEASE "${_mma_cross_rel}")
        endif()
        message(STATUS "${PORT}: android arm64 meson cross override -> ${_mma_cross_rel}")
    endif()
endif()