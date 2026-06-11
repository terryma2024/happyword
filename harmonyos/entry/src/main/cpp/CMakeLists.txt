# Thin adapter CMakeLists for the embedded Cocos battle engine (V1.1.0).
#
# Decision record (Task 0.2): externalNativeOptions.path points HERE instead
# of at the Cocos-generated scaffold root
# (cocos/native/engine/harmonyos-next/CMakeLists.txt) because the scaffold's
# generated arguments pass RES_DIR / COMMON_DIR as *relative* -D strings whose
# resolution depends on CMake's invocation directory (hvigor configures with a
# build dir under entry/.cxx/). This file derives absolute paths from its own
# location and then replicates the scaffold root's recipe verbatim, including
# the same Cocos "common" CMake chain that compiles libcocos.so from the
# engine sources shipped inside the installed Creator 3.8.8 app bundle.
#
# RES_DIR / COMMON_DIR are FORCE-set as cache entries: the common chain
# declares `set(RES_DIR "" CACHE STRING ...)` and under CMP0126 OLD
# (cmake_minimum_required 3.8) a later cache declaration would erase a plain
# variable of the same name.
cmake_minimum_required(VERSION 3.8)

set(CC_LIB_NAME cocos)
set(CC_PROJ_SOURCES)
set(CC_COMMON_SOURCES)
set(CC_ALL_SOURCES)

# harmonyos/entry/src/main/cpp -> repo root is five levels up.
get_filename_component(REPO_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../../../.." ABSOLUTE)
set(RES_DIR    "${REPO_ROOT}/cocos/build/harmonyos-next"   CACHE STRING "Resource path" FORCE)
set(COMMON_DIR "${REPO_ROOT}/cocos/native/engine/common"   CACHE STRING "Cocos common chain" FORCE)

if(NOT EXISTS "${RES_DIR}/proj/cfg.cmake")
    message(FATAL_ERROR
        "Cocos build output missing at ${RES_DIR} — run tools/cocos/build-harmonyos.sh first.")
endif()

option(APP_NAME "Project Name" "WordMagicBattle")
project(${APP_NAME} CXX)

set(CMAKE_CXX_FLAGS_DEBUG "$ENV{CXXFLAGS} -O0 -Wall -g -ggdb -Werror=return-type")
set(CMAKE_CXX_FLAGS_RELEASE "$ENV{CXXFLAGS} -O3 -Wall")

include(${COMMON_DIR}/CMakeLists.txt)

cc_openharmony_before_target(${CC_LIB_NAME})
add_library(${CC_LIB_NAME} SHARED ${CC_ALL_SOURCES})
cc_openharmony_after_target(${CC_LIB_NAME})
