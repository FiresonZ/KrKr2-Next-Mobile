vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO google/brotli
    REF v${VERSION} # v1.1.0 
    SHA512 6eb280d10d8e1b43d22d00fa535435923c22ce8448709419d676ff47d4a644102ea04f488fc65a179c6c09fee12380992e9335bad8dfebd5d1f20908d10849d9
    HEAD_REF master
    PATCHES
        install.patch
        fix-arm-uwp.patch
        pkgconfig.patch
        emscripten.patch
)

# Overlay（照搬 baseline b1e15ef，port-version 1 -> 2）：
# Android arm64 强制 NDK aarch64，并 bump 令 vcpkg ABI 变化以避开缓存里旧的 armv7
# libbrotli*.a（freetype/cairo 链接时报 incompatible with aarch64linux）。
include("${CMAKE_CURRENT_LIST_DIR}/../_cmake_android_arm64.cmake")
set(_BROTLI_ANDROID_OPTIONS "")
append_cmake_android_arm64_options(_BROTLI_ANDROID_OPTIONS)

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        -DBROTLI_DISABLE_TESTS=ON
        ${_BROTLI_ANDROID_OPTIONS}
)
vcpkg_cmake_install()
vcpkg_copy_pdbs()
vcpkg_fixup_pkgconfig()
vcpkg_cmake_config_fixup(CONFIG_PATH share/unofficial-brotli PACKAGE_NAME unofficial-brotli)

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/tools")

# Under emscripten the brotli executable tool is produced with .js extension but vcpkg_copy_tools
# has no special behaviour in this case and searches for the tool name with no extension
if(VCPKG_TARGET_IS_EMSCRIPTEN)
	set(TOOL_SUFFIX ".js" )
endif()

vcpkg_copy_tools(TOOL_NAMES "brotli${TOOL_SUFFIX}" SEARCH_DIR "${CURRENT_PACKAGES_DIR}/tools/brotli")

file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
