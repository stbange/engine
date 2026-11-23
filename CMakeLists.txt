cmake_minimum_required(VERSION 3.20)
project(engine VERSION 0.2.0 LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
    set(ENG_IS_TOP_LEVEL ON)
else()
    set(ENG_IS_TOP_LEVEL OFF)
endif()

option(ENG_BUILD_RUNNER "Build standalone engine runner executable" ${ENG_IS_TOP_LEVEL})
option(ENG_BUILD_TESTS "Build unit and headless test suite" ${ENG_IS_TOP_LEVEL})
option(ENG_ENABLE_COVERAGE "Enable gcov/lcov instrumentation on first-party C code" OFF)

if(EMSCRIPTEN)
    set(ENG_DEFAULT_LUAJIT OFF)
else()
    set(ENG_DEFAULT_LUAJIT ON)
endif()
option(ENG_USE_LUAJIT "Use LuaJIT 2.1 on Desktop (falls back to vendored Lua 5.1.5 + LuaBitOp)" ${ENG_DEFAULT_LUAJIT})

# -----------------------------------------------------------------------------
# 1. Platform & SDL3 Discovery (with FetchContent fallback on fresh hosts)
# -----------------------------------------------------------------------------
if(EMSCRIPTEN)
    add_library(eng_sdl3 INTERFACE)
    target_compile_options(eng_sdl3 INTERFACE "--use-port=sdl3")
    target_link_options(eng_sdl3 INTERFACE
        "--use-port=sdl3"
        "-sUSE_WEBGL2=1"
        "-sFULL_ES3=1"
        "-sALLOW_MEMORY_GROWTH=1"
    )
else()
    find_package(SDL3 QUIET)
    if(NOT SDL3_FOUND)
        include(FetchContent)
        set(SDL_SHARED OFF CACHE BOOL "" FORCE)
        set(SDL_STATIC ON CACHE BOOL "" FORCE)
        set(SDL_X11_XTEST OFF CACHE BOOL "" FORCE)
        set(SDL_TESTS OFF CACHE BOOL "" FORCE)
        set(SDL_EXAMPLES OFF CACHE BOOL "" FORCE)
        set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
        FetchContent_Declare(
            SDL3
            GIT_REPOSITORY https://github.com/libsdl-org/SDL.git
            GIT_TAG release-3.4.20
            GIT_SHALLOW TRUE
        )
        FetchContent_MakeAvailable(SDL3)
    endif()
    add_library(eng_sdl3 INTERFACE)
    if(TARGET SDL3::SDL3)
        target_link_libraries(eng_sdl3 INTERFACE SDL3::SDL3)
    else()
        target_link_libraries(eng_sdl3 INTERFACE SDL3::SDL3-static)
    endif()
endif()

# -----------------------------------------------------------------------------
# 2. Lua Runtime (LuaJIT 2.1 on Desktop, or vendored PUC-Rio Lua 5.1.5 + bitop)
# -----------------------------------------------------------------------------
set(ENG_FOUND_LUAJIT OFF)
if(ENG_USE_LUAJIT AND NOT EMSCRIPTEN)
    find_package(PkgConfig QUIET)
    if(PkgConfig_FOUND)
        pkg_check_modules(LUAJIT QUIET IMPORTED_TARGET luajit)
        if(LUAJIT_FOUND)
            set(ENG_FOUND_LUAJIT ON)
        endif()
    endif()
endif()

file(GLOB ENG_LUA51_SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/third_party/lua51/*.c")

set(ENG_THIRD_PARTY_SOURCES
    "${CMAKE_CURRENT_SOURCE_DIR}/third_party/third_party_impl.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/third_party/nuklear_impl.c"
)
if(NOT ENG_FOUND_LUAJIT)
    list(APPEND ENG_THIRD_PARTY_SOURCES
        ${ENG_LUA51_SOURCES}
        "${CMAKE_CURRENT_SOURCE_DIR}/third_party/luabitop/bit.c"
    )
endif()

add_library(eng_third_party STATIC ${ENG_THIRD_PARTY_SOURCES})
target_include_directories(eng_third_party PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/third_party/stb"
    "${CMAKE_CURRENT_SOURCE_DIR}/third_party/cgltf"
    "${CMAKE_CURRENT_SOURCE_DIR}/third_party/nuklear"
)
if(NOT ENG_FOUND_LUAJIT)
    target_include_directories(eng_third_party PUBLIC
        "${CMAKE_CURRENT_SOURCE_DIR}/third_party/lua51"
    )
    if(UNIX AND NOT APPLE AND NOT EMSCRIPTEN)
        target_compile_definitions(eng_third_party PRIVATE LUA_USE_LINUX _XOPEN_SOURCE=700)
        target_link_libraries(eng_third_party PUBLIC dl)
    elseif(APPLE)
        target_compile_definitions(eng_third_party PRIVATE LUA_USE_MACOSX)
    endif()
endif()
if(UNIX)
    target_link_libraries(eng_third_party PUBLIC m)
endif()

# -----------------------------------------------------------------------------
# 3. Core Engine Library (libengine) — Strictly First-Party C11 Sources
# -----------------------------------------------------------------------------
set(ENG_CORE_SOURCES
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_version.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_cli.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_math.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_mem.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_log.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_jobs.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_vfs.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_events.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_serde.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_ecs.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_scene.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_gl.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_platform.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_input.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_xr.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_portal.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_shader.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_asset.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_voxel.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_sprite.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_render.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_procgen.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_terrain.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_particles.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_text.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_i18n.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_anim.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_physics.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_audio.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_ai.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_net.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_lua.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_doctor.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_profiler.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_ui.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/eng_editor.c"
)

add_library(libengine STATIC ${ENG_CORE_SOURCES})
add_library(engine::core ALIAS libengine)
set_target_properties(libengine PROPERTIES OUTPUT_NAME engine)

target_include_directories(libengine
    PUBLIC
        "${CMAKE_CURRENT_SOURCE_DIR}/include"
    PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/src"
)

target_link_libraries(libengine
    PUBLIC
        eng_sdl3
    PRIVATE
        eng_third_party
)

if(ENG_FOUND_LUAJIT)
    target_compile_definitions(libengine PRIVATE ENG_USING_LUAJIT=1)
    target_link_libraries(libengine PRIVATE PkgConfig::LUAJIT)
endif()

if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(libengine PRIVATE -Wall -Wextra -Wpedantic -Werror=implicit-function-declaration)
endif()

if(ENG_ENABLE_COVERAGE AND NOT EMSCRIPTEN)
    target_compile_options(libengine PUBLIC --coverage -O0 -g)
    target_link_options(libengine PUBLIC --coverage)
endif()

# -----------------------------------------------------------------------------
# 4. Standalone Data-Driven Runner Executable (engine)
# -----------------------------------------------------------------------------
if(ENG_BUILD_RUNNER)
    add_executable(engine "${CMAKE_CURRENT_SOURCE_DIR}/src/main.c")
    target_link_libraries(engine PRIVATE libengine)
    if(EMSCRIPTEN)
        target_link_options(engine PRIVATE
            "-lidbfs.js"
            "-sFORCE_FILESYSTEM=1"
            "-sSTACK_SIZE=2097152"
            "-sINITIAL_MEMORY=33554432"
            "-sEXPORTED_FUNCTIONS=['_main','_malloc','_free','_eng_web_inject_action','_eng_web_inject_axis','_eng_web_submit_xr_frame','_eng_web_end_xr']"
            "-sEXPORTED_RUNTIME_METHODS=['callMain','FS','IDBFS','ccall','cwrap','HEAPF32','HEAP32','GL']"
        )
    endif()
endif()

# -----------------------------------------------------------------------------
# 5. Unit & Headless Test Suite (CTest)
# -----------------------------------------------------------------------------
if(ENG_BUILD_TESTS AND NOT EMSCRIPTEN)
    enable_testing()
    add_executable(engine_tests
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/unit/test_phase0.c"
    )
    target_compile_definitions(engine_tests PRIVATE
        ENG_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}"
        ENG_BINARY_DIR="${CMAKE_CURRENT_BINARY_DIR}"
    )
    target_link_libraries(engine_tests PRIVATE libengine)
    add_test(NAME phase0_unit_tests COMMAND engine_tests)

    add_executable(test_phase1
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/unit/test_phase1.c"
    )
    target_compile_definitions(test_phase1 PRIVATE
        ENG_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}"
        ENG_BINARY_DIR="${CMAKE_CURRENT_BINARY_DIR}"
    )
    target_link_libraries(test_phase1 PRIVATE libengine)
    add_test(NAME phase1_unit_tests COMMAND test_phase1)

    add_executable(test_phase2
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/unit/test_phase2.c"
    )
    target_link_libraries(test_phase2 PRIVATE libengine)
    add_test(NAME phase2_unit_tests COMMAND test_phase2)

    add_executable(test_phase3
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/unit/test_phase3.c"
    )
    target_compile_definitions(test_phase3 PRIVATE
        ENG_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}"
        ENG_BINARY_DIR="${CMAKE_CURRENT_BINARY_DIR}"
    )
    target_link_libraries(test_phase3 PRIVATE libengine)
    add_test(NAME phase3_unit_tests COMMAND test_phase3)

    add_executable(test_phase4
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/unit/test_phase4.c"
    )
    target_compile_definitions(test_phase4 PRIVATE
        ENG_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}"
        ENG_BINARY_DIR="${CMAKE_CURRENT_BINARY_DIR}"
    )
    target_link_libraries(test_phase4 PRIVATE libengine)
    add_test(NAME phase4_unit_tests COMMAND test_phase4)

    add_executable(test_phase5
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/unit/test_phase5.c"
    )
    target_link_libraries(test_phase5 PRIVATE libengine)
    add_test(NAME phase5_unit_tests COMMAND test_phase5)

    add_executable(test_phase6
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/unit/test_phase6.c"
    )
    target_compile_definitions(test_phase6 PRIVATE
        ENG_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}"
        ENG_BINARY_DIR="${CMAKE_CURRENT_BINARY_DIR}"
    )
    target_link_libraries(test_phase6 PRIVATE libengine)
    add_test(NAME phase6_unit_tests COMMAND test_phase6)

    add_executable(test_phase7
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/unit/test_phase7.c"
    )
    target_compile_definitions(test_phase7 PRIVATE
        ENG_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}"
        ENG_BINARY_DIR="${CMAKE_CURRENT_BINARY_DIR}"
    )
    target_link_libraries(test_phase7 PRIVATE libengine)
    add_test(NAME phase7_unit_tests COMMAND test_phase7)

    add_executable(test_phase8
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/unit/test_phase8.c"
    )
    target_compile_definitions(test_phase8 PRIVATE
        ENG_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}"
        ENG_BINARY_DIR="${CMAKE_CURRENT_BINARY_DIR}"
    )
    target_link_libraries(test_phase8 PRIVATE libengine)
    add_test(NAME phase8_unit_tests COMMAND test_phase8)
endif()
