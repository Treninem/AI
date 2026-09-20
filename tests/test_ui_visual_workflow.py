from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_ui_godot_bootstrap_retries_transient_release_downloads_and_validates_archive() -> None:
    workflow = (ROOT / ".github/workflows/ui-visual-ci.yml").read_text(encoding="utf-8")
    assert "actions/cache/restore@v4" in workflow
    assert "actions/cache/save@v4" in workflow
    assert "aurorafox-godot-linux-4.7.1-stable-a13da4feb" in workflow
    assert "--retry-all-errors" in workflow
    assert "--retry 8" in workflow
    assert "--http1.1" in workflow
    assert "--connect-timeout 30" in workflow
    assert "--retry-max-time 300" in workflow
    assert 'unzip -tq "$archive"' in workflow
    assert "curl -L --fail --retry 3" not in workflow
