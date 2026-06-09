if(NOT DEFINED PERAVIZ_TARGET_FILE OR PERAVIZ_TARGET_FILE STREQUAL "")
    message(FATAL_ERROR "PERAVIZ_TARGET_FILE must point to peraviz_native.dll")
endif()

if(NOT EXISTS "${PERAVIZ_TARGET_FILE}")
    message(FATAL_ERROR "Native extension was not found: ${PERAVIZ_TARGET_FILE}")
endif()

find_program(PERAVIZ_DUMPBIN dumpbin)
if(NOT PERAVIZ_DUMPBIN)
    message(FATAL_ERROR "dumpbin was not found. Run this check from a Visual Studio Developer Command Prompt.")
endif()

execute_process(
    COMMAND "${PERAVIZ_DUMPBIN}" /DEPENDENTS "${PERAVIZ_TARGET_FILE}"
    RESULT_VARIABLE _peraviz_dumpbin_result
    OUTPUT_VARIABLE _peraviz_dumpbin_output
    ERROR_VARIABLE _peraviz_dumpbin_error
)

if(NOT _peraviz_dumpbin_result EQUAL 0)
    message(FATAL_ERROR "dumpbin failed with exit code ${_peraviz_dumpbin_result}: ${_peraviz_dumpbin_error}")
endif()

string(TOLOWER "${_peraviz_dumpbin_output}" _peraviz_dumpbin_output_lower)

set(_peraviz_forbidden_dependencies
    "zip.dll"
    "zlib1.dll"
    "zlibd1.dll"
    "tinyxml2.dll"
    "pcre2-16.dll"
    "pcre2-16d.dll"
    "jvm.dll"
)

foreach(_peraviz_dependency IN LISTS _peraviz_forbidden_dependencies)
    if(_peraviz_dumpbin_output_lower MATCHES "(^|[\r\n ]+)${_peraviz_dependency}([\r\n ]+|$)")
        message(FATAL_ERROR "${PERAVIZ_TARGET_FILE} depends on forbidden runtime DLL ${_peraviz_dependency}. Rebuild with the x64-windows-static vcpkg triplet.")
    endif()
endforeach()

if(_peraviz_dumpbin_output_lower MATCHES "(^|[\r\n ]+)wxbase[^\r\n ]*\\.dll([\r\n ]+|$)")
    message(FATAL_ERROR "${PERAVIZ_TARGET_FILE} depends on a forbidden wxWidgets runtime DLL. wxWidgets is not a native dependency of Peraviz.")
endif()

if(_peraviz_dumpbin_output_lower MATCHES "(^|[\r\n ]+)wxmsw[^\r\n ]*\\.dll([\r\n ]+|$)")
    message(FATAL_ERROR "${PERAVIZ_TARGET_FILE} depends on a forbidden wxWidgets runtime DLL. wxWidgets is not a native dependency of Peraviz.")
endif()

message(STATUS "No forbidden third-party runtime DLL dependencies were found for ${PERAVIZ_TARGET_FILE}.")
