cmake_minimum_required(VERSION 3.21)
project(
    MTFPulse
    VERSION 0.0.1
    DESCRIPTION "Magic Tattoos Framework — per-frame pulse animation SKSE plugin"
    LANGUAGES CXX
)

# Skyrim AE 1.6.1170. CommonLibSSE-NG defaults are fine; force C++23 explicitly.
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# ── CommonLibSSE-NG via add_subdirectory ────────────────────────────────────
# Local clone under extern/CommonLibSSE-NG (see build.bat for the one-shot
# git clone if absent). Using add_subdirectory keeps the vcpkg toolchain
# inherited so CommonLibSSE's find_package(fmt) / find_package(spdlog) /
# find_package(Catch2) all resolve against our manifest in vcpkg.json.
set(BUILD_TESTS OFF CACHE BOOL "Build CommonLibSSE tests" FORCE)
set(SKSE_SUPPORT_XBYAK OFF CACHE BOOL "Enable Xbyak in CommonLibSSE" FORCE)
add_subdirectory(extern/CommonLibSSE-NG)

find_package(spdlog CONFIG REQUIRED)

# ── Plugin DLL ──────────────────────────────────────────────────────────────
add_library(${PROJECT_NAME} SHARED
    src/main.cpp
    src/pulse_roster.cpp
    src/pulse_roster.h
    src/papyrus.cpp
    src/papyrus.h
    src/skee_bridge.cpp
    src/skee_bridge.h
    src/skee_interface.h
    src/frame_hook.cpp
    src/frame_hook.h
    src/log.h
)

target_compile_definitions(${PROJECT_NAME}
    PRIVATE
        UNICODE
        _UNICODE
        WINVER=0x0A00            # Windows 10+
        _WIN32_WINNT=0x0A00
)

target_link_libraries(${PROJECT_NAME}
    PRIVATE
        CommonLibSSE
        spdlog::spdlog
)

target_compile_options(${PROJECT_NAME}
    PRIVATE
        /W4
        /WX-     # warnings, not errors — keep dev iteration fast
        /utf-8
        /Zc:__cplusplus
        /Zc:preprocessor
        /permissive-
)

# Output to a plugins-shaped tree so we can copy the whole build/ folder
# into Data/SKSE/Plugins.
set_target_properties(${PROJECT_NAME} PROPERTIES
    OUTPUT_NAME "MTFPulse"
    SUFFIX ".dll"
)
