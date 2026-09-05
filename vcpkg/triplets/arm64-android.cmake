set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME Android)
set(VCPKG_ANDROID_PLATFORM 24)
set(VCPKG_ANDROID_ABI arm64-v8a)

# 关键：vcpkg 的 scripts/toolchains/android.cmake 不会把 VCPKG_ANDROID_ABI 翻译成
# cmake 的 ANDROID_ABI；它 include 的 NDK android.toolchain.cmake 在 ANDROID_ABI 未设时
# 默认回落 armeabi-v7a（armv7-32 + API21），导致 meson/make 型端口（glib、libffi 原厂）
# 全部按 `--target=armv7-none-linux-androideabi21` 构建，与 arm64 引擎/CMake 端口错配。
# 这里直接在 triplet 强制 NDK 缓存变量（triplet 会被包含 get-vars 在内的每次 cmake 加载）。
# CMAKE_ANDROID_ARCH_ABI 是现代 NDK toolchain 真正读取的 ABI 开关（ANDROID_ABI 是旧名），
# 同时设两者，确保 cmake 型端口、get-vars 派生的 make/meson 型端口都按 arm64 构建。
set(ANDROID_ABI arm64-v8a CACHE STRING "")
set(CMAKE_ANDROID_ARCH_ABI arm64-v8a CACHE STRING "")
set(ANDROID_PLATFORM android-24 CACHE STRING "")
set(ANDROID_NATIVE_API_LEVEL 24 CACHE STRING "")

# NDK toolchain is picked up via the ANDROID_NDK_HOME environment variable,
# or VCPKG_ANDROID_NDK if set explicitly in the environment.

# Fix autotools cross-compilation detection for Android
# Without this, configure may think it is not cross-compiling and try to run
# target binaries on the host.
set(VCPKG_MAKE_BUILD_TRIPLET "--host=aarch64-linux-android")
