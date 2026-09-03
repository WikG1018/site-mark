cmake_minimum_required(VERSION 3.5.0)
project(sitemark_native)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(DEFINED PACKAGE_FIND_FILE)
  include(${PACKAGE_FIND_FILE})
endif()

add_library(sitemark_core STATIC IMPORTED)
set_target_properties(sitemark_core PROPERTIES
  IMPORTED_LOCATION "${CMAKE_CURRENT_SOURCE_DIR}/../libs/${OHOS_ARCH}/libsitemark_core.a")

add_library(sitemark_native SHARED napi_init.cpp)
target_include_directories(sitemark_native PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
# iana_time_zone (pulled in by chrono via the NAS SFTP/SMB stack) resolves
# the zone through OH_TimeService_GetTimeZone; the static Rust archive
# therefore needs the NDK time-service stub at final link.
target_link_libraries(sitemark_native PUBLIC sitemark_core libace_napi.z.so
  libtime_service_ndk.so)
