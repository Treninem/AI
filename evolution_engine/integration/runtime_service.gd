class_name AuroraEvolutionRuntime
extends Node

signal foundation_bound(status: Dictionary)
signal session_permission_changed(level: int, managed: bool)

const STATUS_TOOL := "aurora_evolution_status"
const ANALYZE_TOOL := "aurora_evolution_analyze"

var controller := AuroraEvolutionEngine.new()
var community_learning := AuroraCommunityLearningBridge.new()
var _bound := false
var _binding := false
var _tools
var _session_level := AuroraEvolutionPolicy.LEVEL_ANALYSIS
var _user_authorized := false
var _last_binding: Dictionary = {}

func _ready() -> void:
	controller.name = "Controller"
	add_child(controller)
	community_learning.name = "CommunityLearningBridge"
	add_child(community_learning)
	controller.set_permission_level(AuroraEvolutionPolicy.LEVEL_ANALYSIS)
	call_deferred("_bootstrap")

func _exit_tree() -> void:
	controller.set_permission_level(AuroraEvolutionPolicy.LEVEL_ANALYSIS)
	_session_level = AuroraEvolutionPolicy.LEVEL_ANALYSIS
	_user_authorized = false

func _bootstrap() -> void:
	if _binding:
		return
	_binding = true
	for _i in range(180):
		var result := bind_now()
		if bool(result.get("ok", false)):
			break
		await get_tree().process_frame
	_binding = false

func bind_now() -> Dictionary:
	var main := get_parent()
	if main == null:
		return _binding_failure("Main scene is unavailable")

	var coordinator = main.get_node_or_null("AutonomousCoordinator")
	var improver = main.get("improver")
	var extensions = main.get_node_or_null("RuntimeExtensions")
	var memory = main.get("memory")
	var ai = main.get("ai")
	var knowledge = ai.get("knowledge") if ai != null else null
	var core_pipeline = main.get_node_or_null("CoreImprovementPipeline")
	var autonomy_settings = main.get_node_or_null("AutonomySettings")
	var update_guard = main.get_node_or_null("UpdateAutonomyGuard")
	var sandbox_bridge = main.get_node_or_null("SandboxTools")
	var sandbox = sandbox_bridge.get("manager") if sandbox_bridge != null else null
	_tools = main.get("tools")

	community_learning.bind(memory)
	var foundation_status := controller.bind_foundation(
		coordinator,
		improver,
		extensions,
		memory,
		knowledge,
		core_pipeline,
		autonomy_settings,
		update_guard,
		sandbox
	)
	_bound = bool(foundation_status.get("ok", false))
	_last_binding = foundation_status.duplicate(true)
	if _bound:
		_register_read_only_tools()
		foundation_bound.emit(status())
	return status()

func status() -> Dictionary:
	var engine_status := controller.status()
	return {
		"ok": _bound and bool(engine_status.get("ok", false)),
		"bound": _bound,
		"session_permission_level": _session_level,
		"user_authorized": _user_authorized,
		"managed_session": bool(engine_status.get("managed_mode", {}).get("active", false)),
		"agent_tools": [STATUS_TOOL, ANALYZE_TOOL] if _tools_registered() else [],
		"release_authority": false,
		"binding": _last_binding.duplicate(true),
		"engine": engine_status,
		"community_learning": community_learning.status()
	}

func sync_community_now() -> Dictionary:
	# This only pulls already-sanitized observations into candidate experience.
	# It never raises Evolution permission level and never promotes Stable Core.
	return await community_learning.sync_now()

func authorize_session_level(value: int, user_confirmed: bool) -> Dictionary:
	if not user_confirmed:
		return {"ok": false, "stage": "user_confirmation", "error": "Explicit user confirmation is required"}
	if value < AuroraEvolutionPolicy.LEVEL_ANALYSIS or value > AuroraEvolutionPolicy.LEVEL_VERIFIED_ACTIVATION:
		return {"ok": false, "stage": "permission", "error": "Evolution permission level must be within 0..4"}
	_session_level = controller.set_permission_level(value)
	_user_authorized = _session_level > AuroraEvolutionPolicy.LEVEL_ANALYSIS
	session_permission_changed.emit(_session_level, bool(controller.managed_mode.status().get("active", false)))
	return {"ok": true, "permission_level": _session_level, "session_only": true, "persisted": false}

func begin_managed_session(value: int, user_confirmed: bool) -> Dictionary:
	if value < AuroraEvolutionPolicy.LEVEL_SANDBOX_EXPERIMENT:
		return {"ok": false, "stage": "permission", "error": "Managed Evolution sessions require Level 2 or higher"}
	var authorized := authorize_session_level(value, user_confirmed)
	if not bool(authorized.get("ok", false)):
		return authorized
	var entered := controller.enter_managed_mode()
	if not bool(entered.get("ok", false)):
		_reset_session_permission()
		return entered
	session_permission_changed.emit(_session_level, true)
	return {"ok": true, "permission": authorized, "managed_mode": entered}

func end_managed_session() -> Dictionary:
	var left := controller.leave_managed_mode()
	if not bool(left.get("ok", false)):
		return left
	_reset_session_permission()
	return {"ok": true, "managed_mode": left, "permission_level": _session_level}

func run_cycle_from_user(goal: String, mode := "hot", requested_target := "", requested_count := 5, user_confirmed := false) -> Dictionary:
	var gate := _confirmed_action_gate(AuroraEvolutionPolicy.LEVEL_SANDBOX_EXPERIMENT, user_confirmed)
	if not bool(gate.get("ok", false)):
		return gate
	return await controller.run_evolution_cycle(goal, mode, requested_target, requested_count)

func prepare_core_promotion_from_user(goal: String, tournament_id: String, user_confirmed := false) -> Dictionary:
	var gate := _confirmed_action_gate(AuroraEvolutionPolicy.LEVEL_PROMOTION_HANDOFF, user_confirmed)
	if not bool(gate.get("ok", false)):
		return gate
	return await controller.prepare_core_promotion(goal, tournament_id)

func activate_verified_winner_from_user(goal: String, tournament_result: Dictionary, user_confirmed := false) -> Dictionary:
	var gate := _confirmed_action_gate(AuroraEvolutionPolicy.LEVEL_VERIFIED_ACTIVATION, user_confirmed)
	if not bool(gate.get("ok", false)):
		return gate
	return controller.activate_verified_winner(goal, tournament_result)

func rollback_hot_extension_from_user(extension_id: String, reason := "manual safety rollback", user_confirmed := false) -> Dictionary:
	if not user_confirmed:
		return {"ok": false, "stage": "user_confirmation", "error": "Explicit user confirmation is required"}
	return controller.rollback_hot_extension(extension_id, reason)

func recover_stuck_cycle_from_user(reason := "manual safety recovery", user_confirmed := false) -> Dictionary:
	if not user_confirmed:
		return {"ok": false, "stage": "user_confirmation", "error": "Explicit user confirmation is required"}
	return controller.recover_stuck_cycle(reason)

func _confirmed_action_gate(required_level: int, user_confirmed: bool) -> Dictionary:
	if not _bound:
		return {"ok": false, "stage": "foundation", "error": "Evolution runtime is not bound"}
	if not user_confirmed or not _user_authorized:
		return {"ok": false, "stage": "user_confirmation", "error": "Explicit user confirmation is required for this Evolution action"}
	if _session_level < required_level:
		return {"ok": false, "stage": "permission", "error": "Evolution session permission is insufficient"}
	return {"ok": true}

func _reset_session_permission() -> void:
	_session_level = controller.set_permission_level(AuroraEvolutionPolicy.LEVEL_ANALYSIS)
	_user_authorized = false
	session_permission_changed.emit(_session_level, false)

func _register_read_only_tools() -> void:
	if _tools == null or not _tools.has_method("register_tool"):
		return
	var registered = _tools.get("tools")
	if not registered is Dictionary:
		return
	if not registered.has(STATUS_TOOL):
		_tools.register_tool(STATUS_TOOL, "Показать безопасный статус AuroraFox Evolution Engine без запуска изменений.", {}, Callable(self, "_tool_status"))
	if not registered.has(ANALYZE_TOOL):
		_tools.register_tool(ANALYZE_TOOL, "Выполнить только анализ AuroraFox Evolution Engine без мутаций, активации или продвижения.", {"goal": "string"}, Callable(self, "_tool_analyze"))

func _tools_registered() -> bool:
	if _tools == null:
		return false
	var registered = _tools.get("tools")
	return registered is Dictionary and registered.has(STATUS_TOOL) and registered.has(ANALYZE_TOOL)

func _tool_status(_args: Dictionary) -> Dictionary:
	return status()

func _tool_analyze(args: Dictionary) -> Dictionary:
	return await controller.analyze(str(args.get("goal", "")).strip_edges())

func _binding_failure(message: String) -> Dictionary:
	_bound = false
	_last_binding = {"ok": false, "missing": [message]}
	return status()
