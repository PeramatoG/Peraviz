cmake_minimum_required(VERSION 3.21)

set(PERAVIZ_VERSION_FILE "${CMAKE_CURRENT_SOURCE_DIR}/../VERSION")
if(NOT EXISTS "${PERAVIZ_VERSION_FILE}")
    message(FATAL_ERROR "Peraviz VERSION file is missing: ${PERAVIZ_VERSION_FILE}")
endif()
file(READ "${PERAVIZ_VERSION_FILE}" _peraviz_version_raw)
string(STRIP "${_peraviz_version_raw}" PERAVIZ_VERSION)
if(NOT PERAVIZ_VERSION MATCHES "^[0-9]+\\.[0-9]+\\.[0-9]+$")
    message(FATAL_ERROR "Invalid Peraviz VERSION '${PERAVIZ_VERSION}'. Expected MAJOR.MINOR.PATCH without a leading v.")
endif()
project(PeravizNative VERSION "${PERAVIZ_VERSION}" LANGUAGES CXX)

set(PERAVIZ_APPLICATION_NAME "Peraviz")
set(PERAVIZ_DISPLAY_VERSION "${PERAVIZ_VERSION}")
configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/src/peraviz_build_version.h.in"
    "${CMAKE_CURRENT_BINARY_DIR}/generated/peraviz_build_version.h"
    @ONLY
)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
include(CTest)

set(GODOT_CPP_DIR "" CACHE PATH "Path to a local godot-cpp checkout")
option(PERAVIZ_FETCH_GODOT_CPP "Fetch godot-cpp automatically when GODOT_CPP_DIR is not provided" ON)
option(PERAVIZ_ENABLE_DMX "Enable DMX input (Art-Net RX)" ON)
option(PERAVIZ_ENABLE_MVR_XCHANGE "Enable MVR-xchange discovery" ON)

# Uses the standalone Peraviz repository root as the Godot project location.
set(PERAVIZ_GODOT_PROJECT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/.." CACHE PATH "Path to the Peraviz Godot project")

if(NOT TARGET godot-cpp)
    if(GODOT_CPP_DIR)
        if(EXISTS "${GODOT_CPP_DIR}/CMakeLists.txt")
            add_subdirectory("${GODOT_CPP_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/godot-cpp")
        else()
            message(FATAL_ERROR "GODOT_CPP_DIR was provided but no CMakeLists.txt was found: ${GODOT_CPP_DIR}")
        endif()
    elseif(PERAVIZ_FETCH_GODOT_CPP)
        include(FetchContent)
        FetchContent_Declare(
            godot-cpp
            GIT_REPOSITORY https://github.com/godotengine/godot-cpp.git
            GIT_TAG godot-4.2.2-stable
            GIT_SHALLOW TRUE
        )
        FetchContent_MakeAvailable(godot-cpp)
    else()
        message(FATAL_ERROR "godot-cpp is required. Set GODOT_CPP_DIR or enable PERAVIZ_FETCH_GODOT_CPP.")
    endif()
endif()

set(PERAVIZ_USING_VCPKG OFF)
if(CMAKE_TOOLCHAIN_FILE MATCHES "vcpkg.cmake" OR DEFINED VCPKG_TARGET_TRIPLET)
    set(PERAVIZ_USING_VCPKG ON)
endif()

if(PERAVIZ_USING_VCPKG)
    find_package(tinyxml2 CONFIG REQUIRED)
elseif(NOT tinyxml2_FOUND)
    find_package(tinyxml2 CONFIG QUIET)
endif()
if(NOT TARGET tinyxml2::tinyxml2)
    find_path(TINYXML2_INCLUDE_DIR tinyxml2.h)
    find_library(TINYXML2_LIBRARY tinyxml2)
    if(NOT TINYXML2_INCLUDE_DIR OR NOT TINYXML2_LIBRARY)
        message(FATAL_ERROR "tinyxml2 not found. Install development package or provide tinyxml2Config.cmake")
    endif()
    add_library(tinyxml2::tinyxml2 UNKNOWN IMPORTED)
    set_target_properties(tinyxml2::tinyxml2 PROPERTIES
        IMPORTED_LOCATION "${TINYXML2_LIBRARY}"
        INTERFACE_INCLUDE_DIRECTORIES "${TINYXML2_INCLUDE_DIR}"
    )
endif()

if(PERAVIZ_ENABLE_MVR_XCHANGE)
    find_package(mdns CONFIG REQUIRED)
endif()

if(PERAVIZ_USING_VCPKG)
    find_package(libzip CONFIG REQUIRED)
    if(NOT TARGET libzip::zip AND TARGET zip)
        add_library(libzip::zip ALIAS zip)
    endif()
else()
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(LIBZIP REQUIRED IMPORTED_TARGET libzip)
    if(NOT TARGET libzip::zip)
        add_library(libzip::zip INTERFACE IMPORTED)
        target_link_libraries(libzip::zip INTERFACE PkgConfig::LIBZIP)
    endif()
endif()

add_library(peraviz_native SHARED
    src/hello_world.cpp
    src/archive/zip_archive.cpp
    src/asset_cache.cpp
    src/coordinate_mapper.cpp
    src/mesh_3ds_loader.cpp
    src/peraviz_debug_runtime.cpp
    src/gdtf_scene_builder.cpp
    src/gdtf_runtime/gdtf_geometry_identity.cpp
    src/mvr_scene_loader.cpp
    src/peraviz_loader.cpp
    src/gobo_vectorizer.cpp
    src/register_types.cpp
    src/entry.cpp
    src/table_model/runtime_table_schema.cpp
    src/table_model/runtime_table.cpp
    src/table_model/perastage_table_schemas.cpp
)

if(PERAVIZ_ENABLE_DMX)
    target_sources(peraviz_native PRIVATE
        src/dmx/dmx_platform.cpp
        src/dmx/udp_socket.cpp
        src/dmx/artnet_dmx_parser.cpp
        src/dmx/dmx_universe_cache.cpp
        src/dmx/dmx_universe_decoder.cpp
        src/dmx/artnet_receiver.cpp
        src/dmx/gdtf_xml_reader.cpp
        src/dmx/gdtf_attribute_classifier.cpp
        src/dmx/gdtf_physical_ranges.cpp
        src/dmx/gdtf_gobo_catalog.cpp
        src/dmx/gdtf_control_offsets_resolver.cpp
        src/dmx/fixture_dmx_binding.cpp
        src/peraviz_dmx_receiver.cpp
        src/runtime/peraviz_visual_runtime.cpp
        src/runtime/color_science.cpp
        src/runtime/visual_frame_schema.cpp
        src/gdtf_runtime/compiled_gdtf_fixture.cpp
        src/gdtf_runtime/runtime_scene_compiler.cpp
        src/runtime/peraviz_visual_runtime_godot.cpp
    )
    target_compile_definitions(peraviz_native PRIVATE PERAVIZ_ENABLE_DMX=1)
    if(WIN32)
        target_link_libraries(peraviz_native PRIVATE ws2_32)
    endif()
endif()

if(PERAVIZ_ENABLE_MVR_XCHANGE)
    target_sources(peraviz_native PRIVATE
        src/mvrxchange/mvr_xchange_service_name.cpp
        src/mvrxchange/mvr_xchange_discovery.cpp
        src/mvrxchange/mvr_xchange_packet.cpp
        src/mvrxchange/mvr_xchange_local_station.cpp
        src/mvrxchange/mvr_xchange_transfer.cpp
        src/peraviz_mvr_xchange_client.cpp
    )
    target_compile_definitions(peraviz_native PRIVATE PERAVIZ_ENABLE_MVR_XCHANGE=1)
    target_link_libraries(peraviz_native PRIVATE mdns::mdns)
    if(WIN32)
        target_link_libraries(peraviz_native PRIVATE ws2_32 iphlpapi)
    endif()
endif()

target_include_directories(peraviz_native PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
    "${CMAKE_CURRENT_BINARY_DIR}/generated"
)

target_link_libraries(peraviz_native PRIVATE
    godot-cpp
    tinyxml2::tinyxml2
    libzip::zip
)

set_target_properties(peraviz_native PROPERTIES
    OUTPUT_NAME "peraviz_native"
)

if(WIN32)
    add_custom_target(peraviz_native_check_dependencies
        COMMAND ${CMAKE_COMMAND}
            "-DPERAVIZ_TARGET_FILE=$<TARGET_FILE:peraviz_native>"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/check_windows_dependencies.cmake"
        DEPENDS peraviz_native
        COMMENT "Checking peraviz_native for forbidden third-party runtime DLL dependencies"
        VERBATIM
    )
endif()

if(BUILD_TESTING)
    add_executable(peraviz_native_mvr_xchange_tests
        tests/mvr_xchange_service_name_test.cpp
        src/mvrxchange/mvr_xchange_service_name.cpp
        src/mvrxchange/mvr_xchange_packet.cpp
        src/mvrxchange/mvr_xchange_local_station.cpp
        src/mvrxchange/mvr_xchange_transfer.cpp
    )
    target_include_directories(peraviz_native_mvr_xchange_tests PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/src"
    )
    if(WIN32)
        target_link_libraries(peraviz_native_mvr_xchange_tests PRIVATE ws2_32)
    endif()
    add_test(NAME peraviz_native_mvr_xchange_tests COMMAND peraviz_native_mvr_xchange_tests)

    add_executable(peraviz_native_dmx_tests
        tests/gdtf_attribute_classifier_test.cpp
        src/archive/zip_archive.cpp
        src/dmx/gdtf_attribute_classifier.cpp
        src/dmx/gdtf_xml_reader.cpp
    )

    add_executable(peraviz_native_artnet_flow_tests
        tests/dmx_artnet_flow_test.cpp
        src/dmx/artnet_dmx_parser.cpp
        src/dmx/artnet_receiver.cpp
        src/dmx/dmx_platform.cpp
        src/dmx/dmx_universe_cache.cpp
        src/dmx/udp_socket.cpp
    )
    target_include_directories(peraviz_native_artnet_flow_tests PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/src"
    )
    if(WIN32)
        target_link_libraries(peraviz_native_artnet_flow_tests PRIVATE ws2_32)
    endif()
    add_test(NAME peraviz_native_artnet_flow_tests COMMAND peraviz_native_artnet_flow_tests)
    target_include_directories(peraviz_native_dmx_tests PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/src"
        "${CMAKE_CURRENT_BINARY_DIR}/generated"
    )
    target_link_libraries(peraviz_native_dmx_tests PRIVATE
        tinyxml2::tinyxml2
        libzip::zip
    )
    add_test(NAME peraviz_native_dmx_tests COMMAND peraviz_native_dmx_tests)

    add_executable(peraviz_native_dmx_e2e_tests
        tests/fixture_dmx_binding_e2e_test.cpp
        src/archive/zip_archive.cpp
        src/asset_cache.cpp
        src/dmx/gdtf_attribute_classifier.cpp
        src/dmx/gdtf_control_offsets_resolver.cpp
        src/dmx/gdtf_gobo_catalog.cpp
        src/dmx/gdtf_physical_ranges.cpp
        src/dmx/gdtf_xml_reader.cpp
        src/dmx/fixture_dmx_binding.cpp
    )
    target_include_directories(peraviz_native_dmx_e2e_tests PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/src"
        "${CMAKE_CURRENT_BINARY_DIR}/generated"
    )
    target_link_libraries(peraviz_native_dmx_e2e_tests PRIVATE
        tinyxml2::tinyxml2
        libzip::zip
    )
    add_test(NAME peraviz_native_dmx_e2e_tests COMMAND peraviz_native_dmx_e2e_tests)
    add_executable(peraviz_native_visual_runtime_tests
        tests/visual_runtime_core_test.cpp
        src/runtime/peraviz_visual_runtime.cpp
        src/runtime/color_science.cpp
        src/runtime/visual_frame_schema.cpp
        src/gdtf_runtime/compiled_gdtf_fixture.cpp
        src/gdtf_runtime/gdtf_geometry_identity.cpp
        src/gdtf_runtime/runtime_scene_compiler.cpp
        src/dmx/fixture_dmx_binding.cpp
        src/dmx/gdtf_attribute_classifier.cpp
        src/dmx/gdtf_control_offsets_resolver.cpp
        src/dmx/gdtf_xml_reader.cpp
        src/dmx/gdtf_physical_ranges.cpp
        src/dmx/gdtf_gobo_catalog.cpp
        src/archive/zip_archive.cpp
        src/asset_cache.cpp
    )
    target_include_directories(peraviz_native_visual_runtime_tests PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/src"
    )
    target_link_libraries(peraviz_native_visual_runtime_tests PRIVATE
        tinyxml2::tinyxml2
        libzip::zip
    )
    add_test(NAME peraviz_native_visual_runtime_tests COMMAND peraviz_native_visual_runtime_tests)


    add_executable(peraviz_native_gdtf_runtime_schema_tests
        tests/gdtf_runtime_schema_test.cpp
        src/gdtf_runtime/compiled_gdtf_fixture.cpp
        src/gdtf_runtime/gdtf_geometry_identity.cpp
        src/archive/zip_archive.cpp
        src/asset_cache.cpp
        src/dmx/gdtf_attribute_classifier.cpp
        src/dmx/gdtf_xml_reader.cpp
        src/runtime/visual_frame_schema.cpp
    )
    target_include_directories(peraviz_native_gdtf_runtime_schema_tests PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/src"
    )
    target_link_libraries(peraviz_native_gdtf_runtime_schema_tests PRIVATE
        tinyxml2::tinyxml2
        libzip::zip
    )
    add_test(NAME peraviz_native_gdtf_runtime_schema_tests COMMAND peraviz_native_gdtf_runtime_schema_tests)

    add_executable(peraviz_native_runtime_table_tests
        tests/runtime_table_model_test.cpp
        src/table_model/runtime_table_schema.cpp
        src/table_model/runtime_table.cpp
        src/table_model/perastage_table_schemas.cpp
    )
    target_include_directories(peraviz_native_runtime_table_tests PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/src"
    )
    add_test(NAME peraviz_native_runtime_table_tests COMMAND peraviz_native_runtime_table_tests)
endif()

if(PERAVIZ_GODOT_PROJECT_DIR)
    set(_peraviz_bin_dir "${PERAVIZ_GODOT_PROJECT_DIR}/bin")
    file(MAKE_DIRECTORY "${_peraviz_bin_dir}")

    set_target_properties(peraviz_native PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${_peraviz_bin_dir}"
        LIBRARY_OUTPUT_DIRECTORY "${_peraviz_bin_dir}"
    )

    foreach(config Debug Release RelWithDebInfo MinSizeRel)
        string(TOUPPER "${config}" config_upper)
        set_target_properties(peraviz_native PROPERTIES
            RUNTIME_OUTPUT_DIRECTORY_${config_upper} "${_peraviz_bin_dir}"
            LIBRARY_OUTPUT_DIRECTORY_${config_upper} "${_peraviz_bin_dir}"
        )
    endforeach()
endif()
