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

# ---------------------------------------------------------------------------
# WMG PATCH(surface-recreation): swap the engine's OpenHarmonyPlatform.cpp
# for our patched copy (cocos-patches/OpenHarmonyPlatform.cpp) inside the
# cocos_engine target that the include() above just defined. Stock 3.8.8
# cannot survive XComponent surface destroy + re-creation — see the banner
# comment in the patched file for the full mechanism.
#
# The SHA256 guard pins the bundle original: if a Creator upgrade (or
# hotfix) changes the file, the build fails here with instructions instead
# of silently compiling a patch diffed against a different base.
# COCOS_X_PATH comes from ${RES_DIR}/proj/cfg.cmake (already included).
# ---------------------------------------------------------------------------
set(WMG_OHPLATFORM_ORIG "${COCOS_X_PATH}/cocos/platform/openharmony/OpenHarmonyPlatform.cpp")
set(WMG_OHPLATFORM_ORIG_SHA256 "6063a93db2615c1eab256cb6a6c4d1dc1c83a084c43dacb8caca095da589968e")
file(SHA256 "${WMG_OHPLATFORM_ORIG}" _wmg_ohplatform_actual_sha256)
if(NOT _wmg_ohplatform_actual_sha256 STREQUAL WMG_OHPLATFORM_ORIG_SHA256)
    message(FATAL_ERROR
        "Cocos engine file drifted from the base our surface-recreation patch "
        "was diffed against:\n  ${WMG_OHPLATFORM_ORIG}\n"
        "expected SHA256 ${WMG_OHPLATFORM_ORIG_SHA256}\n"
        "actual   SHA256 ${_wmg_ohplatform_actual_sha256}\n"
        "Re-diff cocos-patches/OpenHarmonyPlatform.cpp against the new engine "
        "source (all patched blocks are marked 'WMG PATCH(surface-recreation)') "
        "and update WMG_OHPLATFORM_ORIG_SHA256 in this file.")
endif()
get_target_property(_wmg_engine_sources cocos_engine SOURCES)
set(_wmg_engine_sources_patched)
set(_wmg_ohplatform_found FALSE)
foreach(_wmg_src IN LISTS _wmg_engine_sources)
    if(_wmg_src MATCHES "cocos/platform/openharmony/OpenHarmonyPlatform\\.cpp$")
        set(_wmg_ohplatform_found TRUE)
        list(APPEND _wmg_engine_sources_patched
            "${CMAKE_CURRENT_LIST_DIR}/cocos-patches/OpenHarmonyPlatform.cpp")
    else()
        list(APPEND _wmg_engine_sources_patched "${_wmg_src}")
    endif()
endforeach()
if(NOT _wmg_ohplatform_found)
    message(FATAL_ERROR
        "OpenHarmonyPlatform.cpp not found in cocos_engine sources — the "
        "engine CMake layout changed; re-derive the surface-recreation patch "
        "wiring in this file.")
endif()
set_target_properties(cocos_engine PROPERTIES SOURCES "${_wmg_engine_sources_patched}")

cc_openharmony_before_target(${CC_LIB_NAME})
add_library(${CC_LIB_NAME} SHARED ${CC_ALL_SOURCES})
cc_openharmony_after_target(${CC_LIB_NAME})
