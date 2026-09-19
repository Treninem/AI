from __future__ import annotations

import argparse
import difflib
import hashlib
import json
import math
import os
import re
import resource
import statistics
import time
from pathlib import Path

import numpy as np
import sherpa_onnx
import soundfile as sf

SUPERTONIC_MODEL = "sherpa-onnx-supertonic-3-tts-int8-2026-05-11"
EXPECTED_SUPERTONIC_ARCHIVE_BYTES = 128_774_318
EXPECTED_SUPERTONIC_ARCHIVE_SHA256 = "82fa96f91c4ef8abaae3a14a3f4153facf88bed821d1f7331cec2700f432c427"

SCENARIOS = {
    "morning": "Доброе утро. Сегодня всё получится. Я рядом и помогу спокойно начать день.",
    "night": "Доброй ночи. Все важные задачи сохранены, можно спокойно отдыхать до утра.",
    "playful": "Ну что, проверим идею? Я уже приготовила пару вариантов и один маленький сюрприз.",
    "serious": "Внимание. Перед изменением системы я сохраню состояние и проверю возможность отката.",
    "numbers_units": "Температура двадцать три целых пять десятых градуса Цельсия, загрузка семьдесят два процента, версия один точка три точка ноль точка ноль.",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--supertonic-dir", type=Path, required=True)
    parser.add_argument("--whisper-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--supertonic-archive", type=Path)
    parser.add_argument("--whisper-archive", type=Path)
    parser.add_argument("--threads", type=int, default=max(1, min(4, (os.cpu_count() or 2) - 1)))
    return parser.parse_args()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tree_bytes(root: Path) -> int:
    return sum(path.stat().st_size for path in root.rglob("*") if path.is_file())


def require_file(root: Path, name: str) -> str:
    path = root / name
    if not path.is_file():
        raise FileNotFoundError(f"required model file is missing: {path}")
    return str(path)


def normalize_text(text: str) -> str:
    text = text.lower().replace("ё", "е")
    text = re.sub(r"[^0-9a-zа-я]+", " ", text, flags=re.IGNORECASE)
    return re.sub(r"\s+", " ", text).strip()


def similarity(expected: str, actual: str) -> float:
    return difflib.SequenceMatcher(None, normalize_text(expected), normalize_text(actual)).ratio()


def max_rss_mib() -> float:
    value = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    # Linux reports KiB, macOS reports bytes. CI is Linux, but keep this portable.
    if value > 10_000_000:
        return float(value) / 1024.0 / 1024.0
    return float(value) / 1024.0


def build_tts(model_dir: Path, threads: int) -> sherpa_onnx.OfflineTts:
    config = sherpa_onnx.OfflineTtsConfig(
        model=sherpa_onnx.OfflineTtsModelConfig(
            supertonic=sherpa_onnx.OfflineTtsSupertonicModelConfig(
                duration_predictor=require_file(model_dir, "duration_predictor.int8.onnx"),
                text_encoder=require_file(model_dir, "text_encoder.int8.onnx"),
                vector_estimator=require_file(model_dir, "vector_estimator.int8.onnx"),
                vocoder=require_file(model_dir, "vocoder.int8.onnx"),
                tts_json=require_file(model_dir, "tts.json"),
                unicode_indexer=require_file(model_dir, "unicode_indexer.bin"),
                voice_style=require_file(model_dir, "voice.bin"),
            ),
            num_threads=threads,
            debug=False,
            provider="cpu",
        ),
        max_num_sentences=2,
        silence_scale=0.2,
    )
    return sherpa_onnx.OfflineTts(config)


def find_one(root: Path, fragments: tuple[str, ...], suffix: str) -> Path:
    matches = [
        path
        for path in root.rglob(f"*{suffix}")
        if all(fragment.lower() in path.name.lower() for fragment in fragments)
    ]
    if not matches:
        raise FileNotFoundError(f"cannot find {fragments} *{suffix} under {root}")
    return sorted(matches)[0]


def build_whisper(model_dir: Path, threads: int) -> sherpa_onnx.OfflineRecognizer:
    encoder = find_one(model_dir, ("encoder",), ".onnx")
    decoder = find_one(model_dir, ("decoder",), ".onnx")
    tokens = find_one(model_dir, ("tokens",), ".txt")
    return sherpa_onnx.OfflineRecognizer.from_whisper(
        encoder=str(encoder),
        decoder=str(decoder),
        tokens=str(tokens),
        language="ru",
        task="transcribe",
        num_threads=threads,
        debug=False,
        provider="cpu",
    )


def audio_metrics(samples: np.ndarray) -> dict[str, float | int]:
    if samples.size == 0:
        raise RuntimeError("TTS returned empty audio")
    abs_samples = np.abs(samples.astype(np.float64, copy=False))
    peak = float(np.max(abs_samples))
    rms = float(math.sqrt(float(np.mean(np.square(samples.astype(np.float64, copy=False))))))
    clipping_count = int(np.count_nonzero(abs_samples >= 0.999))
    return {
        "peak": peak,
        "rms": rms,
        "clipping_count": clipping_count,
        "clipping_fraction": clipping_count / float(samples.size),
    }


def transcribe(recognizer: sherpa_onnx.OfflineRecognizer, samples: np.ndarray, sample_rate: int) -> str:
    stream = recognizer.create_stream()
    stream.accept_waveform(sample_rate, samples.astype(np.float32, copy=False))
    recognizer.decode_stream(stream)
    result = stream.result
    return str(getattr(result, "text", "")).strip()


def main() -> None:
    args = parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    if args.supertonic_archive:
        archive_bytes = args.supertonic_archive.stat().st_size
        archive_sha = sha256_file(args.supertonic_archive)
        if archive_bytes != EXPECTED_SUPERTONIC_ARCHIVE_BYTES:
            raise RuntimeError(f"Supertonic archive bytes drifted: {archive_bytes}")
        if archive_sha != EXPECTED_SUPERTONIC_ARCHIVE_SHA256:
            raise RuntimeError(f"Supertonic archive SHA-256 drifted: {archive_sha}")

    started = time.perf_counter()
    tts = build_tts(args.supertonic_dir, args.threads)
    tts_load_seconds = time.perf_counter() - started
    num_speakers = int(tts.num_speakers)
    if num_speakers < 5:
        raise RuntimeError(f"Supertonic exposes only {num_speakers} speakers; F1-F5 cannot be measured")

    started = time.perf_counter()
    recognizer = build_whisper(args.whisper_dir, args.threads)
    whisper_load_seconds = time.perf_counter() - started

    rows: list[dict[str, object]] = []
    per_speaker: list[dict[str, object]] = []

    for sid in range(5):
        speaker_name = f"F{sid + 1}"
        speaker_dir = args.output_dir / speaker_name
        speaker_dir.mkdir(parents=True, exist_ok=True)
        speaker_rows: list[dict[str, object]] = []

        for scenario, text in SCENARIOS.items():
            gen = sherpa_onnx.GenerationConfig()
            gen.sid = sid
            gen.num_steps = 8
            gen.speed = 1.0
            gen.silence_scale = 0.2
            gen.extra["lang"] = "ru"

            synth_started = time.perf_counter()
            audio = tts.generate(text, gen)
            synth_seconds = time.perf_counter() - synth_started
            samples = np.asarray(audio.samples, dtype=np.float32)
            duration = samples.size / float(audio.sample_rate)
            if duration <= 0:
                raise RuntimeError(f"empty duration for {speaker_name}/{scenario}")
            wav_path = speaker_dir / f"{scenario}.wav"
            sf.write(wav_path, samples, audio.sample_rate, subtype="PCM_16")

            asr_started = time.perf_counter()
            transcript = transcribe(recognizer, samples, int(audio.sample_rate))
            asr_seconds = time.perf_counter() - asr_started
            metrics = audio_metrics(samples)
            row = {
                "speaker": speaker_name,
                "sid": sid,
                "scenario": scenario,
                "expected_text": text,
                "asr_text": transcript,
                "asr_similarity": similarity(text, transcript),
                "sample_rate": int(audio.sample_rate),
                "samples": int(samples.size),
                "duration_seconds": duration,
                "synthesis_seconds": synth_seconds,
                "rtf": synth_seconds / duration,
                "asr_seconds": asr_seconds,
                "wav": str(wav_path.relative_to(args.output_dir)),
                **metrics,
            }
            rows.append(row)
            speaker_rows.append(row)

        mean_similarity = statistics.mean(float(row["asr_similarity"]) for row in speaker_rows)
        mean_rtf = statistics.mean(float(row["rtf"]) for row in speaker_rows)
        max_peak = max(float(row["peak"]) for row in speaker_rows)
        clipping_total = sum(int(row["clipping_count"]) for row in speaker_rows)
        per_speaker.append(
            {
                "speaker": speaker_name,
                "sid": sid,
                "mean_asr_similarity": mean_similarity,
                "mean_rtf": mean_rtf,
                "max_peak": max_peak,
                "clipping_count": clipping_total,
                "hard_audio_gate": clipping_total == 0 and max_peak <= 1.0,
            }
        )

    eligible = [speaker for speaker in per_speaker if bool(speaker["hard_audio_gate"])]
    if not eligible:
        raise RuntimeError("No F1-F5 speaker passed the no-clipping audio gate")
    eligible.sort(key=lambda item: (-float(item["mean_asr_similarity"]), float(item["mean_rtf"]), int(item["sid"])))
    selected = eligible[0]

    report = {
        "schema": 1,
        "engine": "sherpa-onnx-supertonic-3",
        "sherpa_onnx_version": getattr(sherpa_onnx, "__version__", "unknown"),
        "language": "ru",
        "candidate_range": "F1-F5",
        "selection_rule": "pass no-clipping hard gate; highest mean Whisper similarity; lower mean RTF tie-break; lower sid final tie-break",
        "selected_candidate": selected,
        "speaker_summary": per_speaker,
        "samples": rows,
        "tts_load_seconds": tts_load_seconds,
        "whisper_load_seconds": whisper_load_seconds,
        "peak_rss_mib": max_rss_mib(),
        "supertonic_archive_bytes": args.supertonic_archive.stat().st_size if args.supertonic_archive else None,
        "supertonic_archive_sha256": sha256_file(args.supertonic_archive) if args.supertonic_archive else None,
        "supertonic_unpacked_bytes": tree_bytes(args.supertonic_dir),
        "whisper_archive_bytes": args.whisper_archive.stat().st_size if args.whisper_archive else None,
        "whisper_archive_sha256": sha256_file(args.whisper_archive) if args.whisper_archive else None,
        "whisper_unpacked_bytes": tree_bytes(args.whisper_dir),
        "threads": args.threads,
    }
    report_path = args.output_dir / "report.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    print(
        "AURORA_SUPERTONIC_CANDIDATE_BENCHMARK_OK "
        f"selected={selected['speaker']} similarity={selected['mean_asr_similarity']:.4f} "
        f"rtf={selected['mean_rtf']:.4f} peak_rss_mib={report['peak_rss_mib']:.1f}"
    )


if __name__ == "__main__":
    main()
