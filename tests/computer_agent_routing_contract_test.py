from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _text(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def test_real_scene_master_stop_node_is_bound_by_work_and_computer_clients():
    scene = _text("main.tscn")
    assert '[node name="AutonomySettings"' in scene

    client = _text("scripts/computer_client.gd")
    assert '"AutonomySettings"' in client
    assert "static func master_enabled_from" in client
    assert "static func shared_service_token" in client

    work = _text("work/work_manager.gd")
    assert "return ComputerClient.master_enabled_from(self)" in work
    assert 'get_node_or_null("AutonomySettingsManager")' not in work


def test_tool_registry_uses_local_core_planning_and_protected_primitives():
    tools = _text("scripts/tool_registry.gd")
    assert 'register_tool("computer_action"' in tools
    assert 'register_tool("computer_windows"' in tools
    assert 'register_tool("computer_screenshot"' in tools
    assert 'ComputerClient.master_enabled_from(self)' in tools
    assert 'ComputerClient.shared_service_token()' in tools
    assert 'X-AuroraFox-Computer-Token:' in tools
    assert 'X-AuroraFox-Autonomy-Allowed: 1' in tools
    assert 'local_core_planning_required' in tools
    assert 'computer_base_url + "/plan"' not in tools
    assert 'computer_base_url + "/run"' not in tools
    assert 'COMPUTER_TIMEOUT_MAX := 320.0' in tools


def test_windows_workspace_bridge_cannot_bypass_private_channel_or_master_stop():
    sandbox = _text("scripts/sandbox_manager.gd")
    assert 'ComputerClient.master_enabled_from(self)' in sandbox
    assert 'ComputerClient.shared_service_token()' in sandbox
    assert 'X-AuroraFox-Computer-Token:' in sandbox
    assert 'X-AuroraFox-Autonomy-Allowed: 1' in sandbox
    assert 'MAX_WINDOWS_EXEC_TIMEOUT := 300' in sandbox
    assert 'MAX_WINDOWS_HTTP_TIMEOUT := 320.0' in sandbox
    assert 'clampi(timeout, 1, MAX_WINDOWS_EXEC_TIMEOUT)' in sandbox
    assert '"allow_network": false' in sandbox


def test_ui_owned_overlay_is_not_changed_into_a_service_side_planner_contract():
    # UI remains a separate claim. This lane only records the integration blocker;
    # it must not solve the blocker by reintroducing a remote/service planner.
    client = _text("scripts/computer_client.gd")
    assert 'func plan(_goal: String)' in client
    assert 'func run(_goal: String' in client
    assert client.count('local_core_planning_required') >= 2
