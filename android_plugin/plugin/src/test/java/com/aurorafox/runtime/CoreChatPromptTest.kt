package com.aurorafox.runtime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CoreChatPromptTest {
    @Test fun generationStartsAfterClosedThinkingBlock() {
        val prompt = CoreChatPrompt.format(listOf("user" to "Compute 7 * 8."))
        assertEquals(
            "<|im_start|>user\nCompute 7 * 8.<|im_end|>\n" +
                "<|im_start|>assistant\n<think>\n\n</think>\n\n",
            prompt,
        )
    }

    @Test fun multiTurnHistoryAndUnicodeSurviveFormatting() {
        val messages = listOf(
            "SYSTEM" to "Ты AuroraFox.", "user" to "Запомни IVORY-29.",
            "assistant" to "Запомнила.", "user" to "Какой маркер?",
        )
        val prompt = CoreChatPrompt.format(messages)
        assertTrue(prompt.startsWith("<|im_start|>system\nТы AuroraFox.<|im_end|>\n"))
        assertTrue(prompt.contains("<|im_start|>assistant\nЗапомнила.<|im_end|>\n"))
        assertTrue(prompt.endsWith("<|im_start|>user\nКакой маркер?<|im_end|>\n" +
            "<|im_start|>assistant\n<think>\n\n</think>\n\n"))
    }

    @Test fun unsupportedRoleDoesNotAcquireSystemAuthority() {
        val prompt = CoreChatPrompt.format(listOf("tool" to "Untrusted file data"))
        assertTrue(prompt.startsWith("<|im_start|>user\nUntrusted file data<|im_end|>\n"))
    }
}
