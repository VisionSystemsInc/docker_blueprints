# Require CMake 3.15+ (matching scikit-build-core) Use new versions of all
# policies up to CMake 3.27
cmake_minimum_required(VERSION 3.17...3.27)

project(
  ${SKBUILD_PROJECT_NAME}
  VERSION ${SKBUILD_PROJECT_VERSION}
  LANGUAGES CXX)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# For future use
if(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
    # Some fixes for the ng-log library.
    add_definitions("-DNGLOG_NO_ABBREVIATED_SEVERITIES")
    add_definitions("-DGL_GLEXT_PROTOTYPES")
    add_definitions("-DNOMINMAX")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /EHsc")
    # Enable object level parallel builds in Visual Studio.
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} /MP")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /MP")
endif()

# Find the module development requirements (requires FindPython from 3.17 or
# scikit-build-core's built-in backport)
find_package(Python REQUIRED COMPONENTS Interpreter Development.Module)
find_package(pybind11 CONFIG REQUIRED)
# set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "/nglog/cmake")
find_package(ng-log 0.8.0 REQUIRED)

pybind11_add_module(nglog py_nglog.cpp WITH_SOABI)

# This is passing in the version as a #define
target_compile_definitions(nglog PRIVATE VERSION_INFO=\"${PROJECT_VERSION}\")

target_link_libraries(nglog PRIVATE ng-log::ng-log pybind11::headers)

# The install directory is the output (wheel) directory
install(TARGETS nglog LIBRARY DESTINATION .)
