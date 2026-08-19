class_name SelfImprover
extends Node

signal improvement_stage(stage: String, details: Dictionary)
signal improvement_verified(result: Dictionary)
signal improvement_rejected(result: Dictionary)

const GENERATED_ROOT := "res://generated/"
const RUNTIME_GENERATED_ROOT := "user://generated/"
const MAX_GENERATED_BYTES := 512 * 1024
const MAX_PROJECT_FILES := 30000
const MAX_PROJECT_BYTES := 2 * 1024 * 1024 * 1024

var tools: ToolRegistry
var ai: AIClient

func setup(tool_registry: ToolRegistry, ai_client: AIClient) -> void:
	tools = tool_registry
	ai = ai_client

func propose_improvement(goal: String) -> Dictionary:
	if ai == null:
		return {"ok": false, "error": "AI client is not configured"}
	var prompt := """
Ты анализируешь AuroraFox — Godot 4.7.1 проект автономного локального AI.
Предложи ОДНО небольшое законченное безопасное улучшение для цели: %s

Верни ТОЛЬКО строгий JSON:
{"path":"res://generated/<filename>.gd","content":"полный готовый GDScript","reason":"что улучшает","verification":"что должно подтвердить корректность"}

Правила:
- только новый .gd внутри логического res://generated/;
- никакого TODO/FIXME/placeholder/stub/pass/implement later;
- код должен быть самодостаточным и совместимым с Godot 4.7.1;
- не меняй project.godot, autoload, секреты, обновлятор и существующее ядро;
- не удаляй файлы;
- не утверждай, что код проверен: проверку выполнит AuroraFox отдельно.
""" % goal.strip_edges()
	var result := await ai.chat([{"role":"user","content":prompt}], 0.1)
	if not result.get("ok", false): return result
	var text := str(result.get("content", "")).replace("```json", "").replace("```", "").strip_edges()
	var proposal = JSON.parse_string(text)
	if not proposal is Dictionary:
		return {"ok": false, "error": "Invalid improvement proposal JSON"}
	var validation := _validate_proposal(proposal)
	if not validation.get("ok", false): return validation
	return {"ok": true, "proposal": proposal}

func evaluate_generated_module(proposal: Dictionary) -> Dictionary:
	var validation := _validate_proposal(proposal)
	if not validation.get("ok", false):
		improvement_rejected.emit(validation)
		return validation
	if tools == null:
		return {"ok": false, "error": "Tool registry is not configured"}
	if OS.get_name() != "Windows":
		return {"ok": false, "error": "Automatic Godot 4.7.1 self-improvement verification is currently enabled on Windows only", "stage": "platform"}

	var path := str(validation.get("path", ""))
	var relative := path.trim_prefix("res://")
	var content := str(proposal.get("content", ""))
	improvement_stage.emit("workspace", {"path": path})
	var created = await tools.call_tool("workspace_create", {
		"task": "AuroraFox self-improvement verification: " + str(proposal.get("reason", "generated module")),
		"runtime": "local"
	})
	if not _ok(created): return _reject("workspace_create", created)

	improvement_stage.emit("import", {"workspace": created.get("workspace", {})})
	var imported = await tools.call_tool("workspace_import_project", {
		"project_path": "res://",
		"target": "project",
		"max_files": MAX_PROJECT_FILES,
		"max_bytes": MAX_PROJECT_BYTES
	})
	if not _ok(imported): return _reject("workspace_import_project", imported)

	improvement_stage.emit("candidate", {"path": relative})
	var written = await tools.call_tool("workspace_write", {
		"path": "project/" + relative,
		"content": content
	})
	if not _ok(written): return _reject("workspace_write", written)

	var reread = await tools.call_tool("workspace_read", {"path": "project/" + relative, "area": "work"})
	if not _ok(reread): return _reject("workspace_read", reread)
	if str(reread.get("content", "")) != content:
		return _reject("candidate_integrity", {"ok": false, "error": "Sandbox candidate differs from proposed content"})

	improvement_stage.emit("godot_test", {"cwd": "project", "version": "4.7.1"})
	var tested = await tools.call_tool("workspace_test", {"language": "gdscript", "cwd": "project"})
	if not _ok(tested): return _reject("workspace_test", tested)

	var result := {
		"ok": true,
		"verified": true,
		"path": path,
		"reason": str(proposal.get("reason", "")),
		"workspace": created.get("workspace", {}),
		"import": _compact(imported),
		"test": _compact(tested),
		"content_sha256": _sha256_text(content)
	}
	improvement_verified.emit(result)
	return result

func apply_generated_module(proposal: Dictionary) -> Dictionary:
	# "Apply" deliberately means verify + stage. It does not silently replace
	# active core. In the editor the staged module can live in res://generated/;
	# an installed app must use writable user://generated/.
	var verification := await evaluate_generated_module(proposal)
	if not verification.get("ok", false): return verification
	var logical_path := str(verification.get("path", ""))
	var stage_path := _stage_path(logical_path)
	if stage_path.is_empty(): return _reject("stage_path", {"ok": false, "error": "Cannot resolve writable stage path"})
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(stage_path.get_base_dir()))
	var write_result = await tools.call_tool("write_file", {"path": stage_path, "content": str(proposal.get("content", ""))})
	if not _ok(write_result): return _reject("stage_generated", write_result)
	var check = await tools.call_tool("read_file", {"path": stage_path})
	if not _ok(check): return _reject("stage_verify", check)
	var expected := str(proposal.get("content", ""))
	if str(check.get("content", "")) != expected:
		return _reject("stage_integrity", {"ok": false, "error": "Staged generated module differs from verified candidate"})
	return {
		"ok": true,
		"verified": true,
		"staged": true,
		"path": logical_path,
		"stage_path": stage_path,
		"sha256": _sha256_text(expected),
		"verification": verification,
		"message": "Generated module passed Godot 4.7.1 verification and was staged without activating core changes."
	}

func _stage_path(logical_path: String) -> String:
	var safe := _safe_generated_path(logical_path)
	if safe.is_empty(): return ""
	var relative := safe.trim_prefix(GENERATED_ROOT)
	var root := GENERATED_ROOT if OS.has_feature("editor") else RUNTIME_GENERATED_ROOT
	return root + relative

func _validate_proposal(proposal: Dictionary) -> Dictionary:
	var path := _safe_generated_path(str(proposal.get("path", "")))
	if path.is_empty(): return {"ok": false, "error": "Unsafe generated module path"}
	var content := str(proposal.get("content", ""))
	if content.strip_edges().is_empty(): return {"ok": false, "error": "Generated module is empty"}
	if content.to_utf8_buffer().size() > MAX_GENERATED_BYTES:
		return {"ok": false, "error": "Generated module exceeds size limit"}
	if _contains_unfinished_markers(content):
		return {"ok": false, "error": "Generated module contains unfinished placeholder/stub markers"}
	if not content.contains("extends ") and not content.contains("class_name "):
		return {"ok": false, "error": "Generated file does not look like a GDScript module"}
	return {"ok": true, "path": path}

func _safe_generated_path(value: String) -> String:
	var path := value.strip_edges().replace("\\", "/")
	if not path.begins_with(GENERATED_ROOT): return ""
	if not path.ends_with(".gd"): return ""
	var relative := path.trim_prefix(GENERATED_ROOT)
	if relative.is_empty() or relative.begins_with("/"): return ""
	if relative == ".." or relative.begins_with("../") or relative.contains("/../") or relative.contains(":"): return ""
	for part in relative.split("/", false):
		if part in ["", ".", ".."]: return ""
	return GENERATED_ROOT + relative

func _contains_unfinished_markers(content: String) -> bool:
	var lower := content.to_lower()
	var markers := [
		"todo", "fixme", "implement later", "not implemented", "placeholder",
		"example stub", "class_name examplestub", "pass #", "raise notimplemented",
		"push_error(\"not implemented", "return null # stub"
	]
	for marker in markers:
		if lower.contains(marker): return true
	return false

func _ok(value: Variant) -> bool:
	return value is Dictionary and bool(value.get("ok", false))

func _reject(stage: String, source: Variant) -> Dictionary:
	var source_dict: Dictionary = source if source is Dictionary else {"error": str(source)}
	var result := {
		"ok": false,
		"verified": false,
		"stage": stage,
		"error": str(source_dict.get("error", "Self-improvement verification failed")),
		"details": _compact(source_dict)
	}
	improvement_rejected.emit(result)
	return result

func _compact(value: Variant) -> Variant:
	if value is Dictionary:
		var out: Dictionary = value.duplicate(true)
		for key in out.keys():
			var text := str(out[key])
			if text.length() > 6000: out[key] = text.substr(0, 6000) + "…"
		return out
	if value is Array:
		var arr: Array = value
		return arr.slice(0, mini(arr.size(), 50))
	return value

func _sha256_text(text: String) -> String:
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK: return ""
	if ctx.update(text.to_utf8_buffer()) != OK: return ""
	return ctx.finish().hex_encode().to_lower()
