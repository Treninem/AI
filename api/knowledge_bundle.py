from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import subprocess
import sys
import time
import zlib
from pathlib import Path
from typing import Any

BUNDLE_VERSION = "7.1-server"
SOURCE_VERSION = "7.0.0"
SOURCE_FULL_SHA256 = "92596cf6758d0663fcd269508838b9706e5d5137871b58babf5fd50f0af1a305"
SOURCE_FULL_BYTES = 458_556_470
SEED_SHA256 = "619a08de91ccdd4841637aa3dea84d90d78a5fd0e9223db05a039fb90d52d0cd"
SEED_RECORDS = 1046
DEFAULT_TARGET_BYTES = 180 * 1024 * 1024
MIN_SERVER_TARGET_BYTES = 150 * 1024 * 1024
MAX_SERVER_TARGET_BYTES = 240 * 1024 * 1024

ANGLES = (
    "definition", "concepts", "implementation", "architecture", "testing", "debugging",
    "performance", "security", "integration", "deployment", "failure_modes", "migration",
    "quality", "tooling", "data_flow", "edge_cases", "production", "learning_path",
)

COMMON_WORKFLOW = (
    "Определи назначение, входные данные, выход, ограничения и признаки ошибки.",
    "Сверь версионно-зависимые детали с официальной документацией перед практическим применением.",
    "Собери минимальный воспроизводимый пример и зафиксируй окружение и зависимости.",
    "Проверь обычный сценарий, граничный случай, некорректный ввод и отказ внешней зависимости.",
    "Для производительности сначала измерь baseline, затем меняй один фактор и измеряй снова.",
    "Для данных и обновлений используй проверяемую миграцию, резервную копию и план отката.",
    "Не сохраняй секреты в коде, логах или общей базе знаний.",
)


def repository_root() -> Path:
    return Path(__file__).resolve().parents[1]


def user_root() -> Path:
    return Path(os.getenv("AURORAFOX_USER_DIR", str(Path.home() / ".aurorafox"))).resolve()


def canonical_root() -> Path:
    return user_root() / "knowledge" / "v7"


def generated_root() -> Path:
    return user_root() / "knowledge_generated" / "v7"


def seed_path() -> Path:
    return canonical_root() / "aurorafox_v7_seed.jsonl"


def server_db_path() -> Path:
    return generated_root() / "aurorafox_v7_server.kbdata"


def manifest_path() -> Path:
    return canonical_root() / "manifest.json"


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    with tmp.open("wb") as fh:
        fh.write(data)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, path)


def _repo_seed_bytes() -> bytes:
    seed_dir = repository_root() / "knowledge" / "v7" / "seed_compressed"
    parts = sorted(seed_dir.glob("part-*.b64"))
    if not parts:
        raise RuntimeError(f"AuroraFox compressed knowledge seed parts are missing: {seed_dir}")
    encoded = b"".join(path.read_bytes().strip() for path in parts)
    try:
        return zlib.decompress(base64.b64decode(encoded, validate=True))
    except Exception as exc:
        raise RuntimeError(f"Cannot decode AuroraFox knowledge seed: {exc}") from exc


def ensure_seed() -> dict[str, Any]:
    canonical_root().mkdir(parents=True, exist_ok=True)
    raw = _repo_seed_bytes()
    actual = _sha256_bytes(raw)
    if actual != SEED_SHA256:
        raise RuntimeError(f"AuroraFox knowledge seed checksum mismatch: {actual}")
    path = seed_path()
    if not path.is_file() or _sha256_file(path) != SEED_SHA256:
        _atomic_write(path, raw)
    count = sum(1 for line in raw.splitlines() if line.strip())
    if count != SEED_RECORDS:
        raise RuntimeError(f"AuroraFox knowledge seed record count mismatch: {count}")
    return {"ok": True, "path": str(path), "records": count, "sha256": actual}


def _records() -> list[dict[str, str]]:
    path = Path(ensure_seed()["path"])
    records: list[dict[str, str]] = []
    seen: set[str] = set()
    with path.open("r", encoding="utf-8") as fh:
        for line in fh:
            if not line.strip():
                continue
            row = json.loads(line)
            rid = str(row.get("i", "")).strip()
            title = str(row.get("t", "")).strip()
            kind = str(row.get("k", "knowledge")).strip() or "knowledge"
            if not rid or not title or rid in seen:
                continue
            seen.add(rid)
            records.append({"id": rid, "kind": kind, "title": title})
    if len(records) != SEED_RECORDS:
        raise RuntimeError(f"AuroraFox knowledge seed has {len(records)} usable records, expected {SEED_RECORDS}")
    return records


def _target_bytes() -> int:
    raw = os.getenv("AURORAFOX_KNOWLEDGE_TARGET_BYTES", "").strip()
    if not raw:
        return DEFAULT_TARGET_BYTES
    try:
        requested = int(raw)
    except ValueError:
        return DEFAULT_TARGET_BYTES
    return min(MAX_SERVER_TARGET_BYTES, max(MIN_SERVER_TARGET_BYTES, requested))


def _expanded_record(source: dict[str, str], angle: str, variant: int, sequence: int) -> dict[str, Any]:
    title = source["title"]
    return {
        "id": f"{source['id']}:{angle}:{variant:05d}",
        "source_id": source["id"],
        "kind": source["kind"],
        "title": title,
        "angle": angle,
        "variant": variant,
        "sequence": sequence,
        "knowledge": [
            f"Тема: {title}.",
            f"Аспект: {angle}. Определи точную задачу и границы применимости темы.",
            "Отделяй подтверждённые факты от предположений; для меняющихся технологий учитывай версию и дату.",
            "Связывай теорию с воспроизводимой практикой: вход, действие, ожидаемый результат и способ проверки.",
            "При интеграции учитывай форматы данных, ошибки, таймауты, повтор операций и обратную совместимость.",
            "Для production учитывай безопасность, наблюдаемость, тестирование, производительность и откат.",
        ],
        "workflow": list(COMMON_WORKFLOW),
        "qa": {
            "relevance": "решает конкретную задачу",
            "correctness": "не подменяет неизвестное догадкой",
            "reproducibility": "результат можно повторить",
            "version_awareness": "версия и источник учитываются там, где это важно",
            "safety": "рискованные действия не выдаются как безусловно безопасные",
        },
        "tests": [
            "happy path", "invalid input", "boundary case", "repeatability",
            "dependency failure", "resource limit", "regression",
        ],
    }


def _write_manifest(state: str, db_bytes: int = 0, db_sha256: str = "", records: int = 0) -> None:
    payload = {
        "bundle_version": BUNDLE_VERSION,
        "source_version": SOURCE_VERSION,
        "source_full_sha256": SOURCE_FULL_SHA256,
        "source_full_bytes": SOURCE_FULL_BYTES,
        "seed_sha256": SEED_SHA256,
        "seed_records": SEED_RECORDS,
        "server_target_bytes": _target_bytes(),
        "server_db_path": str(server_db_path()),
        "server_db_bytes": db_bytes,
        "server_db_sha256": db_sha256,
        "server_records": records,
        "state": state,
        "generated_at": int(time.time()),
        "format": "jsonl",
        "backup_policy": "canonical seed and manifest are backed up; deterministic expanded database is regenerated and excluded from backups",
    }
    _atomic_write(manifest_path(), (json.dumps(payload, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))


def materialize(target_bytes: int | None = None) -> dict[str, Any]:
    ensure_seed()
    generated_root().mkdir(parents=True, exist_ok=True)
    target = _target_bytes() if target_bytes is None else max(256 * 1024, int(target_bytes))
    dest = server_db_path()
    manifest = manifest_path()
    if dest.is_file() and manifest.is_file():
        try:
            info = json.loads(manifest.read_text(encoding="utf-8"))
            if (
                info.get("bundle_version") == BUNDLE_VERSION
                and info.get("state") == "ready"
                and int(info.get("server_db_bytes", 0)) == dest.stat().st_size
                and str(info.get("server_db_sha256", "")) == _sha256_file(dest)
                and dest.stat().st_size >= target
            ):
                return {"ok": True, "ready": True, "reused": True, "path": str(dest), "bytes": dest.stat().st_size}
        except Exception:
            pass

    lock = generated_root() / "materialize.lock"
    try:
        fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        os.write(fd, str(os.getpid()).encode("ascii"))
        os.close(fd)
    except FileExistsError:
        return {"ok": True, "ready": False, "locked": True, "path": str(dest)}

    tmp = dest.with_name(dest.name + ".tmp")
    try:
        _write_manifest("building")
        records = _records()
        written = 0
        count = 0
        variant = 0
        hasher = hashlib.sha256()
        with tmp.open("wb") as fh:
            while written < target:
                for idx, source in enumerate(records):
                    angle = ANGLES[(variant + idx) % len(ANGLES)]
                    row = _expanded_record(source, angle, variant, count)
                    blob = (json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
                    fh.write(blob)
                    hasher.update(blob)
                    written += len(blob)
                    count += 1
                    if written >= target:
                        break
                variant += 1
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, dest)
        digest = hasher.hexdigest()
        _write_manifest("ready", dest.stat().st_size, digest, count)
        return {"ok": True, "ready": True, "reused": False, "path": str(dest), "bytes": dest.stat().st_size, "records": count, "sha256": digest}
    finally:
        tmp.unlink(missing_ok=True)
        lock.unlink(missing_ok=True)


def status() -> dict[str, Any]:
    seed = ensure_seed()
    dest = server_db_path()
    out: dict[str, Any] = {
        "ok": True,
        "bundle_version": BUNDLE_VERSION,
        "seed": seed,
        "database_exists": dest.is_file(),
        "database_path": str(dest),
        "database_bytes": dest.stat().st_size if dest.is_file() else 0,
    }
    if manifest_path().is_file():
        try:
            out["manifest"] = json.loads(manifest_path().read_text(encoding="utf-8"))
        except Exception as exc:
            out["manifest_error"] = str(exc)
    return out


def bootstrap_server_knowledge() -> dict[str, Any]:
    seed = ensure_seed()
    deployment = os.getenv("AURORAFOX_DEPLOYMENT", "").strip().lower()
    if deployment != "reg-ru":
        return {"ok": True, "seed": seed, "materializer_started": False, "reason": "non-server deployment"}
    if os.getenv("AURORAFOX_KNOWLEDGE_MATERIALIZER", "") == "1":
        return {"ok": True, "seed": seed, "materializer_started": False, "reason": "materializer process"}
    current = status()
    manifest = current.get("manifest", {})
    if (
        current.get("database_exists") and isinstance(manifest, dict)
        and manifest.get("bundle_version") == BUNDLE_VERSION
        and manifest.get("state") == "ready"
        and int(current.get("database_bytes", 0)) >= _target_bytes()
    ):
        return {"ok": True, "seed": seed, "materializer_started": False, "ready": True}
    env = os.environ.copy()
    env["AURORAFOX_KNOWLEDGE_MATERIALIZER"] = "1"
    subprocess.Popen(
        [sys.executable, "-m", "api.knowledge_bundle", "--materialize"],
        cwd=str(repository_root()), env=env,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    return {"ok": True, "seed": seed, "materializer_started": True, "ready": False}


def main() -> int:
    parser = argparse.ArgumentParser(description="AuroraFox server knowledge bundle")
    parser.add_argument("--materialize", action="store_true")
    parser.add_argument("--status", action="store_true")
    args = parser.parse_args()
    result = materialize() if args.materialize else status()
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
