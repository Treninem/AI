from __future__ import annotations

import html
import json
import re
import time
from pathlib import Path

import numpy as np
import soundfile as sf
import torch
from transformers import pipeline
from utmos_pytorch import UTMOSScoreTorch

from acoustic_benchmark import (
    CONFIG,
    PERSONA_SAMPLES,
    AuroraVoiceProcessor,
    SileroEngine,
    audio_metrics,
    intelligibility_similarity,
    prepare_for_speech,
    recognize,
    score_mos,
    waveform_delta_rms,
)

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "artifacts" / "voice_ssml_soft"
OUT.mkdir(parents=True, exist_ok=True)

# Selection derived from two measured A/B passes. Morning stays plain because
# every attempted SSML treatment reduced its naturalness. The other profiles
# only keep native model controls that preserved or improved UTMOS/ASR.
SELECTED_PROFILES = {
    "persona_morning": {"mode": "plain", "rate": None, "pitch": None, "break_ms": 0},
    "persona_night": {"mode": "ssml", "rate": "slow", "pitch": "medium", "break_ms": 110},
    "persona_playful": {"mode": "ssml", "rate": None, "pitch": None, "break_ms": 70},
    "persona_serious": {"mode": "ssml", "rate": "slow", "pitch": "medium", "break_ms": 0},
}


def _with_first_sentence_break(escaped: str, break_ms: int) -> str:
    if break_ms <= 0:
        return escaped
    match = re.match(r"^(.*?[.!?])\s+(.+)$", escaped)
    if not match:
        return escaped
    return f'{match.group(1)}<break time="{break_ms}ms"/>{match.group(2)}'


def build_selected_ssml(text: str, sample_id: str) -> tuple[str, str]:
    clean = prepare_for_speech(text)
    profile = SELECTED_PROFILES[sample_id]
    body = _with_first_sentence_break(html.escape(clean, quote=False), int(profile["break_ms"]))
    rate = profile["rate"]
    pitch = profile["pitch"]
    if rate or pitch:
        attrs: list[str] = []
        if rate:
            attrs.append(f'rate="{rate}"')
        if pitch:
            attrs.append(f'pitch="{pitch}"')
        body = f'<prosody {" ".join(attrs)}>{body}</prosody>'
    return clean, f"<speak>{body}</speak>"


def synthesize_plain(engine: SileroEngine, processor: AuroraVoiceProcessor, clean: str) -> tuple[np.ndarray, int, float, float]:
    started = time.perf_counter()
    raw, sr = engine.synthesize(clean, speed=1.0)
    synth_sec = time.perf_counter() - started
    process_started = time.perf_counter()
    final = processor.process(raw, sr, mechanical_amount=0.0, pitch_shift=0.0, speed=1.0)
    process_sec = time.perf_counter() - process_started
    return np.asarray(final, dtype=np.float32).reshape(-1), sr, synth_sec, process_sec


def synthesize_selected(engine: SileroEngine, processor: AuroraVoiceProcessor, text: str, sample_id: str) -> tuple[np.ndarray, int, str, str, float, float]:
    clean = prepare_for_speech(text)
    profile = SELECTED_PROFILES[sample_id]
    if profile["mode"] == "plain":
        audio, sr, synth_sec, process_sec = synthesize_plain(engine, processor, clean)
        return audio, sr, clean, clean, synth_sec, process_sec

    clean, ssml = build_selected_ssml(text, sample_id)
    sr = int(engine.config.get("sample_rate", 48000))
    model = engine._load()
    speaker = str(engine.config.get("speaker", "xenia"))
    started = time.perf_counter()
    with torch.inference_mode():
        raw = model.apply_tts(ssml_text=ssml, speaker=speaker, sample_rate=sr)
    synth_sec = time.perf_counter() - started
    if isinstance(raw, torch.Tensor):
        raw = raw.detach().cpu().numpy()
    process_started = time.perf_counter()
    final = processor.process(np.asarray(raw, dtype=np.float32), sr, mechanical_amount=0.0, pitch_shift=0.0, speed=1.0)
    process_sec = time.perf_counter() - process_started
    return np.asarray(final, dtype=np.float32).reshape(-1), sr, clean, ssml, synth_sec, process_sec


def main() -> int:
    torch.manual_seed(0)
    np.random.seed(0)
    torch.set_num_threads(4)

    device = "cuda" if torch.cuda.is_available() else "cpu"
    engine = SileroEngine(CONFIG["silero"], device)
    processor = AuroraVoiceProcessor(CONFIG["processor"])
    mos_model = UTMOSScoreTorch(device="cpu")
    asr = pipeline(
        "automatic-speech-recognition",
        model="openai/whisper-tiny",
        dtype=torch.float32,
        device=-1,
    )
    engine._load()

    failures: list[str] = []
    rows: dict[str, dict] = {}

    for sample_id, emotion, intensity, text in PERSONA_SAMPLES:
        clean = prepare_for_speech(text)
        plain, sr, plain_synth, plain_process = synthesize_plain(engine, processor, clean)
        candidate, candidate_sr, candidate_clean, ssml, candidate_synth, candidate_process = synthesize_selected(
            engine, processor, text, sample_id
        )
        if candidate_sr != sr:
            failures.append(f"{sample_id}: sample-rate mismatch {sr}!={candidate_sr}")

        plain_metrics = audio_metrics(plain, sr)
        cand_metrics = audio_metrics(candidate, candidate_sr)
        plain_mos = score_mos(mos_model, plain, sr)
        cand_mos = score_mos(mos_model, candidate, candidate_sr)
        plain_recognized = recognize(asr, plain, sr)
        cand_recognized = recognize(asr, candidate, candidate_sr)
        plain_asr = intelligibility_similarity(text, clean, plain_recognized)
        cand_asr = intelligibility_similarity(text, candidate_clean, cand_recognized)
        duration_ratio = float(cand_metrics["duration_sec"] / max(plain_metrics["duration_sec"], 1e-6))
        wave_delta = waveform_delta_rms(candidate, plain)
        mos_delta = cand_mos - plain_mos
        profile = SELECTED_PROFILES[sample_id]

        sf.write(OUT / f"{sample_id}_plain.wav", plain, sr, subtype="PCM_16")
        sf.write(OUT / f"{sample_id}_selected.wav", candidate, candidate_sr, subtype="PCM_16")

        rows[sample_id] = {
            "emotion": emotion,
            "intensity": intensity,
            "profile": profile,
            "render_input": ssml,
            "plain_utmos": plain_mos,
            "selected_utmos": cand_mos,
            "mos_delta": mos_delta,
            "plain_asr": plain_asr,
            "selected_asr": cand_asr,
            "plain_duration_sec": plain_metrics["duration_sec"],
            "selected_duration_sec": cand_metrics["duration_sec"],
            "duration_ratio": duration_ratio,
            "waveform_delta_rms": wave_delta,
            "plain_synthesis_sec": plain_synth,
            "selected_synthesis_sec": candidate_synth,
            "plain_processor_sec": plain_process,
            "selected_processor_sec": candidate_process,
            "clipping_ratio": cand_metrics["clipping_ratio"],
            "peak": cand_metrics["peak"],
            "rms_dbfs": cand_metrics["rms_dbfs"],
            "recognized": cand_recognized,
        }

        if cand_metrics["clipping_ratio"] > 0.0001:
            failures.append(f"{sample_id}: clipping {cand_metrics['clipping_ratio']:.6f}")
        if cand_mos < 2.9:
            failures.append(f"{sample_id}: UTMOS {cand_mos:.3f}")
        if cand_asr < 0.90 or cand_asr + 0.04 < plain_asr:
            failures.append(f"{sample_id}: ASR regression {plain_asr:.3f}->{cand_asr:.3f}")

        if profile["mode"] == "plain":
            if abs(mos_delta) > 0.02 or abs(duration_ratio - 1.0) > 0.01:
                failures.append(f"{sample_id}: plain selection was unexpectedly altered")
            continue

        if mos_delta < -0.10:
            failures.append(f"{sample_id}: UTMOS regression {plain_mos:.3f}->{cand_mos:.3f}")
        if wave_delta < 0.002:
            failures.append(f"{sample_id}: selected SSML did not materially alter waveform")

        if sample_id == "persona_playful":
            if mos_delta < 0.05:
                failures.append(f"{sample_id}: playful quality gain too small ({mos_delta:+.3f})")
            if not (0.80 <= duration_ratio <= 1.10):
                failures.append(f"{sample_id}: playful duration ratio {duration_ratio:.3f}x")
        elif sample_id == "persona_night":
            if not (1.05 <= duration_ratio <= 1.35):
                failures.append(f"{sample_id}: sleepy duration ratio {duration_ratio:.3f}x")
        elif sample_id == "persona_serious":
            if not (1.05 <= duration_ratio <= 1.35):
                failures.append(f"{sample_id}: serious duration ratio {duration_ratio:.3f}x")
            if mos_delta < 0.15:
                failures.append(f"{sample_id}: serious quality gain too small ({mos_delta:+.3f})")

    report = {
        "device": device,
        "speaker": str(CONFIG["silero"].get("speaker", "xenia")),
        "selection": SELECTED_PROFILES,
        "rows": rows,
        "failures": failures,
    }
    (OUT / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    for sample_id, row in rows.items():
        print(
            f"{sample_id}: mode={row['profile']['mode']} MOS {row['plain_utmos']:.3f}->{row['selected_utmos']:.3f} "
            f"({row['mos_delta']:+.3f}), ASR {row['plain_asr']:.3f}->{row['selected_asr']:.3f}, "
            f"duration={row['duration_ratio']:.3f}x, clipping={row['clipping_ratio']:.6f}"
        )
    if failures:
        print("SELECTED SSML GATE FAILED")
        for failure in failures:
            print(" -", failure)
        return 1
    print("SELECTED SSML GATE PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
