cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "sitemark_core")
project(${PROJECT_NAME} LANGUAGES CXX)

include("../../../../cargokit/cmake/cargokit.cmake")
apply_cargokit(${PROJECT_NAME} ../../../../../rust rust_lib_sitemark "")
