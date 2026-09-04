set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME Android)
set(VCPKG_ANDROID_PLATFORM 24)
set(VCPKG_ANDROID_ABI arm64-v8a)

# NDK toolchain is picked up via the ANDROID_NDK_HOME environment variable,
# or VCPKG_ANDROID_NDK if set explicitly in the environment.

# Fix autotools cross-compilation detection for Android
# Without this, configure may think it is not cross-compiling and try to run
# target binaries on the host.
set(VCPKG_MAKE_BUILD_TRIPLET "--host=aarch64-linux-android")
