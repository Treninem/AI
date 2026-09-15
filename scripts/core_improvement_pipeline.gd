class_name CoreImprovementPipeline
extends Node

signal core_candidate_started(goal: String, target: String)
signal core_candidate_verified(result: Dictionary)
signal core_candidate_rejected(result: Dictionary)

const CANDIDATE_ROOT := "user://core_candidates"
const STATE_PATH := "user://core_candidates/state.json"
const MAX_SOURCE_BYTES := 1024 * 1024
const MAX_HISTORY := 30
const CORE_TARGETS := [
	"scripts/cognition_layer.gd",
	"scripts/agent_core.gd",
	"scripts/memory_store.gd",
	"agent/goals.gd"
]
const NEVER_TOUCH_PREFIXES := [
	"update/", "api/", "addons/", "core_runtime/", "models/", ".github/",
	"scripts/windows_trusted_project_bridge.gd", "scripts/runtime_extension_manager.gd",
	"scripts/core_improvement_pipeline.gd"
]

@export var autonomous_core_candidates := true
@export var auto_apply_dev_checkout := true
@export_range(3600.0, 604800.0, 60.0) var candidate_cooldown_seconds := 21600.0

var ai: AIClient
var tools: ToolRegistry
var coordinator: AuroraAutonomousCoordinator
var _running := false
var _last_candidate_unix := 0.0
var _history: Array = []

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CANDIDATE_ROOT))
	_load_state()
	call_deferred("_bootstrap")

func _bootstrap() -> void:
	for _i in range(180):
		_bind_existing()
		if ai != null and tools != null:
			break
		await get_tree().process_frame
	_bind_existing()
	_register_tools()
	if coordinator != null and not coordinator.autonomous_cycle_completed.is_connected(_on_autonomous_cycle_completed):
		coordinator.autonomous_cycle_completed.connect(_on_autonomous_cycle_completed)

func _bind_existing() -> void:
	var main := get_parent()
	if main == null:
		return
	var value: Variant = main.get("ai")
	if value is AIClient:
		ai = value
	value = main.get("tools")
	if value is ToolRegistry:
		tools = value
	var node := main.get_node_or_null("AutonomousCoordinator")
	if node is AuroraAutonomousCoordinator:
		coordinator = node

func _register_tools() -> void:
	if tools == null:
		return
	if not tools.tools.has("aurora_core_candidate"):
		tools.register_tool(
			"aurora_core_candidate",
			"Создать, проверить и безопасно подготовить улучшение разрешённой части ядра AuroraFox.",
			{"goal":"string", "target":"string"},
			Callable(self, "_tool_candidate")
		)
	if not tools.tools.has("aurora_core_candidate_status"):
		tools.register_tool(
			"aurora_core_candidate_status",
			"Показать историю проверенных кандидатов улучшения ядра AuroraFox.",
			{},
			Callable(self, "_tool_status")
		)

func _tool_candidate(args: Dictionary) -> Dictionary:
	return await run_candidate(str(args.get("goal", "")).strip_edges(), str(args.get("target", "")).strip_edges())

func _tool_status(_args: Dictionary) -> Dictionary:
	return status()

func _on_autonomous_cycle_completed(report: Dictionary) -> void:
	if not autonomous_core_candidates or _running or OS.get_name() != "Windows":
		return
	if not bool(report.get("ok", false)):
		return
	if Time.get_unix_time_from_system() - _last_candidate_unix < candidate_cooldown_seconds:
		return
	if _signed_update_busy():
		return
	var goal := str(report.get("goal", "")).strip_edges()
	if goal.is_empty():
		return
	call_deferred("_run_automatic_candidate", goal)

func _run_automatic_candidate(goal: String) -> void:
	await run_candidate(goal)

func run_candidate(goal: String, requested_target := "") -> Dictionary:
	if _running:
		return {"ok": false, "error": "core candidate pipeline is already running"}
	if OS.get_name() != "Windows":
		return {"ok": false, "error": "core source verification currently runs on Windows", "platform": OS.get_name()}
	_bind_existing()
	if ai == null or tools == null:
		return {"ok": false, "error": "AuroraFox core candidate dependencies are not ready"}
	if not await ai.is_available():
		return {"ok": false, "error": "local AuroraFox Core inference is not ready"}
	if _signed_update_busy():
		return {"ok": false, "error": "signed product update has priority", "deferred": true}
	var clean_goal := goal.strip_edges()
	if clean_goal.is_empty():
		clean_goal = "Повысить устойчивость, качество рассуждений и полезность AuroraFox без регрессий"
	var target := _select_target(clean_goal, requested_target)
	if target.is_empty():
		return {"ok": false, "error": "target is outside the autonomous core allowlist"}
	var source_result := _read_res_source(target)
	if not bool(source_result.get("ok", false)):
		return source_result
	var original := str(source_result.get("content", ""))
	_running = true
	core_candidate_started.emit(clean_goal, target)
	var proposal_result := await _propose(clean_goal, target, original)
	if not bool(proposal_result.get("ok", false)):
		return _finish_rejected(proposal_result)
	var proposal: Dictionary = proposal_result.get("proposal", {})
	var validation := _validate_candidate(target, original, proposal)
	if not bool(validation.get("ok", false)):
		return _finish_rejected(validation)
	var verification := await _verify_in_workspace(clean_goal, target, str(proposal.get("content", "")))
	if not bool(verification.get("ok", false)):
		return _finish_rejected(verification)
	var stored := _store_candidate(clean_goal, target, original, proposal, verification)
	if not bool(stored.get("ok", false)):
		return _finish_rejected(stored)

	var result := {
		"ok": true,
		"goal": clean_goal,
		"target": target,
		"candidate_id": stored.get("candidate_id", ""),
		"candidate_path": stored.get("candidate_path", ""),
		"manifest_path": stored.get("manifest_path", ""),
		"base_sha256": _sha256_text(original),
		"candidate_sha256": _sha256_text(str(proposal.get("content", ""))),
		"reason": str(proposal.get("reason", "")).substr(0, 2000),
		"verified": true,
		"verification": _compact(verification),
		"promotion": "signed_update",
		"applied_to_dev_checkout": false
	}

	# A source checkout launched from the Godot editor can safely receive the
	# already-tested file: project_apply_file creates a backup and verifies SHA.
	# Packaged applications never rewrite their signed runtime in-place; they
	# keep the candidate for the signed updater instead.
	if OS.has_feature("editor") and auto_apply_dev_checkout:
		var applied = await tools.call_tool("project_apply_file", {
			"project_path": "res://",
			"relative_path": target,
			"sandbox_path": verification.get("sandbox_path", "")
		})
		result["apply"] = _compact(applied)
		result["applied_to_dev_checkout"] = bool(applied is Dictionary and applied.get("ok", false))
		if bool(result.get("applied_to_dev_checkout", false)):
			result["promotion"] = "dev_checkout_with_backup_then_signed_update"
			if tools.tools.has("index_project"):
				result["reindex"] = _compact(await tools.call_tool("index_project", {"path":"res://", "max_files":30000, "force":false}))

	_last_candidate_unix = Time.get_unix_time_from_system()
	_history.append(_history_entry(result))
	_trim_history()
	_save_state()
	_running = false
	core_candidate_verified.emit(result)
	return result

func _propose(goal: String, target: String, original: String) -> Dictionary:
	var prompt := """
Ты улучшаешь ОДИН разрешённый файл собственного ядра AuroraFox. Работа будет проверена на полной копии проекта Godot 4.7.1 до применения.
Цель: %s
Файл: %s

Верни ТОЛЬКО строгий JSON:
{"path":"%s","content":"ПОЛНЫЙ новый текст файла","reason":"что реально улучшено","verification":"какие регрессии особенно важно проверить"}

Правила:
- сохраняй назначение файла и совместимость всех публичных методов/сигналов, если изменение интерфейса не абсолютно необходимо;
- не удаляй существующие функции ради упрощения;
- не трогай updater, подписи, sandbox, разрешения, секреты, project.godot или другие файлы;
- не добавляй обходы ограничений, скрытые сетевые каналы, произвольное выполнение команд или ослабление проверок;
- не используй TODO/FIXME/placeholder;
- улучшение должно быть измеримым: устойчивость, качество, память, планирование, отказоустойчивость или производительность;
- не утверждай, что тесты прошли: их запустит AuroraFox независимо.

Текущий файл:
--- BEGIN CURRENT SOURCE ---
%s
--- END CURRENT SOURCE ---
""" % [goal, target, target, original]
	var response := await ai.chat([{"role":"user", "content":prompt}], 0.18)
	if not bool(response.get("ok", false)):
		return {"ok": false, "stage": "proposal", "error": str(response.get("error", "local proposal generation failed"))}
	var text := str(response.get("content", "")).replace("```json", "").replace("```", "").strip_edges()
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {"ok": false, "stage": "proposal", "error": "core improvement proposal is not valid JSON"}
	return {"ok": true, "proposal": parsed}

func _validate_candidate(target: String, original: String, proposal: Dictionary) -> Dictionary:
	if str(proposal.get("path", "")) != target:
		return {"ok": false, "stage": "validation", "error": "candidate attempted to change a different path"}
	var content := str(proposal.get("content", ""))
	if content.strip_edges().is_empty():
		return {"ok": false, "stage": "validation", "error": "candidate source is empty"}
	if content.to_utf8_buffer().size() > MAX_SOURCE_BYTES:
		return {"ok": false, "stage": "validation", "error": "candidate source exceeds size limit"}
	if content == original:
		return {"ok": false, "stage": "validation", "error": "candidate does not change the source"}
	var lower := content.to_lower()
	for marker in ["todo", "fixme", "implement later", "placeholder"]:
		if lower.contains(marker):
			return {"ok": false, "stage": "validation", "error": "candidate contains unfinished marker", "marker": marker}
	var old_class := _line_with_prefix(original, "class_name ")
	var new_class := _line_with_prefix(content, "class_name ")
	if not old_class.is_empty() and old_class != new_class:
		return {"ok": false, "stage": "validation", "error": "candidate changed class_name contract", "expected": old_class, "actual": new_class}
	var old_extends := _line_with_prefix(original, "extends ")
	var new_extends := _line_with_prefix(content, "extends ")
	if not old_extends.is_empty() and old_extends != new_extends:
		return {"ok": false, "stage": "validation", "error": "candidate changed base class contract", "expected": old_extends, "actual": new_extends}
	return {"ok": true}

func _verify_in_workspace(goal: String, target: String, content: String) -> Dictionary:
	for required in ["workspace_create", "workspace_import_project", "workspace_write", "workspace_read", "workspace_test", "project_compare_file"]:
		if not tools.tools.has(required):
			return {"ok": false, "stage": "workspace", "error": "required verification tool missing", "tool": required}
	var created = await tools.call_tool("workspace_create", {"task":"AuroraFox core candidate: " + goal, "runtime":"local"})
	if not _ok(created): return _failed("workspace_create", created)
	var imported = await tools.call_tool("workspace_import_project", {"project_path":"res://", "target":"project", "max_files":30000, "max_bytes":2147483648})
	if not _ok(imported): return _failed("workspace_import_project", imported)
	var sandbox_path := "project/" + target
	var written = await tools.call_tool("workspace_write", {"path":sandbox_path, "content":content})
	if not _ok(written): return _failed("workspace_write", written)
	var reread = await tools.call_tool("workspace_read", {"path":sandbox_path, "area":"work"})
	if not _ok(reread): return _failed("workspace_read", reread)
	if str(reread.get("content", "")) != content:
		return {"ok": false, "stage": "candidate_integrity", "error": "workspace candidate differs from proposed source"}
	var tested = await tools.call_tool("workspace_test", {"language":"gdscript", "cwd":"project"})
	if not _ok(tested): return _failed("workspace_test", tested)
	var compared = await tools.call_tool("project_compare_file", {"project_path":"res://", "relative_path":target, "sandbox_path":sandbox_path})
	if not _ok(compared): return _failed("project_compare_file", compared)
	if not bool(compared.get("changed", false)):
		return {"ok": false, "stage": "project_compare_file", "error": "verified candidate is identical to current source"}
	return {
		"ok": true,
		"verified": true,
		"workspace": _compact(created.get("workspace", {})),
		"import": _compact(imported),
		"test": _compact(tested),
		"compare": _compact(compared),
		"sandbox_path": sandbox_path,
		"verification_mode": "full_project_godot_4_7_1_plus_hash_compare"
	}

func _store_candidate(goal: String, target: String, original: String, proposal: Dictionary, verification: Dictionary) -> Dictionary:
	var content := str(proposal.get("content", ""))
	var candidate_sha := _sha256_text(content)
	var candidate_id := "%d_%s" % [int(Time.get_unix_time_from_system()), candidate_sha.substr(0, 12)]
	var root := CANDIDATE_ROOT.path_join(candidate_id)
	var candidate_path := root.path_join(target)
	var manifest_path := root.path_join("candidate.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(candidate_path.get_base_dir()))
	var candidate_file := FileAccess.open(candidate_path, FileAccess.WRITE)
	if candidate_file == null:
		return {"ok": false, "stage": "store", "error": "cannot store verified core candidate"}
	candidate_file.store_string(content)
	candidate_file.close()
	var manifest := {
		"candidate_id": candidate_id,
		"goal": goal,
		"target": target,
		"base_sha256": _sha256_text(original),
		"candidate_sha256": candidate_sha,
		"reason": str(proposal.get("reason", "")).substr(0, 4000),
		"requested_verification": str(proposal.get("verification", "")).substr(0, 3000),
		"verified": true,
		"verification": _compact(verification),
		"created_at": Time.get_datetime_string_from_system(true),
		"promotion": "signed_update"
	}
	var manifest_file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if manifest_file == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate_path))
		return {"ok": false, "stage": "store", "error": "cannot store core candidate manifest"}
	manifest_file.store_string(JSON.stringify(manifest, "  "))
	manifest_file.close()
	if _sha256_file(candidate_path) != candidate_sha:
		return {"ok": false, "stage": "store", "error": "stored candidate failed SHA-256 integrity check"}
	return {"ok": true, "candidate_id":candidate_id, "candidate_path":candidate_path, "manifest_path":manifest_path}

func _select_target(goal: String, requested: String) -> String:
	var request := requested.trim_prefix("res://").replace("\\", "/")
	if not request.is_empty():
		return request if _target_allowed(request) else ""
	var q := goal.to_lower()
	if _contains_any(q, ["памят", "memory", "retriev", "знан"]): return "scripts/memory_store.gd"
	if _contains_any(q, ["план", "reason", "рассуж", "cognit", "провер"]): return "scripts/cognition_layer.gd"
	if _contains_any(q, ["цель", "goal", "приоритет"]): return "agent/goals.gd"
	return "scripts/agent_core.gd"

func _target_allowed(path: String) -> bool:
	if path not in CORE_TARGETS:
		return false
	for prefix in NEVER_TOUCH_PREFIXES:
		if path == prefix or path.begins_with(prefix):
			return false
	return true

func _read_res_source(target: String) -> Dictionary:
	if not _target_allowed(target):
		return {"ok": false, "error": "target is not allowed"}
	var path := "res://" + target
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "cannot read core source", "path": target}
	if file.get_length() > MAX_SOURCE_BYTES:
		file.close()
		return {"ok": false, "error": "core source exceeds size limit", "path": target}
	var content := file.get_as_text()
	file.close()
	return {"ok": true, "content": content}

func _signed_update_busy() -> bool:
	var update_node := get_node_or_null("/root/AuroraUpdate")
	if update_node == null:
		return false
	if bool(update_node.get("checking")) or bool(update_node.get("downloading")):
		return true
	return not str(update_node.get("downloaded_path")).is_empty()

func status() -> Dictionary:
	return {
		"running": _running,
		"autonomous_core_candidates": autonomous_core_candidates,
		"auto_apply_dev_checkout": auto_apply_dev_checkout,
		"candidate_cooldown_seconds": candidate_cooldown_seconds,
		"last_candidate_unix": _last_candidate_unix,
		"targets": CORE_TARGETS.duplicate(),
		"history": _history.duplicate(true)
	}

func _finish_rejected(result: Dictionary) -> Dictionary:
	_running = false
	var row := result.duplicate(true)
	row["ok"] = false
	row["rejected_at"] = Time.get_datetime_string_from_system(true)
	_history.append(_history_entry(row))
	_trim_history()
	_save_state()
	core_candidate_rejected.emit(row)
	return row

func _history_entry(result: Dictionary) -> Dictionary:
	return {
		"ok": bool(result.get("ok", false)),
		"goal": str(result.get("goal", "")).substr(0, 1000),
		"target": str(result.get("target", "")),
		"candidate_id": str(result.get("candidate_id", "")),
		"candidate_sha256": str(result.get("candidate_sha256", "")),
		"verified": bool(result.get("verified", false)),
		"promotion": str(result.get("promotion", "")),
		"applied_to_dev_checkout": bool(result.get("applied_to_dev_checkout", false)),
		"error": str(result.get("error", "")).substr(0, 1000),
		"time": Time.get_datetime_string_from_system(true)
	}

func _trim_history() -> void:
	if _history.size() > MAX_HISTORY:
		_history = _history.slice(_history.size() - MAX_HISTORY, _history.size())

func _load_state() -> void:
	var file := FileAccess.open(STATE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return
	_last_candidate_unix = float(parsed.get("last_candidate_unix", 0.0))
	var rows = parsed.get("history", [])
	if rows is Array:
		_history = rows

func _save_state() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CANDIDATE_ROOT))
	var file := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"last_candidate_unix": _last_candidate_unix,
		"history": _history,
		"updated_at": Time.get_datetime_string_from_system(true)
	}, "  "))
	file.close()

func _line_with_prefix(text: String, prefix: String) -> String:
	for line in text.split("\n"):
		var clean := str(line).strip_edges()
		if clean.begins_with(prefix):
			return clean
	return ""

func _contains_any(text: String, needles: Array) -> bool:
	for needle in needles:
		if text.contains(str(needle)):
			return true
	return false

func _ok(value: Variant) -> bool:
	return value is Dictionary and bool(value.get("ok", false))

func _failed(stage: String, value: Variant) -> Dictionary:
	return {"ok": false, "stage": stage, "error": str(value.get("error", "verification failed")) if value is Dictionary else "verification failed", "details": _compact(value)}

func _compact(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for key in value.keys():
			var k := str(key)
			if k in ["content", "source", "raw", "stdout", "stderr"]:
				continue
			out[k] = _compact(value[key])
		return out
	if value is Array:
		var out_array: Array = []
		for item in value.slice(0, mini(value.size(), 24)):
			out_array.append(_compact(item))
		return out_array
	return value

func _sha256_text(text: String) -> String:
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if ctx.update(text.to_utf8_buffer()) != OK:
		return ""
	return ctx.finish().hex_encode().to_lower()

func _sha256_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK:
		file.close()
		return ""
	while file.get_position() < file.get_length():
		ctx.update(file.get_buffer(mini(1024 * 1024, file.get_length() - file.get_position())))
	file.close()
	return ctx.finish().hex_encode().to_lower()
