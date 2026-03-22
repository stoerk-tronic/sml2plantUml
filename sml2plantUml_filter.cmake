# =============================================================================
# sml2plantUml Doxygen Filter Script
# =============================================================================
# This script is invoked by Doxygen as an input filter for state machine header
# files. It builds and runs a helper tool that generates PlantUML diagrams from
# Boost.SML state machine definitions, then appends the diagram to the original
# header content and writes the result to stdout.
#
# Usage: cmake -P sml2plantUml_filter.cmake <header_file>
# =============================================================================

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

set(FILTER_SUFFIX "_state_machine_sml\\.hpp$")
set(SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}")
set(BUILD_DIR "${SOURCE_DIR}/build")
set(LOCK_FILE ".filter.lock")
set(FILTER_LOCK_TIMEOUT 600)

# -----------------------------------------------------------------------------
# Input Argument Parsing & Validation
# -----------------------------------------------------------------------------

# The header file path is passed as the last positional argument.
# Doxygen calls: <filter> <file>, so the file is always the last argument.
math(EXPR _LAST_ARG_INDEX "${CMAKE_ARGC} - 1")
set(HEADER "${CMAKE_ARGV${_LAST_ARG_INDEX}}")

if(NOT DEFINED HEADER OR HEADER STREQUAL "")
    message(FATAL_ERROR "No header file provided. Usage: cmake -P sml2plantUml_filter.cmake <header>")
endif()

get_filename_component(HEADER_ABS "${HEADER}" ABSOLUTE)

# Override lock timeout from environment if valid.
if(DEFINED ENV{DOC_FILTER_LOCK_TIMEOUT} AND NOT "$ENV{DOC_FILTER_LOCK_TIMEOUT}" STREQUAL "")
    string(STRIP "$ENV{DOC_FILTER_LOCK_TIMEOUT}" _DOC_FILTER_LOCK_TIMEOUT_STRIPPED)
    string(REGEX MATCH "^[0-9]+$" _DOC_FILTER_LOCK_TIMEOUT_IS_INT "${_DOC_FILTER_LOCK_TIMEOUT_STRIPPED}")
    if(_DOC_FILTER_LOCK_TIMEOUT_IS_INT)
        set(FILTER_LOCK_TIMEOUT "${_DOC_FILTER_LOCK_TIMEOUT_STRIPPED}")
    else()
        message(WARNING
            "Ignoring invalid DOC_FILTER_LOCK_TIMEOUT value '$ENV{DOC_FILTER_LOCK_TIMEOUT}'. "
            "Expected a non-negative integer number of seconds. Using default ${FILTER_LOCK_TIMEOUT} seconds.")
    endif()
endif()

# -----------------------------------------------------------------------------
# Derive State Machine Name
# -----------------------------------------------------------------------------

get_filename_component(FILE_NAME "${HEADER}" NAME)
string(
    REGEX REPLACE ${FILTER_SUFFIX}
    ""
    STATE_MACHINE_NAME
    "${FILE_NAME}"
)

# -----------------------------------------------------------------------------
# Environment Variable Forwarding
# -----------------------------------------------------------------------------

# Forward environment variables for toolchain, extra CXX flags, and include
# directories if they are set.
if(DEFINED ENV{CMAKE_TOOLCHAIN_FILE})
    set(TOOLCHAIN_ARG "-DCMAKE_TOOLCHAIN_FILE=$ENV{CMAKE_TOOLCHAIN_FILE}")
endif()

if(DEFINED ENV{DOC_CXX_FLAGS})
    set(EXTRA_CXX_FLAGS "-DEXTRA_CXX_FLAGS=$ENV{DOC_CXX_FLAGS}")
endif()

if(DEFINED ENV{DOC_INCLUDE_DIRS})
    set(EXTRA_INCLUDE_DIRS "-DEXTRA_INCLUDE_DIRS=$ENV{DOC_INCLUDE_DIRS}")
endif()

# -----------------------------------------------------------------------------
# Concurrency Control
# -----------------------------------------------------------------------------

# Serialize concurrent filter invocations (Doxygen may call this in parallel).

file(LOCK "${LOCK_FILE}" TIMEOUT ${FILTER_LOCK_TIMEOUT} RESULT_VARIABLE lock_result)
if(NOT lock_result STREQUAL "0")
    message(FATAL_ERROR
        "Failed to acquire filter lock file '${LOCK_FILE}' within ${FILTER_LOCK_TIMEOUT} seconds "
        "(lock_result='${lock_result}'). "
        "If your builds are slow or highly parallel, increase DOC_FILTER_LOCK_TIMEOUT.")
endif()

# -----------------------------------------------------------------------------
# Generator Selection
# -----------------------------------------------------------------------------

# Use Ninja generator for the initial configure if available, otherwise fall
# back to the default generator. MSBuild may have issues with parallel builds
# and file locking, so prefer Ninja if it's available.
# Do not override the generator if the build directory is already configured
# (has a CMakeCache.txt), to avoid CMake generator mismatch errors.
if(NOT EXISTS "${BUILD_DIR}/CMakeCache.txt")
    find_program(_NINJA_EXECUTABLE ninja)
    if(_NINJA_EXECUTABLE)
        set(GENERATOR_ARG -G Ninja)
    endif()
endif()

# -----------------------------------------------------------------------------
# Configure & Build
# -----------------------------------------------------------------------------

execute_process(
    COMMAND
        ${CMAKE_COMMAND} ${GENERATOR_ARG} -S "${SOURCE_DIR}" -B "${BUILD_DIR}" ${TOOLCHAIN_ARG}
        ${EXTRA_CXX_FLAGS} ${EXTRA_INCLUDE_DIRS}
        -DHEADER_TO_CHECK="${HEADER_ABS}"
        -DSTATE_MACHINE_NAME="${STATE_MACHINE_NAME}"
    OUTPUT_QUIET
    RESULT_VARIABLE configure_result
)

if(NOT configure_result EQUAL 0)
    file(LOCK "${LOCK_FILE}" RELEASE)
    message(FATAL_ERROR "CMake configure failed")
endif()

execute_process(
    COMMAND ${CMAKE_COMMAND} --build "${BUILD_DIR}"
    OUTPUT_QUIET
    RESULT_VARIABLE build_result
)

if(NOT build_result EQUAL 0)
    file(LOCK "${LOCK_FILE}" RELEASE)
    message(FATAL_ERROR "Build failed")
endif()

# -----------------------------------------------------------------------------
# Run Helper Tool
# -----------------------------------------------------------------------------

if(WIN32)
    set(APP_PATH "${BUILD_DIR}/StateMachine2Puml.exe")
else()
    set(APP_PATH "${BUILD_DIR}/StateMachine2Puml")
endif()

execute_process(
    COMMAND "${APP_PATH}"
    OUTPUT_VARIABLE PUML_CONTENT
    RESULT_VARIABLE run_result
)

file(LOCK "${LOCK_FILE}" RELEASE)

if(NOT run_result EQUAL 0)
    message(FATAL_ERROR "Execution failed")
endif()

# -----------------------------------------------------------------------------
# Output Generation
# -----------------------------------------------------------------------------

# Build the documentation comment block.
string(CONCAT DOC_BLOCK
    "/**\n"
    "\\file\n"
    "${PUML_CONTENT}"
    "*/\n"
)

# Write original header with appended documentation block to stdout for Doxygen.
# CMake's message() writes to stderr, so we write to a temp file and use
# cmake -E cat which outputs to stdout.
file(READ "${HEADER_ABS}" CONTENT)
set(FILTER_OUTPUT_FILE "${BUILD_DIR}/_filter_output_${STATE_MACHINE_NAME}.tmp")
file(WRITE "${FILTER_OUTPUT_FILE}" "${CONTENT}\n${DOC_BLOCK}")
execute_process(
    COMMAND ${CMAKE_COMMAND} -E cat "${FILTER_OUTPUT_FILE}"
    RESULT_VARIABLE cat_result
)
if(cat_result EQUAL 0)
    file(REMOVE "${FILTER_OUTPUT_FILE}")
endif()
