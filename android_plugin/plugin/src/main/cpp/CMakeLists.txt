cmake_minimum_required(VERSION 3.22)
project(aurorafox_runtime LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(aurorafox_runtime SHARED runtime_jni.cpp)

find_library(log-lib log)
target_link_libraries(aurorafox_runtime PRIVATE ${log-lib})

set(THIRD_PARTY_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party)

# Optional wasm3 integration. Run android_plugin/setup_native.ps1 first.
if(EXISTS "${THIRD_PARTY_DIR}/wasm3/source/CMakeLists.txt")
    set(BUILD_WASI simple CACHE STRING "" FORCE)
    add_subdirectory(${THIRD_PARTY_DIR}/wasm3/source ${CMAKE_BINARY_DIR}/wasm3 EXCLUDE_FROM_ALL)
    target_link_libraries(aurorafox_runtime PRIVATE m3)
    target_compile_definitions(aurorafox_runtime PRIVATE AURORAFOX_HAS_WASM3=1)
    target_include_directories(aurorafox_runtime PRIVATE ${THIRD_PARTY_DIR}/wasm3/source)
endif()

# llama.cpp / whisper.cpp source trees are fetched by setup_native.ps1.
# Their Android bindings are intentionally kept separate from this minimal JNI shim;
# capability remains false until a tested adapter is enabled.
if(EXISTS "${THIRD_PARTY_DIR}/llama.cpp/CMakeLists.txt")
    target_compile_definitions(aurorafox_runtime PRIVATE AURORAFOX_LLAMA_SOURCES_PRESENT=1)
endif()
if(EXISTS "${THIRD_PARTY_DIR}/whisper.cpp/CMakeLists.txt")
    target_compile_definitions(aurorafox_runtime PRIVATE AURORAFOX_WHISPER_SOURCES_PRESENT=1)
endif()
