#include <jni.h>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#ifdef AURORAFOX_HAS_WASM3
#include "wasm3.h"
#include "m3_env.h"
#if __has_include("m3_api_wasi.h")
#include "m3_api_wasi.h"
#define AURORAFOX_HAS_WASI 1
#endif
#endif

static std::string json_escape(const std::string &s) {
    std::string out;
    out.reserve(s.size() + 16);
    for (char c : s) {
        switch (c) {
            case '\\': out += "\\\\"; break;
            case '"': out += "\\\""; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default: out += c; break;
        }
    }
    return out;
}

static jstring to_jstring(JNIEnv *env, const std::string &value) {
    return env->NewStringUTF(value.c_str());
}

static std::string from_jstring(JNIEnv *env, jstring value) {
    if (!value) return {};
    const char *chars = env->GetStringUTFChars(value, nullptr);
    std::string out = chars ? chars : "";
    if (chars) env->ReleaseStringUTFChars(value, chars);
    return out;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aurorafox_runtime_NativeRuntime_nativeHasLlama(JNIEnv *, jobject) {
    return JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aurorafox_runtime_NativeRuntime_nativeHasWhisper(JNIEnv *, jobject) {
    return JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aurorafox_runtime_NativeRuntime_nativeHasWasm(JNIEnv *, jobject) {
#ifdef AURORAFOX_HAS_WASM3
    return JNI_TRUE;
#else
    return JNI_FALSE;
#endif
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_aurorafox_runtime_NativeRuntime_nativeChat(
    JNIEnv *env, jobject, jstring, jstring, jstring) {
    return to_jstring(env, R"({"ok":false,"error":"llama.cpp JNI adapter is not enabled in this build"})");
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_aurorafox_runtime_NativeRuntime_nativeTranscribe(
    JNIEnv *env, jobject, jstring, jstring, jstring) {
    return to_jstring(env, R"({"ok":false,"error":"whisper.cpp JNI adapter is not enabled in this build"})");
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_aurorafox_runtime_NativeRuntime_nativeRunWasm(
    JNIEnv *env, jobject, jstring modulePath, jstring workspacePath, jobjectArray argsArray) {
#ifndef AURORAFOX_HAS_WASM3
    return to_jstring(env, R"({"ok":false,"error":"WASM runtime is not enabled in this build"})");
#else
    const std::string module_path = from_jstring(env, modulePath);
    const std::string workspace = from_jstring(env, workspacePath);

    std::ifstream input(module_path, std::ios::binary);
    if (!input) {
        return to_jstring(env, R"({"ok":false,"error":"Cannot open WASM module"})");
    }
    std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
    if (bytes.empty()) {
        return to_jstring(env, R"({"ok":false,"error":"Empty WASM module"})");
    }
    if (bytes.size() > 64 * 1024 * 1024) {
        return to_jstring(env, R"({"ok":false,"error":"WASM module exceeds 64 MiB limit"})");
    }

    IM3Environment environment = m3_NewEnvironment();
    if (!environment) {
        return to_jstring(env, R"({"ok":false,"error":"m3_NewEnvironment failed"})");
    }
    IM3Runtime runtime = m3_NewRuntime(environment, 256 * 1024, nullptr);
    if (!runtime) {
        m3_FreeEnvironment(environment);
        return to_jstring(env, R"({"ok":false,"error":"m3_NewRuntime failed"})");
    }

    IM3Module module = nullptr;
    M3Result result = m3_ParseModule(environment, &module, bytes.data(), static_cast<uint32_t>(bytes.size()));
    if (result) {
        std::string err = std::string("WASM parse failed: ") + result;
        m3_FreeRuntime(runtime);
        m3_FreeEnvironment(environment);
        return to_jstring(env, "{\"ok\":false,\"error\":\"" + json_escape(err) + "\"}");
    }
    result = m3_LoadModule(runtime, module);
    if (result) {
        std::string err = std::string("WASM load failed: ") + result;
        m3_FreeRuntime(runtime);
        m3_FreeEnvironment(environment);
        return to_jstring(env, "{\"ok\":false,\"error\":\"" + json_escape(err) + "\"}");
    }

#ifdef AURORAFOX_HAS_WASI
    // wasm3 WASI exposes only the capabilities explicitly linked by the runtime.
    // No Android shell, package manager, contacts, camera, or arbitrary host filesystem is exposed here.
    m3_LinkWASI(module);
#endif

    IM3Function function = nullptr;
    result = m3_FindFunction(&function, runtime, "_start");
    if (result) {
        result = m3_FindFunction(&function, runtime, "main");
    }
    if (result || !function) {
        m3_FreeRuntime(runtime);
        m3_FreeEnvironment(environment);
        return to_jstring(env, R"({"ok":false,"error":"No _start or main export in WASM module"})");
    }

    // Arguments are intentionally not injected into WASI yet; the first safe implementation
    // runs deterministic modules without host privileges. File I/O remains handled by Godot.
    (void) workspace;
    (void) argsArray;
    result = m3_CallV(function);
    if (result) {
        std::string err = std::string("WASM execution failed: ") + result;
        m3_FreeRuntime(runtime);
        m3_FreeEnvironment(environment);
        return to_jstring(env, "{\"ok\":false,\"error\":\"" + json_escape(err) + "\"}");
    }

    m3_FreeRuntime(runtime);
    m3_FreeEnvironment(environment);
    return to_jstring(env, R"({"ok":true,"code":0,"output":"WASM module completed","runtime":"wasm3","network":"none"})");
#endif
}
