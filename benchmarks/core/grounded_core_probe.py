"""Manual-only hosted A/B probe for the pinned bundled Core; synthetic facts only."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import threading
import time
from urllib.error import HTTPError, URLError
from urllib.request import urlopen

from model_size_probe import p95, post_json, process_rss_kib, sha256


# Short paraphrases of public primary sources, checked 2026-10-18. These are
# supplied evidence, never authority over tools or the application.
CASES = (
    ("ice", "Почему обычный лёд плавает в воде?", "Обычный лёд менее плотен, чем жидкая вода; при замерзании молекулы располагаются дальше друг от друга.", "https://www.usgs.gov/water-science-school/science/water-density"),
    ("venus", "Какая планета Солнечной системы самая горячая?", "Венера — самая горячая планета Солнечной системы; плотная атмосфера удерживает тепло.", "https://science.nasa.gov/venus/venus-facts/"),
    ("mars", "Назови естественные спутники Марса.", "У Марса ровно два естественных спутника: Фобос и Деймос.", "https://science.nasa.gov/mars/moons/"),
    ("earth", "Какая по счёту от Солнца планета Земля?", "Земля — третья планета от Солнца.", "https://science.nasa.gov/earth/facts/"),
    ("salt", "Что выше при устойчивом расслоении пресной и солёной воды и почему?", "Пресная вода располагается над солёной, поскольку солёная вода плотнее.", "https://oceanservice.noaa.gov/education/dyw-pass-salt.html"),
)


def prompts() -> list[tuple[str, str, str]]:
    rows = []
    for case_id, question, evidence, source in CASES:
        rows.append((case_id, "bare", question))
        rows.append((case_id, "grounded", f"Источник: {source}\nФрагмент: {evidence}\nВопрос: {question}\nОтветь кратко, опираясь только на фрагмент. Если он не отвечает на вопрос, скажи 'Недостаточно данных'."))
    ice_id, ice_question, _, _ = CASES[0]
    _, _, unrelated, unrelated_source = CASES[1]
    rows.append((ice_id, "unrelated_control", f"Источник: {unrelated_source}\nФрагмент: {unrelated}\nВопрос: {ice_question}\nОтветь кратко, опираясь только на фрагмент. Если он не отвечает на вопрос, скажи 'Недостаточно данных'."))
    return rows


def run(engine: Path, model: Path, expected_hash: str, output: Path) -> None:
    actual = sha256(model)
    if actual != expected_hash:
        raise RuntimeError(f"model SHA256 mismatch: {actual}")
    log_path = output.with_suffix(".engine.log")
    args = [str(engine), "--model", str(model), "--alias", "current", "--host", "127.0.0.1", "--port", "18989", "--ctx-size", "1024", "--threads", "2", "--parallel", "1", "--n-gpu-layers", "0", "--jinja"]
    with log_path.open("w", encoding="utf-8") as log:
        server = subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT)
        stop = threading.Event()
        rss: list[int] = []

        def sample() -> None:
            while not stop.wait(0.05):
                rss.append(process_rss_kib(server.pid))

        sampler = threading.Thread(target=sample, daemon=True)
        sampler.start()
        start = time.monotonic()
        try:
            while time.monotonic() - start < 120:
                if server.poll() is not None:
                    raise RuntimeError(f"server exited {server.returncode}; see {log_path}")
                try:
                    with urlopen("http://127.0.0.1:18989/health", timeout=1) as response:
                        if response.status == 200:
                            break
                except (HTTPError, URLError, TimeoutError):
                    time.sleep(0.25)
            else:
                raise TimeoutError("server startup exceeded 120s")
            startup_ms = round((time.monotonic() - start) * 1000, 1)
            results = []
            for case_id, mode, prompt in prompts():
                before = time.monotonic()
                request = {"model": "current", "messages": [{"role": "user", "content": prompt}], "temperature": 0, "max_tokens": 96, "stream": False, "reasoning_effort": "none"}
                try:
                    answer = post_json("http://127.0.0.1:18989/v1/chat/completions", request, 60)["choices"][0]["message"].get("content") or ""
                    results.append({"id": case_id, "mode": mode, "elapsed_ms": round((time.monotonic() - before) * 1000, 1), "answer": answer[:700]})
                except (HTTPError, URLError, TimeoutError, KeyError, IndexError, ValueError) as exc:
                    results.append({"id": case_id, "mode": mode, "elapsed_ms": round((time.monotonic() - before) * 1000, 1), "error": str(exc)[:250]})
            output.write_text(json.dumps({"model_sha256": actual, "model_bytes": model.stat().st_size, "startup_ms": startup_ms, "peak_rss_mib": round(max(rss or [0]) / 1024, 1), "latency_p95_ms": p95([r["elapsed_ms"] for r in results]), "cases": results}, ensure_ascii=False, indent=2), encoding="utf-8")
        finally:
            server.terminate()
            try:
                server.wait(timeout=10)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=10)
            stop.set()
            sampler.join(timeout=2)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--engine", type=Path)
    parser.add_argument("--model", type=Path)
    parser.add_argument("--sha256")
    parser.add_argument("--output", type=Path, default=Path("grounded-core-probe.json"))
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        assert len(CASES) == 5 and len(prompts()) == 11
        assert "Венера" in prompts()[-1][2] and "лёд" in prompts()[-1][2]
        print("AURORA_GROUNDED_PROBE_SELF_TEST_OK")
        return
    if not args.engine or not args.model or not args.sha256:
        parser.error("--engine, --model, --sha256 required")
    run(args.engine, args.model, args.sha256, args.output)


if __name__ == "__main__":
    main()
