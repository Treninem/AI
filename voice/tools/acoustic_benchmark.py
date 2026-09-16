from __future__ import annotations

import html
import json
import math
import re
import sys
import time
from pathlib import Path

import numpy as np
import soundfile as sf
import torch
import torchaudio
from transformers import pipeline
from utmos_pytorch import UTMOSScoreTorch

ROOT = Path(__file__).resolve().parents[2]
VOICE_PY = ROOT / "voice" / "python"
sys.path.insert(0, str(VOICE_PY))

from processor import AuroraVoiceProcessor, prepare_for_speech
from tts_engine import SileroEngine

CONFIG = json.loads((ROOT / "voice" / "config" / "voice_config.json").read_text(encoding="utf-8"))
OUT = ROOT / "artifacts" / "voice_acoustic"
OUT.mkdir(parents=True, exist_ok=True)

# This file is intentionally a candidate-only A/B experiment on the isolated
# voice-quality-targeted-prosody branch. Runtime code stays untouched until the
# candidate wins the quality gate.
CASES = [
    {
        "id": "persona_morning",
        "emotion": "happy",
        "text": "Доброе утро. Я уже здесь и готова спокойно помочь тебе начать день.",
        "candidate_text": "Доброе утро! Я уже здесь и готова спокойно помочь тебе начать день.",
        "mode": "punctuation",
    },
    {
        "id": "persona_night",
        "emotion": "sleepy",
        "text": "Доброй ночи. Давай закончим последние дела спокойно, без спешки и лишнего шума.",
        "mode": "ssml_slow",
    },
    {
        "id": "persona_playful",
        "emotion": "playful",
        "text": "Ну что, проверим эту идею? Мне уже интересно, какой вариант окажется самым удачным!",
        "candidate_text": "Ну что? Проверим эту идею! Мне уже интересно, какой вариант окажется самым удачным!",
        "mode": "punctuation",
    },
    {
        "id": "persona_serious",
        "emotion": "serious",
        "text": "Сейчас важно проверить факты, не торопиться с выводами и подтвердить результат.",
        "mode": "ssml_slow",
    },
]


def normalized(text: str) -> str:
    text = text.lower().replace("ё", "е")
    return " ".join(re.sub(r"[^0-9a-zа-я]+", " ", text).split())


def char_similarity(a: str, b: str) -> float:
    a = normalized(a)
    b = normalized(b)
    if not a or not b:
        return 0.0
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(cur[-1] + 1, prev[j] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return 1.0 - prev[-1] / max(len(a), len(b), 1)


def metrics(audio: np.ndarray, sr: int) -> dict:
    x = np.asarray(audio, dtype=np.float32).reshape(-1)
    peak = float(np.max(np.abs(x))) if x.size else 0.0
    rms = float(np.sqrt(np.mean(np.square(x), dtype=np.float64))) if x.size else 0.0
    return {
        "duration_sec": float(x.size / sr) if sr else 0.0,
        "peak": peak,
        "rms_dbfs": 20.0 * math.log10(max(rms, 1e-9)),
        "clipping_ratio": float(np.mean(np.abs(x) >= 0.999)) if x.size else 0.0,
    }


def resample_16k(audio: np.ndarray, sr: int) -> torch.Tensor:
    wav = torch.from_numpy(np.asarray(audio, dtype=np.float32)).reshape(1, -1)
    if sr != 16000:
        wav = torchaudio.functional.resample(wav, sr, 16000)
    return wav


def score_mos(model: UTMOSScoreTorch, audio: np.ndarray, sr: int) -> float:
    with torch.inference_mode():
        return float(model.score(resample_16k(audio, sr)).reshape(-1)[0].cpu())


def process(processor: AuroraVoiceProcessor, audio: np.ndarray, sr: int, emotion: str) -> np.ndarray:
    # Production currently keeps prosody_dsp disabled. Preserve exactly that
    # signal path here so A/B isolates model-native punctuation/SSML effects.
    return processor.process(
        audio,
        sr,
        emotion=emotion,
        intensity=0.65,
        mechanical_amount=float(CONFIG.get("mechanical_amount", 0.0)),
        pitch_shift=0.0,
        speed=1.0,
    )


def synth_plain(engine: SileroEngine, text: str) -> tuple[np.ndarray, int, float]:
    started = time.perf_counter()
    audio, sr = engine.synthesize(prepare_for_speech(text), speed=1.0)
    return np.asarray(audio, dtype=np.float32).reshape(-1), sr, time.perf_counter() - started


def synth_candidate(engine: SileroEngine, case: dict) -> tuple[np.ndarray, int, float, str]:
    mode = str(case["mode"])
    if mode == "punctuation":
        candidate = prepare_for_speech(str(case["candidate_text"]))
        audio, sr, elapsed = synth_plain(engine, candidate)
        return audio, sr, elapsed, candidate

    clean = prepare_for_speech(str(case["text"]))
    ssml = f'<speak><prosody rate="slow" pitch="medium">{html.escape(clean)}</prosody></speak>'
    sr = int(engine.config.get("sample_rate", 48000))
    started = time.perf_counter()
    with torch.inference_mode():
        audio = engine._load().apply_tts(
            ssml_text=ssml,
            speaker=engine.config.get("speaker", "xenia"),
            sample_rate=sr,
        )
    if isinstance(audio, torch.Tensor):
        audio = audio.detach().cpu().numpy()
    return np.asarray(audio, dtype=np.float32).reshape(-1), sr, time.perf_counter() - started, ssml


def waveform_delta(a: np.ndarray, b: np.ndarray) -> float:
    n = min(len(a), len(b))
    if n <= 0:
        return 0.0
    return float(np.sqrt(np.mean(np.square(a[:n] - b[:n]), dtype=np.float64)))


def main() -> int:
    torch.manual_seed(0)
    np.random.seed(0)
    torch.set_num_threads(4)

    engine = SileroEngine(CONFIG["silero"], "cpu")
    processor = AuroraVoiceProcessor(CONFIG["processor"])
    mos_model = UTMOSScoreTorch(device="cpu")
    asr = pipeline(
        "automatic-speech-recognition",
        model="openai/whisper-tiny",
        dtype=torch.float32,
        device=-1,
    )

    load_started = time.perf_counter()
    engine._load()
    model_load_sec = time.perf_counter() - load_started

    rows: list[dict] = []
    failures: list[str] = []

    for case in CASES:
        sample_id = str(case["id"])
        text = str(case["text"])
        emotion = str(case["emotion"])

        plain_raw, sr, plain_synth = synth_plain(engine, text)
        candidate_raw, candidate_sr, candidate_synth, candidate_form = synth_candidate(engine, case)
        if candidate_sr != sr:
            failures.append(f"{sample_id}: sample-rate mismatch {sr} vs {candidate_sr}")

        plain_started = time.perf_counter()
        plain = process(processor, plain_raw, sr, emotion)
        plain_dsp = time.perf_counter() - plain_started
        cand_started = time.perf_counter()
        candidate = process(processor, candidate_raw, sr, emotion)
        candidate_dsp = time.perf_counter() - cand_started

        sf.write(OUT / f"{sample_id}_plain.wav", plain, sr, subtype="PCM_16")
        sf.write(OUT / f"{sample_id}_candidate.wav", candidate, sr, subtype="PCM_16")

        plain_m = metrics(plain, sr)
        cand_m = metrics(candidate, sr)
        plain_mos = score_mos(mos_model, plain, sr)
        cand_mos = score_mos(mos_model, candidate, sr)
        recognized = str(asr(
            {"array": resample_16k(candidate, sr).squeeze(0).numpy(), "sampling_rate": 16000},
            generate_kwargs={"language": "ru", "task": "transcribe"},
        ).get("text", "")).strip()
        similarity = char_similarity(text, recognized)
        duration_ratio = cand_m["duration_sec"] / max(plain_m["duration_sec"], 1e-6)
        wave_delta = waveform_delta(plain, candidate)

        row = {
            "id": sample_id,
            "emotion": emotion,
            "mode": case["mode"],
            "source_text": text,
            "candidate_form": candidate_form,
            "recognized": recognized,
            "asr_similarity": similarity,
            "plain_utmos": plain_mos,
            "candidate_utmos": cand_mos,
            "utmos_delta": cand_mos - plain_mos,
            "plain_duration_sec": plain_m["duration_sec"],
            "candidate_duration_sec": cand_m["duration_sec"],
            "duration_ratio": duration_ratio,
            "waveform_delta_rms": wave_delta,
            "plain_synthesis_wall_sec": plain_synth,
            "candidate_synthesis_wall_sec": candidate_synth,
            "plain_processor_wall_sec": plain_dsp,
            "candidate_processor_wall_sec": candidate_dsp,
            "candidate_clipping_ratio": cand_m["clipping_ratio"],
            "candidate_peak": cand_m["peak"],
            "candidate_rms_dbfs": cand_m["rms_dbfs"],
        }
        rows.append(row)

        if cand_m["clipping_ratio"] > 0.0001:
            failures.append(f"{sample_id}: clipping {cand_m['clipping_ratio']:.6f}")
        if cand_mos < plain_mos - 0.08:
            failures.append(f"{sample_id}: UTMOS degraded {plain_mos:.3f}->{cand_mos:.3f}")
        if similarity < 0.92:
            failures.append(f"{sample_id}: ASR similarity {similarity:.3f}")
        if wave_delta < 0.005:
            failures.append(f"{sample_id}: candidate waveform is not meaningfully different")
        if case["mode"] == "ssml_slow" and duration_ratio < 1.10:
            failures.append(f"{sample_id}: slow prosody not measurable ({duration_ratio:.3f}x)")

    report = {
        "model_load_sec": model_load_sec,
        "candidate_policy": {
            "morning": "punctuation only",
            "night": "Silero SSML slow + medium pitch",
            "playful": "punctuation only",
            "serious": "Silero SSML slow + medium pitch",
            "runtime_changed": False,
        },
        "samples": rows,
        "summary": {
            "mean_plain_utmos": float(np.mean([r["plain_utmos"] for r in rows])),
            "mean_candidate_utmos": float(np.mean([r["candidate_utmos"] for r in rows])),
            "mean_candidate_synthesis_wall_sec": float(np.mean([r["candidate_synthesis_wall_sec"] for r in rows])),
            "max_candidate_clipping_ratio": float(max(r["candidate_clipping_ratio"] for r in rows)),
            "min_asr_similarity": float(min(r["asr_similarity"] for r in rows)),
            "failures": failures,
        },
    }
    (OUT / "targeted_prosody_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    print(json.dumps(report["summary"], ensure_ascii=False, indent=2))
    for row in rows:
        print(
            f"{row['id']}: {row['mode']} MOS={row['plain_utmos']:.3f}->{row['candidate_utmos']:.3f} "
            f"ASR={row['asr_similarity']:.3f} duration={row['duration_ratio']:.3f}x "
            f"wave={row['waveform_delta_rms']:.4f} clip={row['candidate_clipping_ratio']:.6f}"
        )

    if failures:
        print("TARGETED PROSODY GATE FAILED")
        for failure in failures:
            print(" -", failure)
        return 1
    print("TARGETED PROSODY GATE PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
