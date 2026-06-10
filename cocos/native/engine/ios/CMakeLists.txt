cmake_minimum_required(VERSION 3.8)

set(CMAKE_SYSTEM_NAME iOS)
set(APP_NAME "WordMagicBattle"  CACHE STRING "Project Name")

project(${APP_NAME} CXX)

# Xcode 26 clang rejects the std-trait specializations in the engine's bundled
# enoki headers (arm64 NEON path only); demote until Cocos updates enoki.
add_compile_options($<$<COMPILE_LANGUAGE:CXX>:-Wno-invalid-specialization>)

set(CC_PROJECT_DIR ${CMAKE_CURRENT_LIST_DIR})
set(CC_UI_RESOURCES)
set(CC_PROJ_SOURCES)
set(CC_ASSET_FILES)
set(CC_COMMON_SOURCES)
set(CC_ALL_SOURCES)

include(${CC_PROJECT_DIR}/../common/CMakeLists.txt)
set(EXECUTABLE_NAME ${APP_NAME}-mobile)

cc_ios_before_target(${EXECUTABLE_NAME})
add_executable(${EXECUTABLE_NAME} ${CC_ALL_SOURCES})
cc_ios_after_target(${EXECUTABLE_NAME})
