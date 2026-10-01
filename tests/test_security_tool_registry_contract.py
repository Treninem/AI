from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS = (ROOT / "scripts" / "tool_registry.gd").read_text(encoding="utf-8")
BUILD = (ROOT / "build" / "build_windows.ps1").read_text(encoding="utf-8")
WINDOWS_CI = (ROOT / ".github" / "workflows" / "windows-package-ci.yml").read_text(encoding="utf-8")


def test_security_tool_requires_explicit_authorization_and_private_paths():
    body = TOOLS.split("func _security_configuration_check", 1)[1].split("func _security_user_path", 1)[0]
    assert 'authorized", false' in body
    assert "explicit_owner_authorization_required" in body
    assert "scope_path_denied" in body
    assert "baseline_path_denied" in body
    assert "output_path_denied" in body
    assert "--authorize" in body
    assert "OS.create_process" in body
    assert "OS.execute" not in body
    assert "await get_tree().create_timer" in body


def test_security_tool_cannot_escape_user_private_storage():
    helper = TOOLS.split("func _security_user_path", 1)[1].split("func _security_runtime_paths", 1)[0]
    assert 'value.begins_with("user://")' in helper
    assert "simplify_path()" in helper
    assert 'absolute.begins_with(root + "/")' in helper


def test_windows_package_contains_the_same_authorized_runner():
    assert '$securityRunnerSource = Join-Path $root "security_workspace\\runner.py"' in BUILD
    assert 'Copy-Item $securityRunnerSource (Join-Path $fileOut "security_runner.py") -Force' in BUILD
    assert "build\\windows\\file_intelligence\\security_runner.py" in WINDOWS_CI
    assert 'register_tool("security_configuration_check"' in TOOLS
