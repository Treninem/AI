
V15_VOICE_STARTUP_CLAIM_TEST_EXTENSION_2026_10_12: OWNED_PATHS additionally include tests/voice_smoke.gd (the already-executed native Godot voice CI smoke); use an isolated VoiceManager subclass to check true/false/reconnect startup-greeting behavior without starting recording or a live voice backend. No shared workflow changes. This extension is declared before editing that file.
