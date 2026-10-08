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
    catalog = TOOLS.split('register_tool("security_configuration_check"', 1)[1].split("\n", 1)[0]
    assert "output_path" not in catalog


def test_model_flag_cannot_grant_owner_consent_or_overwrite_private_files():
    assert "await _security_review_scope(scope_abs, baseline_abs)" in TOOLS
    assert "security_owner_review.call(scope_text" in TOOLS
    assert "reviewed_inputs_changed" in TOOLS
    assert "DirAccess.remove_absolute(output_abs)" not in TOOLS
    assert 'user://security/runs/' in TOOLS
    assert 'scope_file_sha256' in TOOLS
    assert 'OS.kill(pid)' in TOOLS
    main = (ROOT / "scripts/main.gd").read_text(encoding="utf-8")
    assert 'security_review_dialog.confirmed.connect' in main
    assert 'return bool(await security_review_decided)' in main
    agent = (ROOT / "scripts/agent_core.gd").read_text(encoding="utf-8")
    assert 'tools.call_tool(tool_name, args, execution_guard)' in agent


def test_global_master_stop_applies_without_an_optional_work_guard():
    body = TOOLS.split("func _security_execution_allowed", 1)[1].split("func _security_validate_evidence", 1)[0]
    assert "ComputerClient.master_enabled_from(self)" in body
    assert body.index("ComputerClient.master_enabled_from(self)") < body.index("if not guard.is_valid()")
