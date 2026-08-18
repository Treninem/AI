cmake_minimum_required(VERSION 3.22)
project(aurorafox_runtime LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(aurorafox_runtime SHARED runtime_jni.cpp)

find_library(log-lib log)
target_link_libraries(aurorafox_runtime PRIVATE ${log-lib})

set(THIRD_PARTY_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party)

# Local LLM runtime: official llama.cpp source fetched by setup_native.ps1.
if(EXISTS "${THIRD_PARTY_DIR}/llama.cpp/CMakeLists.txt")
    set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
    set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
    set(LLAMA_CURL OFF CACHE BOOL "" FORCE)
    set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
    set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
    set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
    add_subdirectory(${THIRD_PARTY_DIR}/llama.cpp ${CMAKE_BINARY_DIR}/llama EXCLUDE_FROM_ALL)
    target_link_libraries(aurorafox_runtime PRIVATE llama)
    target_compile_definitions(aurorafox_runtime PRIVATE AURORAFOX_HAS_LLAMA=1)
    target_include_directories(aurorafox_runtime PRIVATE
        ${THIRD_PARTY_DIR}/llama.cpp/include
        ${THIRD_PARTY_DIR}/llama.cpp/ggml/include)
endif()

# Portable Android code sandbox.
if(EXISTS "${THIRD_PARTY_DIR}/wasm3/source/CMakeLists.txt")
    set(BUILD_WASI simple CACHE STRING "" FORCE)
    add_subdirectory(${THIRD_PARTY_DIR}/wasm3/source ${CMAKE_BINARY_DIR}/wasm3 EXCLUDE_FROM_ALL)
    target_link_libraries(aurorafox_runtime PRIVATE m3)
    target_compile_definitions(aurorafox_runtime PRIVATE AURORAFOX_HAS_WASM3=1)
    target_include_directories(aurorafox_runtime PRIVATE ${THIRD_PARTY_DIR}/wasm3/source)
endif()

# whisper.cpp is downloaded now; its tested JNI adapter is enabled separately.
if(EXISTS "${THIRD_PARTY_DIR}/whisper.cpp/CMakeLists.txt")
    target_compile_definitions(aurorafox_runtime PRIVATE AURORAFOX_WHISPER_SOURCES_PRESENT=1)
endif()
