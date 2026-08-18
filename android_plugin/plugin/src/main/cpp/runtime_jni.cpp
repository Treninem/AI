#include <jni.h>
#include <algorithm>
#include <fstream>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

#ifdef AURORAFOX_HAS_LLAMA
#include "llama.h"
#endif

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
    out.reserve(s.size() + 32);
    for (unsigned char c : s) {
        switch (c) {
            case '\\': out += "\\\\"; break;
            case '"': out += "\\\""; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (c < 0x20) {
                    char buf[8];
                    snprintf(buf, sizeof(buf), "\\u%04x", c);
                    out += buf;
                } else {
                    out += static_cast<char>(c);
                }
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

static int extract_json_int(const std::string &json, const std::string &key, int fallback) {
    const std::string needle = "\"" + key + "\"";
    size_t pos = json.find(needle);
    if (pos == std::string::npos) return fallback;
    pos = json.find(':', pos + needle.size());
    if (pos == std::string::npos) return fallback;
    ++pos;
    while (pos < json.size() && (json[pos] == ' ' || json[pos] == '\t')) ++pos;
    try {
        return std::stoi(json.substr(pos));
    } catch (...) {
        return fallback;
    }
}

#ifdef AURORAFOX_HAS_LLAMA
static std::once_flag g_backend_once;
static std::mutex g_llama_mutex;
static llama_model *g_model = nullptr;
static std::string g_model_path;

static void init_llama_backends() {
    ggml_backend_load_all();
}

static llama_model *ensure_llama_model(const std::string &path, std::string &error) {
    std::call_once(g_backend_once, init_llama_backends);
    if (g_model && g_model_path == path) return g_model;
    if (g_model) {
        llama_model_free(g_model);
        g_model = nullptr;
        g_model_path.clear();
    }
    llama_model_params params = llama_model_default_params();
    params.n_gpu_layers = 0;
    g_model = llama_model_load_from_file(path.c_str(), params);
    if (!g_model) {
        error = "Unable to load GGUF model";
        return nullptr;
    }
    g_model_path = path;
    return g_model;
}

static std::string llama_generate(const std::string &model_path, const std::string &prompt, int n_predict) {
    std::lock_guard<std::mutex> lock(g_llama_mutex);
    std::string error;
    llama_model *model = ensure_llama_model(model_path, error);
    if (!model) return "{\"ok\":false,\"error\":\"" + json_escape(error) + "\"}";

    const llama_vocab *vocab = llama_model_get_vocab(model);
    int n_prompt = -llama_tokenize(vocab, prompt.c_str(), static_cast<int32_t>(prompt.size()), nullptr, 0, true, true);
    if (n_prompt <= 0) return R"({"ok":false,"error":"Failed to measure prompt tokens"})";

    n_predict = std::clamp(n_predict, 16, 1024);
    const int trained_ctx = std::max(1024, llama_model_n_ctx_train(model));
    const int requested_ctx = n_prompt + n_predict + 32;
    const int context_size = std::min(std::max(requested_ctx, 1024), std::min(trained_ctx, 8192));
    if (n_prompt + 8 >= context_size) {
        return R"({"ok":false,"error":"Prompt is too large for the mobile context window"})";
    }

    std::vector<llama_token> prompt_tokens(static_cast<size_t>(n_prompt));
    const int tokenized = llama_tokenize(vocab, prompt.c_str(), static_cast<int32_t>(prompt.size()), prompt_tokens.data(), static_cast<int32_t>(prompt_tokens.size()), true, true);
    if (tokenized < 0) return R"({"ok":false,"error":"Failed to tokenize prompt"})";

    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = static_cast<uint32_t>(context_size);
    ctx_params.n_batch = static_cast<uint32_t>(std::min(n_prompt, 512));
    ctx_params.n_ubatch = ctx_params.n_batch;
    ctx_params.n_threads = 4;
    ctx_params.n_threads_batch = 4;
    ctx_params.no_perf = true;

    llama_context *ctx = llama_init_from_model(model, ctx_params);
    if (!ctx) return R"({"ok":false,"error":"Failed to create llama context"})";

    llama_sampler_chain_params chain_params = llama_sampler_chain_default_params();
    chain_params.no_perf = true;
    llama_sampler *sampler = llama_sampler_chain_init(chain_params);
    llama_sampler_chain_add(sampler, llama_sampler_init_greedy());

    int pos = 0;
    for (int offset = 0; offset < n_prompt; offset += 512) {
        const int count = std::min(512, n_prompt - offset);
        llama_batch batch = llama_batch_get_one(prompt_tokens.data() + offset, count);
        if (llama_decode(ctx, batch) != 0) {
            llama_sampler_free(sampler);
            llama_free(ctx);
            return R"({"ok":false,"error":"Prompt evaluation failed"})";
        }
        pos += count;
    }

    std::string generated;
    generated.reserve(static_cast<size_t>(n_predict) * 4);
    for (int i = 0; i < n_predict && pos < context_size - 1; ++i) {
        const llama_token token = llama_sampler_sample(sampler, ctx, -1);
        if (llama_vocab_is_eog(vocab, token)) break;

        char piece[512];
        const int n = llama_token_to_piece(vocab, token, piece, sizeof(piece), 0, true);
        if (n > 0) generated.append(piece, static_cast<size_t>(n));

        llama_token next = token;
        llama_batch batch = llama_batch_get_one(&next, 1);
        if (llama_decode(ctx, batch) != 0) break;
        ++pos;
    }

    llama_sampler_free(sampler);
    llama_free(ctx);
    return "{\"ok\":true,\"content\":\"" + json_escape(generated) + "\",\"runtime\":\"llama.cpp\"}";
}
#endif

extern "C" JNIEXPORT jboolean JNICALL
Java_com_aurorafox_runtime_NativeRuntime_nativeHasLlama(JNIEnv *, jobject) {
#ifdef AURORAFOX_HAS_LLAMA
    return JNI_TRUE;
#else
    return JNI_FALSE;
#endif
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
        JNIEnv *env, jobject, jstring modelPath, jstring prompt, jstring optionsJson) {
#ifndef AURORAFOX_HAS_LLAMA
    return to_jstring(env, R"({"ok":false,"error":"llama.cpp runtime is not enabled in this build"})");
#else
    const std::string model_path = from_jstring(env, modelPath);
    const std::string prompt_text = from_jstring(env, prompt);
    const std::string options = from_jstring(env, optionsJson);
    if (model_path.empty() || prompt_text.empty()) return to_jstring(env, R"({"ok":false,"error":"Model path or prompt is empty"})");
    int n_predict = extract_json_int(options, "max_tokens", extract_json_int(options, "num_predict", 384));
    return to_jstring(env, llama_generate(model_path, prompt_text, n_predict));
#endif
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
    if (!input) return to_jstring(env, R"({"ok":false,"error":"Cannot open WASM module"})");
    std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
    if (bytes.empty()) return to_jstring(env, R"({"ok":false,"error":"Empty WASM module"})");
    if (bytes.size() > 64 * 1024 * 1024) return to_jstring(env, R"({"ok":false,"error":"WASM module exceeds 64 MiB limit"})");

    IM3Environment environment = m3_NewEnvironment();
    if (!environment) return to_jstring(env, R"({"ok":false,"error":"m3_NewEnvironment failed"})");
    IM3Runtime runtime = m3_NewRuntime(environment, 256 * 1024, nullptr);
    if (!runtime) {
        m3_FreeEnvironment(environment);
        return to_jstring(env, R"({"ok":false,"error":"m3_NewRuntime failed"})");
    }

    IM3Module module = nullptr;
    M3Result result = m3_ParseModule(environment, &module, bytes.data(), static_cast<uint32_t>(bytes.size()));
    if (result) {
        std::string err = std::string("WASM parse failed: ") + result;
        m3_FreeRuntime(runtime); m3_FreeEnvironment(environment);
        return to_jstring(env, "{\"ok\":false,\"error\":\"" + json_escape(err) + "\"}");
    }
    result = m3_LoadModule(runtime, module);
    if (result) {
        std::string err = std::string("WASM load failed: ") + result;
        m3_FreeRuntime(runtime); m3_FreeEnvironment(environment);
        return to_jstring(env, "{\"ok\":false,\"error\":\"" + json_escape(err) + "\"}");
    }
#ifdef AURORAFOX_HAS_WASI
    m3_LinkWASI(module);
#endif
    IM3Function function = nullptr;
    result = m3_FindFunction(&function, runtime, "_start");
    if (result) result = m3_FindFunction(&function, runtime, "main");
    if (result || !function) {
        m3_FreeRuntime(runtime); m3_FreeEnvironment(environment);
        return to_jstring(env, R"({"ok":false,"error":"No _start or main export in WASM module"})");
    }
    (void) workspace;
    (void) argsArray;
    result = m3_CallV(function);
    if (result) {
        std::string err = std::string("WASM execution failed: ") + result;
        m3_FreeRuntime(runtime); m3_FreeEnvironment(environment);
        return to_jstring(env, "{\"ok\":false,\"error\":\"" + json_escape(err) + "\"}");
    }
    m3_FreeRuntime(runtime); m3_FreeEnvironment(environment);
    return to_jstring(env, R"({"ok":true,"code":0,"output":"WASM module completed","runtime":"wasm3","network":"none"})");
#endif
}
