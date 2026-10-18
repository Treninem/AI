"""Hosted, synthetic comparison only; never changes AuroraFox's bundled Core."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import threading
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


CASES = (
    ("ice_density", "Почему обычный лёд плавает в воде при нормальных условиях? Одно короткое предложение."),
    ("venus_hottest", "Какая планета Солнечной системы самая горячая? Ответь кратко."),
    ("mars_moons", "Назови два естественных спутника Марса."),
    ("water_boil", "При какой температуре кипит чистая вода при нормальном атмосферном давлении?"),
    ("earth_order", "Какая по счёту от Солнца планета Земля?"),
    ("photosynthesis", "Какой газ растения поглощают и какой выделяют при обычном фотосинтезе?"),
    ("salt_fresh", "Что находится выше при устойчивом слоистом смешении: пресная или солёная вода? Почему?"),
    ("mercury_moons", "Есть ли у Меркурия естественные спутники?"),
    ("jupiter_type", "К какому типу планет относится Юпитер?"),
    ("arithmetic", "Сколько будет 17 умножить на 6? Ответь числом."),
    ("translation", "Переведи слово hello на русский язык. Только перевод."),
    ("english_chat", "In one English sentence, explain how a local assistant can use memory while planning a task."),
)


def obvious_check(case_id: str, answer: str) -> bool | None:
    """Only unmistakable checks; a human must review the complete report."""
    text = answer.casefold().replace("ё", "е")
    if case_id == "ice_density":
        if re.search(r"лед\s+плотнее\s+вод", text):
            return False
        return bool(re.search(r"(?:менее|меньш\w*)\s+плот(?:ен|н\w*)|плотност\w*\s+(?:меньш|ниже)", text))
    if case_id == "venus_hottest":
        return "венер" in text and "меркурий — самая" not in text
    if case_id == "mars_moons":
        return "фобос" in text and "деймос" in text
    if case_id == "water_boil":
        return bool(re.search(r"\b100\b", text))
    if case_id == "earth_order":
        return bool(re.search(r"\b3\b|треть", text))
    if case_id == "photosynthesis":
        return "углекисл" in text and "кислород" in text
    if case_id == "salt_fresh":
        return None  # relation direction needs human reading
    if case_id == "mercury_moons":
        return None  # negation must bind to Mercury, not another planet
    if case_id == "jupiter_type":
        return "газов" in text
    if case_id == "arithmetic":
        return bool(re.search(r"\b102\b", text))
    if case_id == "translation":
        return "привет" in text
    if case_id == "english_chat":
        return None  # natural-language quality needs human reading
    raise ValueError(case_id)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def process_rss_kib(pid: int) -> int:
    try:
        for line in Path(f"/proc/{pid}/status").read_text().splitlines():
            if line.startswith("VmRSS:"):
                return int(line.split()[1])
    except (OSError, ValueError):
        pass
    return 0


def post_json(url: str, body: dict, timeout: float) -> dict:
    request = Request(url, json.dumps(body).encode(), {"Content-Type": "application/json"})
    with urlopen(request, timeout=timeout) as response:
        return json.load(response)


def p95(values: list[float]) -> float:
    return sorted(values)[math.ceil(len(values) * 0.95) - 1]


def run_model(engine: Path, name: str, model: Path, expected_hash: str,
              port: int) -> dict:
    actual_hash = sha256(model)
    if actual_hash != expected_hash:
        raise RuntimeError(f"{name}: model SHA256 mismatch: {actual_hash}")
    args = [str(engine), "--model", str(model), "--alias", name,
            "--host", "127.0.0.1", "--port", str(port), "--ctx-size", "1024",
            "--threads", "2", "--parallel", "1", "--n-gpu-layers", "0", "--jinja"]
    log_path = Path(f"{name}-engine.log")
    with log_path.open("w", encoding="utf-8") as log:
        server = subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT)
        stop = threading.Event()
        rss_samples: list[int] = []

        def sample_memory() -> None:
            while not stop.wait(0.05):
                rss_samples.append(process_rss_kib(server.pid))

        sampler = threading.Thread(target=sample_memory, daemon=True)
        sampler.start()
        started = time.monotonic()
        base = f"http://127.0.0.1:{port}"
        try:
            deadline = started + 120
            while time.monotonic() < deadline:
                if server.poll() is not None:
                    raise RuntimeError(f"{name}: server exited {server.returncode}; see {log_path}")
                try:
                    with urlopen(base + "/health", timeout=1) as response:
                        if response.status == 200:
                            break
                except (HTTPError, URLError, TimeoutError):
                    time.sleep(0.25)
            else:
                raise TimeoutError(f"{name}: startup exceeded 120 seconds; see {log_path}")
            startup_ms = round((time.monotonic() - started) * 1000, 1)
            results = []
            for case_id, prompt in CASES:
                request = {"model": name, "messages": [{"role": "user", "content": prompt}],
                           "temperature": 0, "max_tokens": 96, "stream": False,
                           "reasoning_effort": "none"}
                before = time.monotonic()
                try:
                    response = post_json(base + "/v1/chat/completions", request, 60)
                    content = response["choices"][0]["message"].get("content") or ""
                    results.append({"id": case_id, "elapsed_ms": round((time.monotonic()-before)*1000, 1),
                                    "answer": content[:500], "obvious_check": obvious_check(case_id, content),
                                    "usage": response.get("usage", {})})
                except (HTTPError, URLError, TimeoutError, KeyError, IndexError, ValueError) as exc:
                    results.append({"id": case_id, "elapsed_ms": round((time.monotonic()-before)*1000, 1),
                                    "error": str(exc)[:250], "obvious_check": False})
            latencies = [item["elapsed_ms"] for item in results]
            return {"name": name, "model_sha256": actual_hash, "model_bytes": model.stat().st_size,
                    "startup_ms": startup_ms, "peak_rss_mib": round(max(rss_samples or [0])/1024, 1),
                    "latency_p50_ms": sorted(latencies)[len(latencies)//2],
                    "latency_p95_ms": p95(latencies), "cases": results}
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
    parser.add_argument("--model", nargs=3, action="append", metavar=("NAME", "PATH", "SHA256"))
    parser.add_argument("--output", type=Path, default=Path("model-size-probe.json"))
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        assert len(CASES) >= 10 and len({item[0] for item in CASES}) == len(CASES)
        assert obvious_check("ice_density", "Лёд менее плотен, чем вода.") is True
        assert obvious_check("ice_density", "Лёд плотнее воды.") is False
        print("AURORA_MODEL_PROBE_SELF_TEST_OK")
        return
    if os.name != "posix" or args.engine is None or not args.engine.is_file():
        raise RuntimeError("Hosted Linux CPU engine required")
    if not args.model or len(args.model) != 2:
        raise ValueError("compare exactly two pinned models in one hosted run")
    report = {"kind": "hosted_research_only", "engine": str(args.engine),
              "runner": {"cpus": os.cpu_count(), "uname": os.uname().machine}, "models": []}
    for name, path, expected in args.model:
        report["models"].append(run_model(args.engine, name, Path(path), expected.lower(), 18776))
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"models": [{key: value for key, value in model.items() if key != "cases"}
                                  for model in report["models"]]}, ensure_ascii=False))
    if any("error" in case for model in report["models"] for case in model["cases"]):
        raise RuntimeError("A model request failed; report retained for diagnosis")


if __name__ == "__main__":
    main()
