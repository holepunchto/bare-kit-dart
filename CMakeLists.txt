cmake_minimum_required(VERSION 4.0)

find_package(cmake-bare REQUIRED PATHS node_modules/cmake-bare)
find_package(cmake-fetch REQUIRED PATHS node_modules/cmake-fetch)
find_package(cmake-prelude REQUIRED PATHS node_modules/cmake-prelude)

project(bare_kit_dart C)

fetch_package("github:holepunchto/bare-kit@3.3.0")

if(DEFINED ENV{DART_HOME})
  set(dart_home "$ENV{DART_HOME}")
else()
  find_program(dart dart REQUIRED)

  file(REAL_PATH "${dart}" dart)

  cmake_path(GET dart PARENT_PATH dart_home)
  cmake_path(GET dart_home PARENT_PATH dart_home)
endif()

set(dart_include "${dart_home}/include")

if(NOT EXISTS "${dart_include}/dart_api_dl.c")
  message(FATAL_ERROR "No Dart SDK found at ${dart_home}, set DART_HOME to its path")
endif()

add_library_targets(
  bare_kit_dart
  TYPE SHARED
  SOURCES
    src/shim.c
    "${dart_include}/dart_api_dl.c"
  LINK
    PRIVATE
      $<LINK_LIBRARY:WHOLE_ARCHIVE,bare_kit::static>
  EXPORTS
    Dart_InitializeApiDL
    bare_kit_dart_on_exit
    bare_kit_dart_port_create
    bare_kit_dart_port_destroy
  STRIP ON
  INSTALL OFF
)

target_include_directories(
  bare_kit_dart
  PRIVATE
    "${dart_include}"
)

target_compile_definitions(
  bare_kit_dart
  PRIVATE
    DART_SHARED_LIB
)

target_link_libraries(
  bare_kit_dart_exports
  INTERFACE
    bare_kit::exports
)

set_target_properties(
  bare_kit_dart_shared
  PROPERTIES
  OUTPUT_NAME bare-kit
)

if(ANDROID)
  target_link_options(
    bare_kit_dart_shared
    PRIVATE
      "-Wl,-z,global" # Resolve addons against the library when loaded locally
  )
endif()

if(LINUX)
  target_link_options(
    bare_kit_dart_shared
    PRIVATE
      "-Wl,-z,now" # Use eager binding
  )
endif()

bare_target(target)

install(FILES $<TARGET_FILE:bare_kit_dart_shared> DESTINATION ${target})
