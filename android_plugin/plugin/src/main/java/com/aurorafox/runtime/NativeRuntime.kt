package com.aurorafox.runtime

class NativeRuntime {
    private val loaded: Boolean

    init {
        loaded = try {
            System.loadLibrary("aurorafox_runtime")
            true
        } catch (_: Throwable) {
            false
        }
    }

    fun isLoaded(): Boolean = loaded
    fun hasLlama(): Boolean = loaded && nativeHasLlama()
    fun hasWhisper(): Boolean = loaded && nativeHasWhisper()
    fun hasWasm(): Boolean = loaded && nativeHasWasm()

    fun chat(modelPath: String, messagesJson: String, optionsJson: String): String =
        nativeChat(modelPath, messagesJson, optionsJson)

    fun transcribe(modelPath: String, audioPath: String, language: String): String =
        nativeTranscribe(modelPath, audioPath, language)

    fun runWasm(modulePath: String, workspacePath: String, args: Array<String>): String =
        nativeRunWasm(modulePath, workspacePath, args)

    private external fun nativeHasLlama(): Boolean
    private external fun nativeHasWhisper(): Boolean
    private external fun nativeHasWasm(): Boolean
    private external fun nativeChat(modelPath: String, messagesJson: String, optionsJson: String): String
    private external fun nativeTranscribe(modelPath: String, audioPath: String, language: String): String
    private external fun nativeRunWasm(modulePath: String, workspacePath: String, args: Array<String>): String
}
