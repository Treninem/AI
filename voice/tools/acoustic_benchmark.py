from __future__ import annotations

import json
import math
import re
import sys
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
EMOTIONS = json.loads((ROOT / "voice" / "config" / "emotions.json").read_text(encoding="utf-8"))
OUT = ROOT / "artifacts" / "voice_acoustic"
OUT.mkdir(parents=True, exist_ok=True)

SAMPLES = [
    ("neutral_short", "neutral", 0.45, "Привет. Я Аврора Фокс. Чем я могу помочь тебе сегодня?"),
    ("neutral_numbers", "neutral", 0.45, "Температура 23 градуса. Давление 2,4 бара."),
    ("thinking_long", "thinking", 0.65, "Сейчас проверю данные, сравню несколько вариантов и спокойно объясню, какой результат получился."),
    ("success", "success", 0.70, "Готово! Проверка завершена успешно, ошибок не обнаружено."),
    ("warning", "warning", 0.70, "Внимание. Давление выше заданного значения, лучше проверить линию подачи воздуха."),
]
FEMALE_SPEAKERS = ("xenia", "baya", "kseniya")
SPEAKER_SWEEP_TEXTS = tuple(sample[3] for sample in SAMPLES)


def normalized(text: str) -> str:
    text = text.lower().replace("ё", "е")
    return " ".join(re.sub(r"[^0-9a-zа-я]+", " ", text).split())


def char_similarity(a: str, b: str) -> float:
    a = normalized(a)
    b = normalized(b)
    if not a or not b:
        return 0.0
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(current[-1] + 1, previous[j] + 1, previous[j - 1] + (ca != cb)))
        previous = current
    distance = previous[-1]
    return 1.0 - distance / max(len(a), len(b), 1)


def intelligibility_similarity(original: str, spoken_form: str, recognized: str) -> float:
    """Accept ASR's normal written form as well as the literal spoken form.

    Russian ASR commonly writes spoken number words back as digits. That is a
    successful round trip, not a loss of intelligibility, so compare against
    both the user-visible source and the normalized TTS form.
    """
    return max(
        char_similarity(original, recognized),
        char_similarity(spoken_form, recognized),
    )


def audio_metrics(audio: np.ndarray, sr: int) -> dict:
    x = np.asarray(audio, dtype=np.float32).reshape(-1)
    peak = float(np.max(np.abs(x))) if x.size else 0.0
    rms = float(np.sqrt(np.mean(np.square(x), dtype=np.float64))) if x.size else 0.0
    rms_db = 20.0 * math.log10(max(rms, 1e-9))
    clipping = float(np.mean(np.abs(x) >= 0.999)) if x.size else 0.0
    dc = float(abs(np.mean(x))) if x.size else 0.0
    edge_n = max(1, min(x.size // 8, int(sr * 0.01))) if x.size else 1
    edge_peak = float(max(np.max(np.abs(x[:edge_n])), np.max(np.abs(x[-edge_n:])))) if x.size else 0.0
    return {
        "duration_sec": float(x.size / sr) if sr else 0.0,
        "peak": peak,
        "rms_dbfs": rms_db,
        "clipping_ratio": clipping,
        "dc_offset": dc,
        "edge_peak_10ms": edge_peak,
    }


def resample_16k(audio: np.ndarray, sr: int) -> torch.Tensor:
    wav = torch.from_numpy(np.asarray(audio, dtype=np.float32)).reshape(1, -1)
    if sr != 16000:
        wav = torchaudio.functional.resample(wav, sr, 16000)
    return wav


def emotion_values(name: str, intensity: float) -> tuple[float, float, float]:
    profile = EMOTIONS.get(name, EMOTIONS["neutral"])
    power = max(0.0, min(1.0, intensity * float(CONFIG.get("emotionality", 0.55))))
    speed = float(CONFIG.get("speed", 1.0)) * (1.0 + (float(profile.get("speed", 1.0)) - 1.0) * power)
    pitch_factor = float(CONFIG.get("pitch", 1.0)) * (1.0 + (float(profile.get("pitch", 1.0)) - 1.0) * power)
    base_mech = float(CONFIG.get("mechanical_amount", 0.0))
    mech = base_mech + (float(profile.get("mechanical", base_mech)) - base_mech) * power
    return speed, pitch_factor - 1.0, mech


def score_mos(model: UTMOSScoreTorch, audio: np.ndarray, sr: int) -> float:
    with torch.inference_mode():
        return float(model.score(resample_16k(audio, sr)).reshape(-1)[0].cpu())


def synthesize_with_speaker(engine: SileroEngine, text: str, speaker: str) -> tuple[np.ndarray, int]:
    sr = int(engine.config.get("sample_rate", 48000))
    model = engine._load()
    with torch.inference_mode():
        audio = model.apply_tts(text=prepare_for_speech(text), speaker=speaker, sample_rate=sr)
    if isinstance(audio, torch.Tensor):
        audio = audio.detach().cpu().numpy()
    return np.asarray(audio, dtype=np.float32).reshape(-1), sr


def speaker_sweep(engine: SileroEngine, mos_model: UTMOSScoreTorch) -> dict:
    result: dict[str, dict] = {}
    for speaker in FEMALE_SPEAKERS:
        scores: list[float] = []
        try:
            preview: np.ndarray | None = None
            preview_sr = int(engine.config.get("sample_rate", 48000))
            for text in SPEAKER_SWEEP_TEXTS:
                audio, sr = synthesize_with_speaker(engine, text, speaker)
                preview = audio if preview is None else preview
                preview_sr = sr
                scores.append(score_mos(mos_model, audio, sr))
            if preview is not None:
                sf.write(OUT / f"speaker_{speaker}.wav", preview, preview_sr, subtype="PCM_16")
            result[speaker] = {
                "mean_utmos": float(np.mean(scores)),
                "min_utmos": float(np.min(scores)),
                "scores": scores,
            }
        except Exception as exc:
            result[speaker] = {"error": str(exc)}
    return result


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

    report = {"device": device, "samples": []}
    failures: list[str] = []
    processed_mos: list[float] = []
    raw_mos: list[float] = []
    similarities: list[float] = []

    for sample_id, emotion, intensity, text in SAMPLES:
        clean = prepare_for_speech(text)
        raw, sr = engine.synthesize(clean, emotion=emotion, intensity=intensity, speed=1.0)
        speed, pitch_shift, mech = emotion_values(emotion, intensity)
        final = processor.process(
            raw,
            sr,
            emotion=emotion,
            intensity=intensity,
            mechanical_amount=mech,
            pitch_shift=pitch_shift,
            speed=speed,
        )

        raw_path = OUT / f"{sample_id}_raw.wav"
        final_path = OUT / f"{sample_id}_aurora.wav"
        sf.write(raw_path, raw, sr, subtype="PCM_16")
        sf.write(final_path, final, sr, subtype="PCM_16")

        final_16 = resample_16k(final, sr)
        raw_score = score_mos(mos_model, raw, sr)
        final_score = score_mos(mos_model, final, sr)
        recognized = str(asr(
            {"array": final_16.squeeze(0).numpy(), "sampling_rate": 16000},
            generate_kwargs={"language": "ru", "task": "transcribe"},
        ).get("text", "")).strip()
        similarity = intelligibility_similarity(text, clean, recognized)
        metrics = audio_metrics(final, sr)

        raw_mos.append(raw_score)
        processed_mos.append(final_score)
        similarities.append(similarity)
        row = {
            "id": sample_id,
            "emotion": emotion,
            "intensity": intensity,
            "source_text": text,
            "spoken_text": clean,
            "recognized": recognized,
            "char_similarity": similarity,
            "raw_utmos": raw_score,
            "aurora_utmos": final_score,
            "mos_delta": final_score - raw_score,
            "speed": speed,
            "pitch_shift": pitch_shift,
            "mechanical": mech,
            **metrics,
        }
        report["samples"].append(row)

        if metrics["clipping_ratio"] > 0.0001:
            failures.append(f"{sample_id}: clipping {metrics['clipping_ratio']:.6f}")
        if not (-27.0 <= metrics["rms_dbfs"] <= -14.0):
            failures.append(f"{sample_id}: RMS {metrics['rms_dbfs']:.2f} dBFS")
        if metrics["dc_offset"] > 0.015:
            failures.append(f"{sample_id}: DC offset {metrics['dc_offset']:.4f}")
        if metrics["edge_peak_10ms"] > 0.35:
            failures.append(f"{sample_id}: hard edge {metrics['edge_peak_10ms']:.3f}")
        if final_score < 2.9:
            failures.append(f"{sample_id}: UTMOS {final_score:.3f}")
        if final_score + 0.18 < raw_score:
            failures.append(f"{sample_id}: processing degraded UTMOS {raw_score:.3f}->{final_score:.3f}")
        if similarity < 0.62:
            failures.append(f"{sample_id}: ASR similarity {similarity:.3f} recognized={recognized!r}")

    sweep = speaker_sweep(engine, mos_model)
    report["speaker_sweep"] = sweep
    configured_speaker = str(CONFIG["silero"].get("speaker", "xenia"))
    valid_sweep = {
        name: float(data["mean_utmos"])
        for name, data in sweep.items()
        if "mean_utmos" in data
    }
    if not valid_sweep:
        failures.append("speaker sweep produced no valid voice candidates")
    if configured_speaker in valid_sweep and valid_sweep:
        best_speaker, best_mos = max(valid_sweep.items(), key=lambda item: item[1])
        configured_mos = valid_sweep[configured_speaker]
        if best_speaker != configured_speaker and best_mos > configured_mos + 0.03:
            failures.append(
                f"speaker candidate {best_speaker} scores higher than {configured_speaker}: "
                f"{best_mos:.3f} vs {configured_mos:.3f}"
            )

    report["summary"] = {
        "raw_utmos_mean": float(np.mean(raw_mos)),
        "aurora_utmos_mean": float(np.mean(processed_mos)),
        "utmos_delta_mean": float(np.mean(processed_mos) - np.mean(raw_mos)),
        "asr_similarity_mean": float(np.mean(similarities)),
        "speaker_sweep": valid_sweep,
        "failures": failures,
    }
    (OUT / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report["summary"], ensure_ascii=False, indent=2))
    for row in report["samples"]:
        print(
            f"{row['id']}: MOS raw={row['raw_utmos']:.3f} aurora={row['aurora_utmos']:.3f} "
            f"ASR={row['char_similarity']:.3f} RMS={row['rms_dbfs']:.1f}dBFS peak={row['peak']:.3f}"
        )
    if failures:
        print("QUALITY GATE FAILED")
        for item in failures:
            print(" -", item)
        return 1
    print("QUALITY GATE PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
