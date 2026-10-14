class_name KnowledgeIndexClient
extends RefCounted

# Optional Windows acceleration. Missing, stale and unsupported indexes always
# return control to KnowledgeStore, which remains the canonical search path.
const INDEX_PATH := "user://knowledge/knowledge.fts5.sqlite3"

# Worker/test entry point only. A full-pack build can take minutes and must
# never run on the UI thread or inside an ordinary chat request.
static func rebuild() -> Dictionary:
	if OS.get_name() != "Windows" or not FileAccess.file_exists(KnowledgeStore.DB_PATH):
		return {"ok": false}
	var runtime := _runtime_paths()
	if runtime.is_empty():
		return {"ok": false}
	var args := PackedStringArray([
		str(runtime["script"]), "build",
		"--source", ProjectSettings.globalize_path(KnowledgeStore.DB_PATH),
		"--index", ProjectSettings.globalize_path(INDEX_PATH),
	])
	var output: Array = []
	var code := OS.execute(str(runtime["python"]), args, output, false, false)
	if code != 0 or output.is_empty():
		return {"ok": false}
	var parsed = JSON.parse_string(str(output[0]))
	if not parsed is Dictionary or not bool(parsed.get("ok", false)):
		return {"ok": false}
	return {"ok": true, "indexed_rows": int(parsed.get("indexed_rows", 0))}

static func search(query: String, limit: int) -> Dictionary:
	if OS.get_name() != "Windows" or limit < 1:
		return {"ok": false}
	if not FileAccess.file_exists(KnowledgeStore.DB_PATH) or not FileAccess.file_exists(INDEX_PATH):
		return {"ok": false}
	var runtime := _runtime_paths()
	if runtime.is_empty():
		return {"ok": false}
	var args := PackedStringArray([
		str(runtime["script"]), "search",
		"--source", ProjectSettings.globalize_path(KnowledgeStore.DB_PATH),
		"--index", ProjectSettings.globalize_path(INDEX_PATH),
		"--query", query, "--limit", str(limit),
	])
	var output: Array = []
	var code := OS.execute(str(runtime["python"]), args, output, false, false)
	if code != 0 or output.is_empty():
		return {"ok": false}
	var parsed = JSON.parse_string(str(output[0]))
	if not parsed is Dictionary or not bool(parsed.get("ok", false)) or not parsed.get("results", null) is Array:
		return {"ok": false}
	var results: Array = parsed.get("results", [])
	if results.size() > limit:
		return {"ok": false}
	for item in results:
		if not item is Dictionary:
			return {"ok": false}
	return {"ok": true, "results": results}

static func _runtime_paths() -> Dictionary:
	for candidate_root in [
		OS.get_executable_path().get_base_dir().path_join("file_intelligence"),
		ProjectSettings.globalize_path("res://file_intelligence"),
	]:
		var root := str(candidate_root)
		var service: String = root.path_join("knowledge_fts_index.py")
		if not FileAccess.file_exists(service):
			continue
		var candidates := [root.path_join("python/python.exe"), root.path_join(".venv/Scripts/python.exe")]
		var test_python := OS.get_environment("AURORAFOX_KNOWLEDGE_INDEX_TEST_PYTHON")
		if not test_python.is_empty():
			candidates.push_front(test_python)
		for python in candidates:
			if FileAccess.file_exists(str(python)):
				return {"script": service, "python": str(python)}
	return {}
