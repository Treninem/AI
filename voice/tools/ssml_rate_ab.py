from __future__ import annotations

import html
import re

import acoustic_benchmark as bench


# Second-pass benchmark candidate: preserve the natural model pitch and use
# only model-native tempo plus short pauses. The first A/B proved that Silero
# pitch="high" noticeably degrades the morning/playful female voice.
bench.SSML_PERSONA_PROFILES = {
    "persona_morning": {"rate": "medium", "pitch": "medium", "break_ms": 70},
    "persona_night": {"rate": "slow", "pitch": "medium", "break_ms": 120},
    "persona_playful": {"rate": "fast", "pitch": "medium", "break_ms": 35},
    "persona_serious": {"rate": "slow", "pitch": "medium", "break_ms": 90},
}


def build_ssml(text: str, sample_id: str) -> tuple[str, str]:
    clean = bench.prepare_for_speech(text)
    profile = bench.SSML_PERSONA_PROFILES[sample_id]
    escaped = html.escape(clean, quote=False)
    break_ms = int(profile.get("break_ms", 0))
    if break_ms > 0:
        escaped = re.sub(
            r"([.!?])\s+",
            rf'\1<break time="{break_ms}ms"/> ',
            escaped,
            count=1,
        )
    ssml = (
        '<speak><prosody rate="%s" pitch="medium">%s</prosody></speak>'
        % (profile["rate"], escaped)
    )
    return clean, ssml


bench.build_ssml = build_ssml


if __name__ == "__main__":
    raise SystemExit(bench.main())
