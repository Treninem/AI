from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sqlite3
import tempfile
import time
import uuid
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any


DATA_SUFFIXES = {".db", ".json", ".jsonl", ".sqlite", ".sqlite3"}
SECRET_NAMES = {
    ".env",
    "bootstrap_key.txt",
    "keys.json",
}
SECRET_SUFFIXES = {".key", ".p12", ".pem"}
SKIP_DIRECTORIES = {
    ".backup-cache",
    "backups",
    "cache",
    "models",
    "server_backups",
    "uploads",
}


class BackupTooLarge(RuntimeError):
    pass


@dataclass(frozen=True)
class BackupResult:
    archive_path: Path
    backup_id: str
    sha256: str
    file_count: int
    source_bytes: int


class BackupService:
    """Create a verifiable data snapshot without dedicated credential files."""

    def __init__(self, user_root: Path, cache_root: Path | None = None, max_source_bytes: int | None = None):
        self.user_root = user_root.resolve()
        self.cache_root = (cache_root or self.user_root / "api" / ".backup-cache").resolve()
        self.max_source_bytes = max_source_bytes or int(
            os.getenv("AURORAFOX_BACKUP_MAX_BYTES", str(256 * 1024 * 1024))
        )
        self.cache_root.mkdir(parents=True, exist_ok=True)

    @staticmethod
    def _sha256(path: Path) -> str:
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        return digest.hexdigest()

    @staticmethod
    def _is_sqlite(path: Path) -> bool:
        try:
            with path.open("rb") as stream:
                return stream.read(16) == b"SQLite format 3\x00"
        except OSError:
            return False

    def _iter_sources(self) -> list[tuple[Path, Path]]:
        sources: list[tuple[Path, Path]] = []
        if not self.user_root.is_dir():
            return sources
        for source in self.user_root.rglob("*"):
            try:
                relative = source.relative_to(self.user_root)
            except ValueError:
                continue
            if any(part.lower() in SKIP_DIRECTORIES for part in relative.parts[:-1]):
                continue
            if source.is_symlink() or not source.is_file():
                continue
            if source.name.lower() in SECRET_NAMES or source.suffix.lower() in SECRET_SUFFIXES:
                continue
            if source.suffix.lower() not in DATA_SUFFIXES:
                continue
            sources.append((source, relative))
        return sorted(sources, key=lambda item: item[1].as_posix())

    def _copy_source(self, source: Path, destination: Path) -> None:
        destination.parent.mkdir(parents=True, exist_ok=True)
        if self._is_sqlite(source):
            source_uri = source.resolve().as_uri() + "?mode=ro"
            source_db = sqlite3.connect(source_uri, uri=True, timeout=30)
            destination_db = sqlite3.connect(destination)
            try:
                source_db.backup(destination_db)
            finally:
                destination_db.close()
                source_db.close()
            return
        shutil.copyfile(source, destination)

    def create_archive(self) -> BackupResult:
        backup_id = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()) + "-" + uuid.uuid4().hex[:10]
        archive_path = self.cache_root / f"AuroraFox-Server-Backup-{backup_id}.zip"
        manifest_files: list[dict[str, Any]] = []
        source_bytes = 0

        with tempfile.TemporaryDirectory(prefix="snapshot-", dir=self.cache_root) as temp_name:
            snapshot_root = Path(temp_name)
            for source, relative in self._iter_sources():
                expected_size = source.stat().st_size
                if source_bytes + expected_size > self.max_source_bytes:
                    raise BackupTooLarge(
                        f"AuroraFox backup data exceeds limit of {self.max_source_bytes} bytes"
                    )
                destination = snapshot_root / "data" / relative
                self._copy_source(source, destination)
                actual_size = destination.stat().st_size
                source_bytes += actual_size
                manifest_files.append({
                    "path": (Path("data") / relative).as_posix(),
                    "bytes": actual_size,
                    "sha256": self._sha256(destination),
                })

            manifest = {
                "schema": "aurorafox.backup.v1",
                "backup_id": backup_id,
                "created_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "source": "AuroraFox server persistent data",
                "credential_files_included": False,
                "file_count": len(manifest_files),
                "source_bytes": source_bytes,
                "files": manifest_files,
            }
            manifest_path = snapshot_root / "manifest.json"
            manifest_path.write_text(
                json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )

            temporary_archive = archive_path.with_suffix(".zip.tmp")
            try:
                with zipfile.ZipFile(
                    temporary_archive,
                    "w",
                    compression=zipfile.ZIP_DEFLATED,
                    compresslevel=6,
                ) as archive:
                    archive.write(manifest_path, "manifest.json")
                    for item in manifest_files:
                        archive.write(snapshot_root / item["path"], item["path"])
                temporary_archive.replace(archive_path)
            finally:
                temporary_archive.unlink(missing_ok=True)

        return BackupResult(
            archive_path=archive_path,
            backup_id=backup_id,
            sha256=self._sha256(archive_path),
            file_count=len(manifest_files),
            source_bytes=source_bytes,
        )

    def publish_latest(self, export_root: Path) -> BackupResult:
        export_root = export_root.resolve()
        export_root.mkdir(parents=True, exist_ok=True)
        result = self.create_archive()
        latest_archive = export_root / "latest.zip"
        latest_hash = export_root / "latest.sha256"
        temporary_hash = export_root / ".latest.sha256.tmp"
        result.archive_path.replace(latest_archive)
        os.chmod(latest_archive, 0o640)
        temporary_hash.write_text(f"{result.sha256}  latest.zip\n", encoding="ascii", newline="\n")
        os.chmod(temporary_hash, 0o640)
        temporary_hash.replace(latest_hash)
        return BackupResult(
            archive_path=latest_archive,
            backup_id=result.backup_id,
            sha256=result.sha256,
            file_count=result.file_count,
            source_bytes=result.source_bytes,
        )


def main() -> int:
    parser = argparse.ArgumentParser(description="Create the restricted AuroraFox server data snapshot")
    parser.add_argument("--user-root", required=True)
    parser.add_argument("--export-root", required=True)
    parser.add_argument("--max-source-bytes", type=int, default=256 * 1024 * 1024)
    args = parser.parse_args()
    export_root = Path(args.export_root)
    service = BackupService(
        Path(args.user_root),
        export_root / ".work",
        max_source_bytes=max(1, args.max_source_bytes),
    )
    result = service.publish_latest(export_root)
    print(json.dumps({
        "ok": True,
        "backup_id": result.backup_id,
        "path": str(result.archive_path),
        "sha256": result.sha256,
        "file_count": result.file_count,
        "source_bytes": result.source_bytes,
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
