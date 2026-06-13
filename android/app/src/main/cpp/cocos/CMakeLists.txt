# Thin adapter CMakeLists for the embedded Cocos battle engine (V1.1.0).
#
# Decision record (Task 0.2): externalNativeBuild.cmake.path points HERE
# instead of at the Cocos-generated scaffold root
# (cocos/native/engine/android/CMakeLists.txt) because the scaffold's
# gradle.properties passes RES_PATH / NATIVE_DIR / COCOS_ENGINE_PATH as
# absolute machine-specific strings resolved at the Cocos Creator build step.
# This file derives absolute paths from its own location and then includes the
# scaffold's android/CMakeLists.txt recipe verbatim, which itself includes the
# Cocos "common" CMake chain that compiles libcocos.so from the engine sources
# shipped inside the installed Creator 3.8.8 app bundle.
#
# RES_DIR / COMMON_DIR are FORCE-set as cache entries: the common chain
# declares `set(RES_DIR "" CACHE STRING ...)` and under CMP0126 OLD
# (cmake_minimum_required 3.8) a later cache declaration would erase a plain
# variable of the same name.
cmake_minimum_required(VERSION 3.8)

set(CC_LIB_NAME cocos)
set(CC_PROJECT_DIR "${CMAKE_CURRENT_LIST_DIR}")
set(CC_PROJ_SOURCES)
set(CC_COMMON_SOURCES)
set(CC_ALL_SOURCES)

# android/app/src/main/cpp/cocos (CMAKE_CURRENT_LIST_DIR) -> repo root:
# ../  = cpp/   ../../../  = src/   ../../../../../  = app/  (one more) = android/  (one more) = repo root
# That is 6 levels up from the directory containing this file.
get_filename_component(REPO_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../../../../.." ABSOLUTE)
set(RES_DIR    "${REPO_ROOT}/cocos/build/android"          CACHE STRING "Resource path" FORCE)
set(COMMON_DIR "${REPO_ROOT}/cocos/native/engine/common"   CACHE STRING "Cocos common chain" FORCE)

if(NOT EXISTS "${RES_DIR}/proj/cfg.cmake")
    message(FATAL_ERROR
        "Cocos build output missing at ${RES_DIR} — run tools/cocos/build-android.sh first.")
endif()

# Pull in cfg.cmake (sets COCOS_X_PATH, feature flags etc.) so the common
# chain has the same variables it would get from the generated gradle project.
include(${RES_DIR}/proj/cfg.cmake)

option(APP_NAME "Project Name" "WordMagicBattle")
project(${APP_NAME} CXX)

set(CMAKE_CXX_FLAGS_DEBUG "$ENV{CXXFLAGS} -O0 -Wall -g -ggdb -Werror=return-type")
set(CMAKE_CXX_FLAGS_RELEASE "$ENV{CXXFLAGS} -O3 -Wall")

include(${COMMON_DIR}/CMakeLists.txt)

# No engine patch needed for Android (unlike HarmonyOS surface-recreation fix).
cc_android_before_target(${CC_LIB_NAME})
add_library(${CC_LIB_NAME} SHARED ${CC_ALL_SOURCES})
cc_android_after_target(${CC_LIB_NAME})
