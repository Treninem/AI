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


def test_computer_timeout_budgets_cover_bounded_service_execution():
    client = _text("scripts/computer_client.gd")
    tools = _text("scripts/tool_registry.gd")
    assert 'const SCREEN_TIMEOUT := 20.0' in client
    assert 'const ACTION_TIMEOUT := 32.0' in client
    assert 'const COMPUTER_ACTION_TIMEOUT := 32.0' in tools
    assert 'const COMPUTER_SCREEN_TIMEOUT := 20.0' in tools
    assert '_computer_json("/action", HTTPClient.METHOD_POST, payload, COMPUTER_ACTION_TIMEOUT)' in tools
    assert '_computer_json("/screen", HTTPClient.METHOD_GET, {}, COMPUTER_SCREEN_TIMEOUT)' in tools


def test_agent_cannot_bypass_sandbox_with_public_arbitrary_process_tool():
    tools = _text("scripts/tool_registry.gd")
    assert 'register_tool("run_process"' not in tools
    assert 'func _run_process(args: Dictionary)' in tools
    assert 'register_tool("git_status"' in tools
    assert 'register_tool("git_diff"' in tools


def test_sandbox_exec_is_container_first_and_local_process_fails_closed_by_default():
    tools = _text("scripts/tool_registry.gd")
    service = _text("computer/computer_service.py")
    assert '"mode":"string"' in tools
    assert 'mode not in ["auto", "container", "local"]' in tools
    assert 'if mode in ["auto", "container"]' in tools
    assert '"/sandbox/container_exec"' in tools
    assert '"/sandbox/exec"' in tools
    assert tools.index('"/sandbox/container_exec"') < tools.index('"/sandbox/exec"')
    assert 'Automatic/strict sandbox execution requires Docker/Podman' in tools
    assert 'AURORAFOX_ALLOW_DEGRADED_LOCAL_SANDBOX=1' in tools
    assert 'ALLOW_DEGRADED_LOCAL_SANDBOX' in service
    assert 'AURORAFOX_ALLOW_DEGRADED_LOCAL_SANDBOX' in service
    assert 'Degraded local process sandbox is disabled by default' in service
    assert 'degraded_local_sandbox_enabled' in service


def test_strict_container_cannot_implicitly_pull_images_from_network():
    service = _text("computer/computer_service.py")
    assert '"--pull=never"' in service
    assert '"--network", "none"' in service
    assert '"image_pull_allowed": False' in service


def test_windows_workspace_bridge_auto_mode_is_container_only():
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
    assert 'degraded_local_process_opt_in' in sandbox
    assert 'AURORAFOX_ALLOW_DEGRADED_LOCAL_SANDBOX' in sandbox
    assert 'if requested_mode in ["auto", "container"]' in sandbox
    assert 'Automatic execution requires the strict Docker/Podman sandbox' in sandbox
    assert 'degraded local fallback is disabled' in sandbox
    assert 'Explicit local mode lacks strict filesystem/network isolation' in sandbox


def test_work_guard_owns_action_id_and_tracks_whole_attempt_side_effects():
    agent = _text("scripts/agent_core.gd")
    work = _text("work/work_manager.gd")
    store = _text("work/work_store.gd")
    assert '"before_tool", {"step": step + 1, "tool": tool_name, "args": _safe_args(args)}, args' in agent
    assert '"after_tool", {"step": step + 1, "tool": tool_name, "result": _guard_result(tool_result)}' in agent
    assert 'decision.get("args_patch", {})' in agent
    assert 'tool_args[key] = patch[key]' in agent
    assert 'if tool_name == "computer_action"' in work
    assert 'decision["args_patch"] = {"action_id": action_id}' in work
    assert 'unsafe_action_seen' in work
    assert 'store.mark_attempt_unsafe(project_id, task_id)' in work
    assert 'func _attempt_is_unsafe(' in work
    assert 'func _finish_failed_execution(' in work
    assert 'func _tool_result_uncertain' in work
    assert 'http in [400, 401, 403, 404, 405, 409, 422, 423]' in work
    assert 'const SCHEMA_VERSION := 3' in store
    assert '"attempt_retry_safety": "safe"' in store
    assert 'func mark_attempt_unsafe(' in store
    assert 'legacy_attempt_retry_safety_unknown' in store


def test_uncertain_action_requires_explicit_user_acknowledgement_before_retry():
    work = _text("work/work_manager.gd")
    store = _text("work/work_store.gd")
    assert 'func acknowledge_uncertain_action(' in work
    assert 'if not bool(task.get("requires_user_action", false))' in work
    assert '"requires_user_action": false' in work
    assert '"retryable": allow_retry' in work
    assert 'if task.is_empty() or bool(task.get("requires_user_action", false))' in store
    assert 'if new_state == STATE_RUNNING and bool(task.get("requires_user_action", false))' in store
    assert 'task["attempt_retry_safety"] = "safe"' in store
    assert 'return transition_task(project_id, task_id, STATE_QUEUED, {}, true)' in store


def test_ui_owned_overlay_is_not_changed_into_a_service_side_planner_contract():
    client = _text("scripts/computer_client.gd")
    assert 'func plan(_goal: String)' in client
    assert 'func run(_goal: String' in client
    assert client.count('local_core_planning_required') >= 2


def test_action_ids_do_not_derive_from_private_service_token():
    client = _text("scripts/computer_client.gd")
    action_id_body = client.split("func _new_action_id() -> String:", 1)[1]
    assert "shared_service_token()" not in action_id_body
    assert "generate_random_bytes(16)" in action_id_body
