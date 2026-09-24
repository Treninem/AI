from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
AGENTS = ROOT / "AGENTS.md"
MEMORY = ROOT / "docs" / "AURORAFOX_ENGINEERING_MEMORY.md"
MASTER = ROOT / "docs" / "PROJECT_MASTER_LOG.md"


def test_every_agent_must_read_and_update_engineering_memory() -> None:
    agents = AGENTS.read_text(encoding="utf-8")
    assert "docs/AURORAFOX_ENGINEERING_MEMORY.md" in agents
    assert "Mandatory engineering-memory protocol" in agents
    assert "Every newly confirmed blocker or materially useful workaround MUST be added" in agents
    assert "OWNER_WAIVED_NOT_EXECUTED" in agents
    assert "Never store passwords, tokens, private keys, keystores" in agents


def test_engineering_memory_is_not_a_competing_project_journal() -> None:
    agents = AGENTS.read_text(encoding="utf-8")
    memory = MEMORY.read_text(encoding="utf-8")
    assert "not a competing progress journal" in agents
    assert "Это **не второй журнал проекта**" in memory
    assert "docs/PROJECT_MASTER_LOG.md" in memory
    assert MASTER.is_file()


def test_engineering_memory_has_reusable_entry_contract() -> None:
    memory = MEMORY.read_text(encoding="utf-8")
    for field in (
        "**Симптом:**",
        "**Причина:**",
        "**Нерабочие попытки:**",
        "**Решение:**",
        "**Профилактика:**",
        "**Evidence:**",
        "**Статус:**",
    ):
        assert field in memory

    for status in ("RESOLVED", "ENVIRONMENT", "WAIVED", "ACTIVE", "INVARIANT"):
        assert status in memory


def test_critical_historical_release_and_runtime_lessons_are_pinned() -> None:
    memory = MEMORY.read_text(encoding="utf-8")
    required_ids = {
        "AF-MEM-001",  # stale branch / non-fast-forward
        "AF-MEM-005",  # master-log truncation protection
        "AF-MEM-010",  # PowerShell native stderr
        "AF-MEM-011",  # Windows PowerShell 5.1 RSA
        "AF-MEM-025",  # local emulator offline
        "AF-MEM-026",  # lost APK shell variable
        "AF-MEM-030",  # local Core error UX
        "AF-MEM-040",  # large Knowledge timeout
        "AF-MEM-051",  # firewall loopback
        "AF-MEM-053",  # child-process wait
        "AF-MEM-060",  # SMTP environment
        "AF-MEM-070",  # historical trust chain
        "AF-MEM-073",  # nested artifact layout
        "AF-MEM-074",  # GitHub 2 GiB asset limit
        "AF-MEM-075",  # idempotent draft release
        "AF-MEM-076",  # successful publication
        "AF-MEM-082",  # heartbeat and timeouts
    }
    missing = sorted(item for item in required_ids if item not in memory)
    assert not missing, f"missing pinned engineering-memory entries: {missing}"

    assert "35992779591" in memory
    assert "c3693426e34d8c94b23b622a7050f7d78831beb7" in memory
    assert "GitHub Release asset превышает 2 GiB" in memory
