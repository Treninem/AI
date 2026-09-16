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


def test_computer_control_is_explicit_default_off_permission():
    client = _text("scripts/computer_client.gd")
    tools = _text("scripts/tool_registry.gd")
    assert 'static var _computer_control_enabled := false' in client
    assert 'static func set_computer_control_enabled(value: bool)' in client
    assert 'static func computer_control_enabled() -> bool' in client
    assert 'if require_computer_permission and not computer_control_enabled()' in client
    assert 'func _computer_permission() -> Dictionary' in tools
    assert 'if ComputerClient.computer_control_enabled()' in tools
    assert tools.count('var permission := _computer_permission()') >= 3


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


def test_agent_cannot_bypass_sandbox_with_public_arbitrary_process_tool():
    tools = _text("scripts/tool_registry.gd")
    assert 'register_tool("run_process"' not in tools
    assert 'func _run_process(args: Dictionary)' in tools  # fixed git helpers may reuse it internally
    assert 'register_tool("git_status"' in tools
    assert 'register_tool("git_diff"' in tools


def test_sandbox_exec_is_container_first_and_explicit_container_fails_closed():
    tools = _text("scripts/tool_registry.gd")
    assert '"mode":"string"' in tools
    assert 'mode not in ["auto", "container", "local"]' in tools
    assert '"/sandbox/container_exec"' in tools
    assert '"/sandbox/exec"' in tools
    assert tools.index('"/sandbox/container_exec"') < tools.index('"/sandbox/exec"')
    assert 'container_runtime_unavailable' in tools
    assert 'degraded_isolation' in tools
    assert 'network_isolation_enforced' in tools


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
    assert '"strict_network_isolation": false' in sandbox
    assert 'base.strict_network_isolation = bool(base.container_runtime)' in sandbox
    assert 'requested_mode == "container"' in sandbox
    assert 'container_runtime_unavailable' in sandbox
    assert 'degraded_isolation' in sandbox
    assert 'request mode=container for strict isolation' in sandbox


def test_work_guard_owns_computer_action_id_and_stops_uncertain_unsafe_results():
    agent = _text("scripts/agent_core.gd")
    work = _text("work/work_manager.gd")
    assert '"before_tool", {"step": step + 1, "tool": tool_name, "args": _safe_args(args)}, args' in agent
    assert '"after_tool", {"step": step + 1, "tool": tool_name, "result": _guard_result(tool_result)}' in agent
    assert 'decision.get("args_patch", {})' in agent
    assert 'tool_args[key] = patch[key]' in agent
    assert 'if tool_name == "computer_action"' in work
    assert 'decision["args_patch"] = {"action_id": action_id}' in work
    assert 'unsafe_action_uncertain' in work
    assert 'func _tool_result_uncertain' in work
    assert '"transport_failure"' in work
    assert '"service_unavailable"' in work
    assert 'http >= 500 or http in [408, 429]' in work


def test_uncertain_action_requires_explicit_user_acknowledgement_before_retry():
    work = _text("work/work_manager.gd")
    store = _text("work/work_store.gd")
    assert 'func acknowledge_uncertain_action(' in work
    assert 'if not bool(task.get("requires_user_action", false))' in work
    assert '"requires_user_action": false' in work
    assert '"retryable": allow_retry' in work
    assert 'if task.is_empty() or bool(task.get("requires_user_action", false))' in store
    assert 'return transition_task(project_id, task_id, STATE_QUEUED, {}, true)' in store


def test_ui_owned_overlay_is_not_changed_into_a_service_side_planner_contract():
    # UI remains a separate claim. This lane only records the integration blocker;
    # it must not solve the blocker by reintroducing a remote/service planner.
    client = _text("scripts/computer_client.gd")
    assert 'func plan(_goal: String)' in client
    assert 'func run(_goal: String' in client
    assert client.count('local_core_planning_required') >= 2
