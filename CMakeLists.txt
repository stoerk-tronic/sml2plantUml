cmake_minimum_required(VERSION 3.24)

project(
    StateMachine2Puml
    VERSION 1.0.0
    DESCRIPTION "Transform SML state machines to PlantUML diagrams"
    LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

include(FetchContent)

FetchContent_Declare(
    sml
    GIT_REPOSITORY https://github.com/boost-ext/sml.git
    GIT_TAG v1.1.13
)

FetchContent_MakeAvailable(sml)

if(NOT DEFINED HEADER_TO_CHECK)
    message(FATAL_ERROR "HEADER_TO_CHECK not set")
endif()

if(NOT DEFINED STATE_MACHINE_NAME)
    message(FATAL_ERROR "STATE_MACHINE_NAME not set")
endif()

# Strip surrounding quotes that may be added when variables are passed
# via execute_process(COMMAND cmake -D...) rather than from a shell.
string(REGEX REPLACE "^\"(.*)\"$" "\\1" HEADER_TO_CHECK "${HEADER_TO_CHECK}")
string(REGEX REPLACE "^\"(.*)\"$" "\\1" STATE_MACHINE_NAME "${STATE_MACHINE_NAME}")

add_executable(StateMachine2Puml transformSml2plantUml.cpp)

target_compile_definitions(
    StateMachine2Puml
    PRIVATE
        HEADER_TO_CHECK=\"${HEADER_TO_CHECK}\"
        STATE_MACHINE_NAME=${STATE_MACHINE_NAME}
)

target_link_libraries(StateMachine2Puml PRIVATE sml)
