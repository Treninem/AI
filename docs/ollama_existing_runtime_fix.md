# Existing Ollama reuse

AuroraFox must reuse an already-running system Ollama at `127.0.0.1:11434` and must not assume that the recommended `qwen3:8b` model is installed.

Runtime behavior:

1. Query `/api/tags`.
2. Keep the configured model when it is installed and chat-capable.
3. Otherwise select the best available non-embedding chat model.
4. Do not select embedding-only models for chat.
5. If a selected model disappears and Ollama returns `404 model not found`, refresh `/api/tags` and retry once with a valid installed chat model.
6. Download recommended models only when the user explicitly starts model preparation.
