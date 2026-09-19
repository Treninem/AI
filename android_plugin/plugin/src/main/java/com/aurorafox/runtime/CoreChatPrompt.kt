package com.aurorafox.runtime

/** ChatML for the bundled Qwen3 Core, matching enable_thinking=false.
 * The empty thinking block is part of the prompt, never a fabricated answer.
 * Keep the mobile default aligned with the desktop reasoning_effort=none path.
 */
object CoreChatPrompt {
    fun format(messages: List<Pair<String, String>>): String = buildString {
        for ((rawRole, content) in messages) {
            val role = rawRole.lowercase().let {
                if (it in setOf("system", "user", "assistant")) it else "user"
            }
            append("<|im_start|>").append(role).append('\n')
            append(content).append("<|im_end|>\n")
        }
        append("<|im_start|>assistant\n<think>\n\n</think>\n\n")
    }
}
