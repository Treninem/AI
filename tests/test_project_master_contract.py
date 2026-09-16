from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / "docs" / "PROJECT_MASTER_LOG.md"
AGENTS = ROOT / "AGENTS.md"
README = ROOT / "README.md"

LEGACY_JOURNALS = (
    ROOT / "docs" / "DEVELOPMENT_LOG.md",
    ROOT / "docs" / "WORK_COORDINATION.md",
    ROOT / "docs" / "workstreams" / "CHAT_MAIN.md",
    ROOT / "docs" / "workstreams" / "WORK_MODE.md",
    ROOT / "docs" / "workstreams" / "CODEX.md",
)


def test_single_master_log_exists_and_legacy_journals_are_retired() -> None:
    assert MASTER.is_file(), "docs/PROJECT_MASTER_LOG.md must be the single project journal"
    for path in LEGACY_JOURNALS:
        assert not path.exists(), f"Parallel project journal is forbidden: {path.relative_to(ROOT)}"


def test_agents_requires_read_claim_write_protocol() -> None:
    text = AGENTS.read_text(encoding="utf-8")
    assert "docs/PROJECT_MASTER_LOG.md" in text
    for required in (
        "Fetch the latest `main` HEAD",
        "Add an ACTIVE claim",
        "only development/coordination journal",
        "tests and GitHub Actions run IDs/results",
        "exact next step",
    ):
        assert required in text


def test_master_log_contains_continuation_and_conflict_contract() -> None:
    text = MASTER.read_text(encoding="utf-8")
    for required in (
        "ЕДИНЫЙ КАНОНИЧЕСКИЙ ЖУРНАЛ ПРОЕКТА",
        "Обязательный протокол для Chat / Work / Codex / агентов",
        "Активные работы и занятые файлы",
        "CLAIM",
        "V1.3.0.0",
        "V1.2→V1.3",
        "Следующий шаг",
        "не повторяя уже выполненную параллельную работу",
    ):
        assert required in text


def test_readme_points_to_master_and_current_release() -> None:
    text = README.read_text(encoding="utf-8")
    assert "docs/PROJECT_MASTER_LOG.md" in text
    assert "V1.3.0.0" in text
    assert "`0.4.0`" not in text
    assert "Ollama/local LLM" not in text
    assert "Ollama **не является зависимостью AuroraFox**" in text
