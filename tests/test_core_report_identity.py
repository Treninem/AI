import json
from pathlib import Path
import subprocess

import pytest

from benchmarks.core.report_identity import bind_report, checkout_sha


@pytest.fixture
def repository(tmp_path, monkeypatch):
    monkeypatch.delenv("AURORAFOX_BENCHMARK_EXPECTED_SHA", raising=False)
    repo = tmp_path / "source"
    repo.mkdir()
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    (repo / "source.txt").write_text("real test commit\n")
    subprocess.run(["git", "-C", str(repo), "add", "source.txt"], check=True)
    subprocess.run([
        "git", "-C", str(repo), "-c", "user.name=Identity Test",
        "-c", "user.email=identity@example.invalid", "-c", "commit.gpgsign=false",
        "commit", "-qm", "test source",
    ], check=True)
    sha = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
    return repo, sha


def test_real_checkout_wins_over_event_merge_sha(repository, monkeypatch):
    repo, sha = repository
    monkeypatch.setenv("GITHUB_SHA", "f" * 40)
    assert checkout_sha(repo) == sha


def test_binds_report_without_changing_runtime_evidence(repository, tmp_path):
    repo, sha = repository
    report = tmp_path / "report.json"
    evidence = {"passed": False, "scenarios": [{"passed": False, "content": "ЛОКАЛЬНО"}], "core": {"prepared_sha256": "model-hash"}}
    report.write_text(json.dumps(evidence))
    assert bind_report(report, repo, sha) == sha
    assert json.loads(report.read_text()) == dict(evidence, git_sha=sha)


@pytest.mark.parametrize("conflict", ["expected_checkout", "existing_report"])
def test_rejects_source_conflict_without_rewriting_report(repository, tmp_path, conflict):
    repo, sha = repository
    report = tmp_path / "report.json"
    evidence = {"passed": True}
    if conflict == "existing_report":
        evidence["git_sha"] = "f" * 40
    report.write_text(json.dumps(evidence))
    original = report.read_bytes()
    with pytest.raises(ValueError):
        bind_report(report, repo, "f" * 40 if conflict == "expected_checkout" else sha)
    assert report.read_bytes() == original


def test_expected_ci_head_is_enforced(repository, monkeypatch):
    repo, sha = repository
    monkeypatch.setenv("AURORAFOX_BENCHMARK_EXPECTED_SHA", sha)
    assert checkout_sha(repo) == sha
    monkeypatch.setenv("AURORAFOX_BENCHMARK_EXPECTED_SHA", "f" * 40)
    with pytest.raises(ValueError, match="source mismatch"):
        checkout_sha(repo)


def test_missing_git_checkout_is_rejected(tmp_path, monkeypatch):
    monkeypatch.delenv("AURORAFOX_BENCHMARK_EXPECTED_SHA", raising=False)
    with pytest.raises(ValueError, match="Unable to identify"):
        checkout_sha(tmp_path)
