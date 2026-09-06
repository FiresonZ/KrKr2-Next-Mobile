cmake_minimum_required(VERSION 3.19)

project(psdparse)

add_library(${PROJECT_NAME} STATIC
	bmp.cpp
	psddesc.cpp
	psdfile.cpp
	psdimage.cpp
	psdlayer.cpp
	psdparse.cpp
	psdresource.cpp
)

# 直接按 CONFIG 逐个找组件，避开 vcpkg BoostConfig 的 EXACT 版本转发。
# 同 cpp/core/tjs2/CMakeLists.txt：Android 上生成的 boost_*-config 版本串带 "(32bit)"
# 误标后缀，经 BoostConfig EXACT 转发时失败；库本身是 arm64，直接 CONFIG 不校验版本即可。
find_package(boost_phoenix CONFIG REQUIRED)
find_package(boost_spirit CONFIG REQUIRED)
find_package(boost_iostreams CONFIG REQUIRED)

target_link_libraries(${PROJECT_NAME} PRIVATE
	krkr2plugin Boost::phoenix Boost::spirit Boost::iostreams
)