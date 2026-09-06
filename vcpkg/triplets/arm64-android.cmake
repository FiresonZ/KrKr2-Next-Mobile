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
# CMAKE_SYSTEM_PROCESSOR 也必须显式设为 aarch64：vcpkg 的 get_vars 在没有它时会按
# 32 位 ARM 推导 target/编译参数，导致 boost-locale 等 cmake 端口被编成 armv7（其
# CMake config 版本串带 "(32bit)"）。zlib/libpng/freetype 的 per-port overlay 恰是因为
# 额外补了 -DCMAKE_SYSTEM_PROCESSOR=aarch64 才编对。这里落实成全局，避免每个 cmake
# 端口都打 overlay。
set(ANDROID_ABI arm64-v8a CACHE STRING "")
set(CMAKE_ANDROID_ARCH_ABI arm64-v8a CACHE STRING "")
set(CMAKE_SYSTEM_PROCESSOR aarch64 CACHE STRING "")
set(ANDROID_PLATFORM android-24 CACHE STRING "")
set(ANDROID_NATIVE_API_LEVEL 24 CACHE STRING "")

# NDK toolchain is picked up via the ANDROID_NDK_HOME environment variable,
# or VCPKG_ANDROID_NDK if set explicitly in the environment.

# Fix autotools cross-compilation detection for Android
# Without this, configure may think it is not cross-compiling and try to run
# target binaries on the host.
set(VCPKG_MAKE_BUILD_TRIPLET "--host=aarch64-linux-android")

# 上游(KrKr2-Next)的做法：把 -DANDROID_ABI=arm64-v8a 作为 VCPKG_CMAKE_CONFIGURE_OPTIONS
# 传给【每一个】cmake 端口（含 boost-locale / boost-iostreams 等 CMake 型 boost 组件），
# 这才是 boost 能正确按 arm64 配置的根因。之前的做法只设 VCPKG_ANDROID_ABI + 顶部 cache
# 变量，未进入各端口子 cmake 得 configure，导致 boost 等 CMake 端口被默认按 32 位配置，
# 生成的 config 版本串被误标 "(32bit)"，find_package(Boost ...) EXACT 转发时失败，
# 并被迫为 zlib/libpng/freetype/glib 等逐个打 overlay 补救。这里补齐全局 ABI 选项根治。
set(VCPKG_CMAKE_CONFIGURE_OPTIONS -DANDROID_ABI=arm64-v8a)
