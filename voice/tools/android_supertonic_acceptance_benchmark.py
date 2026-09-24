from __future__ import annotations

import argparse
import json
import statistics
import time
from pathlib import Path

import numpy as np
import sherpa_onnx
import soundfile as sf

from android_supertonic_candidate_benchmark import (
    EXPECTED_SUPERTONIC_ARCHIVE_BYTES,
    EXPECTED_SUPERTONIC_ARCHIVE_SHA256,
    audio_metrics,
    build_tts,
    find_one,
    max_rss_mib,
    sha256_file,
    similarity,
    tree_bytes,
)

EXPECTED_WHISPER_ARCHIVE_BYTES = 116_204_861
EXPECTED_WHISPER_ARCHIVE_SHA256 = "c46116994e539aa165266d96b325252728429c12535eb9d8b6a2b10f129e66b1"

SCENARIOS = [
    ("neutral_ru", "ru", "ru", "AuroraFox работает локально и готова спокойно помочь с задачей."),
    ("morning_ru", "ru", "ru", "Доброе утро. Сегодня всё получится. Я рядом и помогу спокойно начать день."),
    ("night_ru", "ru", "ru", "Доброй ночи. Все важные задачи сохранены, можно спокойно отдыхать до утра."),
    ("playful_ru", "ru", "ru", "Ну что, проверим идею? Я уже приготовила пару вариантов и один маленький сюрприз."),
    ("serious_ru", "ru", "ru", "Внимание. Перед изменением системы я сохраню состояние и проверю возможность отката."),
    ("calm_ru", "ru", "ru", "Спокойно. Я проверю каждый шаг по очереди и сообщу только подтверждённый результат."),
    (
        "long_neutral_ru",
        "ru",
        "ru",
        "AuroraFox — локальный помощник. Она может работать с файлами, знаниями и памятью без обязательного облачного сервиса. "
        "Перед важным действием система проверяет разрешения, сохраняет состояние и оставляет возможность безопасного отката. "
        "Если отдельный инструмент недоступен, основной локальный чат должен продолжать работать без потери пользовательских данных.",
    ),
    (
        "numbers_ru",
        "ru",
        "ru",
        "Температура двадцать три целых пять десятых градуса Цельсия, загрузка семьдесят два процента, версия один точка три точка ноль точка ноль.",
    ),
    ("dates_ru", "ru", "ru", "Сегодня семнадцатое сентября две тысячи двадцать шестого года. Следующая проверка назначена на двадцать первое сентября."),
    ("measurements_ru", "ru", "ru", "Длина трубы двадцать миллиметров, стенка один миллиметр, скорость линии тридцать метров в минуту, давление четыре целых две десятых бара."),
    ("abbreviations_ru", "ru", "ru", "Проверь API, CPU, USB, Wi-Fi, APK и WAV, затем сохрани отчёт."),
    ("english_en", "en", "en", "Good morning. AuroraFox is running locally on Windows and Android without mandatory cloud speech services."),
    ("mixed_ru_en", "ru", "", "AuroraFox готова. OpenAI API не требуется, Windows и Android работают локально, а WAV сохраняется на устройстве."),
]

REPEAT_TEXT = "Повторная локальная проверка голоса должна оставаться стабильной без сети."
RAPID_TEXTS = [
    "Первая быстрая фраза.",
    "Вторая быстрая фраза.",
    "Третья быстрая фраза.",
    "Четвёртая быстрая фраза.",
    "Пятая быстрая фраза.",
]
CANCEL_TEXT = (
    "Это длинная фраза для проверки настоящей отмены синтеза. "
    "Генерация должна остановиться по callback до полного завершения длинного сообщения, "
    "не зависнуть и не повредить следующий запрос. " * 8
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--supertonic-dir", type=Path, required=True)
    parser.add_argument("--supertonic-archive", type=Path, required=True)
    parser.add_argument("--whisper-dir", type=Path, required=True)
    parser.add_argument("--whisper-archive", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--threads", type=int, default=2)
    return parser.parse_args()


def verify_archive(path: Path, expected_bytes: int, expected_sha256: str, label: str) -> None:
    actual_bytes = path.stat().st_size
    actual_sha = sha256_file(path)
    if actual_bytes != expected_bytes:
        raise RuntimeError(f"{label} archive bytes drifted: {actual_bytes} != {expected_bytes}")
    if actual_sha != expected_sha256:
        raise RuntimeError(f"{label} archive SHA-256 drifted: {actual_sha} != {expected_sha256}")


def build_whisper(model_dir: Path, language: str, threads: int) -> sherpa_onnx.OfflineRecognizer:
    encoder = find_one(model_dir, ("encoder",), ".onnx")
    decoder = find_one(model_dir, ("decoder",), ".onnx")
    tokens = find_one(model_dir, ("tokens",), ".txt")
    return sherpa_onnx.OfflineRecognizer.from_whisper(
        encoder=str(encoder),
        decoder=str(decoder),
        tokens=str(tokens),
        language=language,
        task="transcribe",
        num_threads=threads,
        debug=False,
        provider="cpu",
    )


def transcribe(recognizer: sherpa_onnx.OfflineRecognizer, samples: np.ndarray, sample_rate: int) -> str:
    stream = recognizer.create_stream()
    stream.accept_waveform(sample_rate, samples.astype(np.float32, copy=False))
    recognizer.decode_stream(stream)
    return str(getattr(stream.result, "text", "")).strip()


def generation_config(sid: int, language: str) -> sherpa_onnx.GenerationConfig:
    config = sherpa_onnx.GenerationConfig()
    config.sid = sid
    config.num_steps = 8
    config.speed = 1.0
    config.silence_scale = 0.2
    config.extra["lang"] = language
    return config


def generate_one(
    tts: sherpa_onnx.OfflineTts,
    recognizers: dict[str, sherpa_onnx.OfflineRecognizer],
    sid: int,
    scenario: str,
    language: str,
    asr_language: str,
    text: str,
    output_dir: Path,
) -> dict[str, object]:
    started = time.perf_counter()
    audio = tts.generate(text, generation_config(sid, language))
    synth_seconds = time.perf_counter() - started
    samples = np.asarray(audio.samples, dtype=np.float32)
    if samples.size == 0:
        raise RuntimeError(f"empty audio for sid={sid} scenario={scenario}")
    duration = samples.size / float(audio.sample_rate)
    speaker = f"F{sid + 1}"
    speaker_dir = output_dir / speaker
    speaker_dir.mkdir(parents=True, exist_ok=True)
    wav_path = speaker_dir / f"{scenario}.wav"
    sf.write(wav_path, samples, audio.sample_rate, subtype="PCM_16")

    recognizer = recognizers[asr_language]
    asr_started = time.perf_counter()
    transcript = transcribe(recognizer, samples, int(audio.sample_rate))
    asr_seconds = time.perf_counter() - asr_started
    return {
        "speaker": speaker,
        "sid": sid,
        "scenario": scenario,
        "tts_language": language,
        "asr_language": asr_language or "auto",
        "expected_text": text,
        "asr_text": transcript,
        "asr_similarity": similarity(text, transcript),
        "sample_rate": int(audio.sample_rate),
        "duration_seconds": duration,
        "synthesis_seconds": synth_seconds,
        "rtf": synth_seconds / duration,
        "asr_seconds": asr_seconds,
        "wav": str(wav_path.relative_to(output_dir)),
        **audio_metrics(samples),
    }


def run_reliability(tts: sherpa_onnx.OfflineTts, sid: int) -> dict[str, object]:
    repeat_times: list[float] = []
    repeat_sizes: list[int] = []
    for _ in range(3):
        started = time.perf_counter()
        audio = tts.generate(REPEAT_TEXT, generation_config(sid, "ru"))
        repeat_times.append(time.perf_counter() - started)
        repeat_sizes.append(len(audio.samples))
        if len(audio.samples) == 0:
            raise RuntimeError(f"repeat synthesis returned empty audio for sid={sid}")

    rapid_times: list[float] = []
    for text in RAPID_TEXTS:
        started = time.perf_counter()
        audio = tts.generate(text, generation_config(sid, "ru"))
        rapid_times.append(time.perf_counter() - started)
        if len(audio.samples) == 0:
            raise RuntimeError(f"rapid synthesis returned empty audio for sid={sid}")

    callback_calls = 0
    max_progress = 0.0

    def cancel_callback(samples: np.ndarray, progress: float) -> int:
        nonlocal callback_calls, max_progress
        callback_calls += 1
        max_progress = max(max_progress, float(progress))
        return 1

    started = time.perf_counter()
    cancelled_audio = tts.generate(CANCEL_TEXT, generation_config(sid, "ru"), cancel_callback)
    cancellation_seconds = time.perf_counter() - started
    cancelled_samples = len(cancelled_audio.samples)

    recovery = tts.generate("После отмены синтез снова работает.", generation_config(sid, "ru"))
    if len(recovery.samples) == 0:
        raise RuntimeError(f"post-cancellation recovery failed for sid={sid}")

    return {
        "speaker": f"F{sid + 1}",
        "sid": sid,
        "repeat_seconds": repeat_times,
        "repeat_sample_sizes": repeat_sizes,
        "repeat_size_stable": len(set(repeat_sizes)) == 1,
        "rapid_seconds": rapid_times,
        "rapid_total_seconds": sum(rapid_times),
        "cancel_callback_calls": callback_calls,
        "cancel_max_progress": max_progress,
        "cancellation_seconds": cancellation_seconds,
        "cancelled_samples": cancelled_samples,
        "post_cancel_recovery_samples": len(recovery.samples),
        "cancellation_callback_observed": callback_calls > 0,
    }


def main() -> None:
    args = parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    verify_archive(args.supertonic_archive, EXPECTED_SUPERTONIC_ARCHIVE_BYTES, EXPECTED_SUPERTONIC_ARCHIVE_SHA256, "Supertonic")
    verify_archive(args.whisper_archive, EXPECTED_WHISPER_ARCHIVE_BYTES, EXPECTED_WHISPER_ARCHIVE_SHA256, "Whisper")

    load_started = time.perf_counter()
    tts = build_tts(args.supertonic_dir, args.threads)
    cold_tts_load_seconds = time.perf_counter() - load_started
    if int(tts.num_speakers) < 5:
        raise RuntimeError(f"Supertonic exposes only {tts.num_speakers} speakers")

    recognizer_load_started = time.perf_counter()
    recognizers = {
        "ru": build_whisper(args.whisper_dir, "ru", args.threads),
        "en": build_whisper(args.whisper_dir, "en", args.threads),
        "": build_whisper(args.whisper_dir, "", args.threads),
    }
    whisper_load_seconds = time.perf_counter() - recognizer_load_started

    samples: list[dict[str, object]] = []
    reliability: list[dict[str, object]] = []
    for sid in range(5):
        for scenario, tts_language, asr_language, text in SCENARIOS:
            samples.append(generate_one(tts, recognizers, sid, scenario, tts_language, asr_language, text, args.output_dir))
        reliability.append(run_reliability(tts, sid))

    restart_started = time.perf_counter()
    restarted_tts = build_tts(args.supertonic_dir, args.threads)
    restart_load_seconds = time.perf_counter() - restart_started
    restart_audio = restarted_tts.generate("Проверка после повторной загрузки модели.", generation_config(0, "ru"))
    if len(restart_audio.samples) == 0:
        raise RuntimeError("restart synthesis returned empty audio")

    summaries: list[dict[str, object]] = []
    for sid in range(5):
        rows = [row for row in samples if int(row["sid"]) == sid]
        summaries.append({
            "speaker": f"F{sid + 1}",
            "sid": sid,
            "mean_asr_similarity": statistics.mean(float(row["asr_similarity"]) for row in rows),
            "min_asr_similarity": min(float(row["asr_similarity"]) for row in rows),
            "mean_rtf": statistics.mean(float(row["rtf"]) for row in rows),
            "max_rtf": max(float(row["rtf"]) for row in rows),
            "max_peak": max(float(row["peak"]) for row in rows),
            "mean_rms": statistics.mean(float(row["rms"]) for row in rows),
            "clipping_count": sum(int(row["clipping_count"]) for row in rows),
        })

    metric_candidates = sorted(summaries, key=lambda row: (
        int(row["clipping_count"]) != 0,
        -float(row["mean_asr_similarity"]),
        float(row["mean_rtf"]),
        int(row["sid"]),
    ))
    provisional_metric_candidate = metric_candidates[0]

    report = {
        "schema": 2,
        "engine": "sherpa-onnx-supertonic-3",
        "sherpa_onnx_version": getattr(sherpa_onnx, "__version__", "unknown"),
        "candidate_range": "F1-F5",
        "candidate_decision_boundary": "Machine metrics are provisional only. They do not prove female identity or naturalness; release speaker selection still requires human listening evidence.",
        "provisional_metric_candidate": provisional_metric_candidate,
        "speaker_summary": summaries,
        "samples": samples,
        "reliability": reliability,
        "scenario_count_per_speaker": len(SCENARIOS),
        "wav_count": len(samples),
        "cold_tts_load_seconds": cold_tts_load_seconds,
        "restart_tts_load_seconds": restart_load_seconds,
        "restart_synthesis_samples": len(restart_audio.samples),
        "whisper_load_seconds": whisper_load_seconds,
        "peak_rss_mib": max_rss_mib(),
        "supertonic_archive_bytes": args.supertonic_archive.stat().st_size,
        "supertonic_archive_sha256": sha256_file(args.supertonic_archive),
        "supertonic_unpacked_bytes": tree_bytes(args.supertonic_dir),
        "whisper_archive_bytes": args.whisper_archive.stat().st_size,
        "whisper_archive_sha256": sha256_file(args.whisper_archive),
        "whisper_unpacked_bytes": tree_bytes(args.whisper_dir),
        "threads": args.threads,
    }
    (args.output_dir / "acceptance-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    if len(samples) != 5 * len(SCENARIOS):
        raise RuntimeError(f"unexpected sample count: {len(samples)}")
    if any(int(row["clipping_count"]) != 0 for row in samples):
        raise RuntimeError("one or more acceptance WAVs clip")
    if any(not bool(row["cancellation_callback_observed"]) for row in reliability):
        raise RuntimeError("cancellation callback was not observed for every candidate")
    if any(int(row["post_cancel_recovery_samples"]) <= 0 for row in reliability):
        raise RuntimeError("post-cancellation recovery failed")

    print(
        "AURORA_SUPERTONIC_ACCEPTANCE_OK "
        f"wav_count={len(samples)} provisional_metric_candidate={provisional_metric_candidate['speaker']} "
        f"mean_similarity={float(provisional_metric_candidate['mean_asr_similarity']):.4f} "
        f"mean_rtf={float(provisional_metric_candidate['mean_rtf']):.4f} "
        f"cold_load={cold_tts_load_seconds:.3f}s restart_load={restart_load_seconds:.3f}s "
        f"peak_rss_mib={report['peak_rss_mib']:.1f}"
    )


if __name__ == "__main__":
    main()
