extends SceneTree

# One pinned public shard, always under an isolated APPDATA/LOCALAPPDATA profile.
const EXPECTED_BYTES := 33529381
const EXPECTED_SHA := "538f8ddbabc1dd6eeb7a16f1ba182636eaeaacd8339d2aae461fe663c64fa15a"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var source := OS.get_environment("AURORAFOX_PUBLIC_SHARD_PATH").strip_edges()
	var db_path := ProjectSettings.globalize_path(KnowledgeStore.DB_PATH)
	if source.is_empty() or not FileAccess.file_exists(source):
		_finish(false, "public shard missing", {}, 2)
		return
	if not db_path.to_lower().contains("public-shard-normalized-profile"):
		_finish(false, "test profile isolation missing", {}, 2)
		return
	var input := FileAccess.open(source, FileAccess.READ)
	if input == null:
		_finish(false, "public shard cannot be opened", {}, 2)
		return
	var input_bytes := input.get_length()
	input.close()
	if input_bytes != EXPECTED_BYTES or FileAccess.get_sha256(source).to_lower() != EXPECTED_SHA:
		_finish(false, "public shard identity mismatch", {}, 2)
		return
	var started := Time.get_ticks_msec()
	var result := KnowledgeStore.new().import_json_lines_file(source, {
		"scope": "core_knowledge",
		"imported_by": "public_shard_normalization_probe",
	})
	var db_bytes := 0
	var normalized := FileAccess.open(KnowledgeStore.DB_PATH, FileAccess.READ)
	if normalized != null:
		db_bytes = normalized.get_length()
		normalized.close()
	var summary := {
		"source_bytes": input_bytes,
		"records": int(result.get("records", -1)),
		"chunks": int(result.get("chunks", -1)),
		"normalized_jsonl_bytes": db_bytes,
		"elapsed_ms": Time.get_ticks_msec() - started,
	}
	_finish(bool(result.get("ok", false)), "" if bool(result.get("ok", false)) else "normalization failed", summary, 0 if bool(result.get("ok", false)) else 3)


func _finish(ok: bool, error: String, summary: Dictionary, code: int) -> void:
	var report := {"ok": ok, "error": error, "summary": summary}
	print("PUBLIC_SHARD_NORMALIZATION_PROBE ", JSON.stringify(report))
	quit(code)
