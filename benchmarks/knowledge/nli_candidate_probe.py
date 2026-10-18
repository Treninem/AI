"""CPU-only research probe for a small public Russian NLI checkpoint.

This is not shipped with Fox. --validate checks the public fixture without
installing dependencies or downloading a model; --run requires a hosted worker.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import statistics
import time
from pathlib import Path


FIXTURE = Path(__file__).parent / "fixtures" / "nli_candidate_pairs.json"
THRESHOLDS = (0.5, 0.8, 0.95)


def load_cases() -> dict:
    data = json.loads(FIXTURE.read_text(encoding="utf-8"))
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", data["model_id"]):
        raise ValueError("invalid fixed model identifier")
    if not re.fullmatch(r"[0-9a-f]{7,40}", data["revision"]):
        raise ValueError("model revision must be a Git commit prefix")
    cases = data["cases"]
    holdout = data.get("holdout_cases", [])
    combined = cases + holdout
    if (len(cases) < 10 or (holdout and len(holdout) < 10)
            or len({c["id"] for c in combined}) != len(combined)):
        raise ValueError("expected distinct identifiers and at least ten pairs per set")
    if not all(isinstance(c["entails"], bool) and c["premise"].strip()
               and c["hypothesis"].strip() and c["source_url"].startswith("https://")
               for c in combined):
        raise ValueError("invalid public premise/hypothesis record")
    return data


def summarize(cases: list[dict], probabilities: list[float]) -> dict:
    if len(cases) != len(probabilities) or not all(math.isfinite(p) and 0 <= p <= 1
                                                   for p in probabilities):
        raise ValueError("candidate score count or range is invalid")
    results = {}
    for threshold in THRESHOLDS:
        false_support = [c["id"] for c, p in zip(cases, probabilities)
                         if not c["entails"] and p >= threshold]
        missed_support = [c["id"] for c, p in zip(cases, probabilities)
                          if c["entails"] and p < threshold]
        results[str(threshold)] = {
            "false_support": false_support,
            "missed_support": missed_support,
            "true_support": sum(c["entails"] and p >= threshold
                                for c, p in zip(cases, probabilities)),
            "true_abstain": sum(not c["entails"] and p < threshold
                                for c, p in zip(cases, probabilities)),
        }
    return results


def run(data: dict) -> dict:
    # Imported only on a hosted CPU worker. The owner PC may have too little RAM.
    import resource

    import torch
    from huggingface_hub import snapshot_download
    from transformers import AutoModelForSequenceClassification, AutoTokenizer

    torch.set_num_threads(2)
    start = time.perf_counter()
    snapshot = Path(snapshot_download(
        repo_id=data["model_id"], revision=data["revision"],
        allow_patterns=["*.json", "*.txt", "*.model", "*.safetensors"],
        max_workers=1, token=False,
    ))
    resolved_sha = snapshot.name
    if not re.fullmatch(r"[0-9a-f]{40}", resolved_sha):
        raise RuntimeError("could not verify resolved model commit")
    tokenizer = AutoTokenizer.from_pretrained(snapshot, trust_remote_code=False)
    model = AutoModelForSequenceClassification.from_pretrained(
        snapshot, trust_remote_code=False, use_safetensors=True).eval().to("cpu")
    labels = {int(i): str(label).casefold() for i, label in model.config.id2label.items()}
    entail_ids = [i for i, label in labels.items()
                  if "entail" in label and "not" not in label and "non" not in label]
    if len(entail_ids) != 1:
        raise RuntimeError(f"unverified NLI label mapping: {labels}")
    load_seconds = round(time.perf_counter() - start, 3)
    probabilities, latencies = [], []
    cases = data["cases"] + data.get("holdout_cases", [])
    for case in cases:
        encoded = tokenizer(case["premise"], case["hypothesis"], return_tensors="pt",
                            truncation=True, max_length=256)
        began = time.perf_counter()
        with torch.inference_mode():
            logits = model(**encoded).logits[0]
            probability = torch.softmax(logits, dim=-1)[entail_ids[0]].item()
        latencies.append((time.perf_counter() - began) * 1000)
        probabilities.append(probability)
    ordered = sorted(latencies)
    return {
        "model_id": data["model_id"], "resolved_sha": resolved_sha,
        "torch_version": torch.__version__, "load_seconds": load_seconds,
        "max_rss_mib": round(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024, 1),
        "latency_p50_ms": round(statistics.median(ordered), 2),
        "latency_p95_ms": round(ordered[math.ceil(len(ordered) * 0.95) - 1], 2),
        "scores": [{"id": case["id"], "entailment_probability": round(p, 4)}
                   for case, p in zip(cases, probabilities)],
        "thresholds": summarize(data["cases"], probabilities[:len(data["cases"])]),
        "holdout_thresholds": summarize(data.get("holdout_cases", []),
                                        probabilities[len(data["cases"]):]),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--validate", action="store_true")
    mode.add_argument("--run", action="store_true")
    args = parser.parse_args()
    data = load_cases()
    if args.validate:
        print(json.dumps({"fixture_valid": True, "cases": len(data["cases"]),
                          "holdout_cases": len(data.get("holdout_cases", [])),
                          "positive": sum(c["entails"] for c in data["cases"]),
                          "negative": sum(not c["entails"] for c in data["cases"]),
                          "holdout_positive": sum(c["entails"] for c in data.get("holdout_cases", [])),
                          "holdout_negative": sum(not c["entails"] for c in data.get("holdout_cases", []))}, indent=2))
        return 0
    result = run(data)
    print(json.dumps(result, indent=2, ensure_ascii=False))
    # A successful probe run is not a product PASS. This threshold is an
    # experimental tripwire; broader held-out data and owner-PC budgets remain.
    gate = result["thresholds"]["0.8"]
    holdout_gate = result["holdout_thresholds"]["0.8"]
    return int(bool(gate["false_support"]) or gate["true_support"] < 4
               or bool(holdout_gate["false_support"]) or holdout_gate["true_support"] < 4)


if __name__ == "__main__":
    raise SystemExit(main())
