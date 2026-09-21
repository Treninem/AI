extends SceneTree

const InstallerScript = preload("res://scripts/knowledge_pack_installer.gd")
const StoreScript = preload("res://scripts/knowledge_store.gd")
const ROOT := "user://knowledge_pack_installer_smoke"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	var shard_path := ROOT.path_join("knowledge-00000.jsonl")
	var record := {"id":"pack-smoke", "title":"Aurora", "content":"AURORA PACK READY", "kind":"knowledge"}
	var shard_text := JSON.stringify(record) + "\n"
	if not _write_text_atomic(shard_path, shard_text):
		_fail("cannot write shard", 2)
		return

	var shard_bytes := shard_text.to_utf8_buffer().size()
	var manifest := {
		"schema":"aurorafox.knowledge-pack.v1",
		"pack_id":"aurorafox-smoke",
		"pack_version":"1",
		"record_schema":"aurorafox.knowledge-record.v1",
		"production":false,
		"content_bytes":len("AURORA PACK READY"),
		"file_bytes":shard_bytes,
		"record_count":1,
		"shard_limit_bytes":1024 * 1024,
		"languages":["en"],
		"domains":["test"],
		"source":{"name":"fixture", "license":"CC0-1.0", "attribution":"AuroraFox tests"},
		"shards":[{"path":"knowledge-00000.jsonl", "sha256":FileAccess.get_sha256(shard_path),
			"bytes":shard_bytes, "content_bytes":len("AURORA PACK READY"), "records":1}],
	}
	if not _write_json_atomic(ROOT.path_join("manifest.json"), manifest):
		_fail("cannot write manifest", 3)
		return

	var installer = InstallerScript.new()
	var inspected: Dictionary = installer.inspect(ROOT)
	if not bool(inspected.get("ok", false)) or int(inspected.get("shard_count", 0)) != 1:
		_fail("inspection failed: " + JSON.stringify(inspected), 4)
		return
	var installed: Dictionary = installer.install(StoreScript.new(), ROOT)
	if not bool(installed.get("ok", false)) or str(installed.get("status", "")) != "ready":
		_fail("install failed: " + JSON.stringify(installed), 5)
		return
	var resumed: Dictionary = installer.install(StoreScript.new(), ROOT)
	if not bool(resumed.get("ok", false)) or int(resumed.get("skipped_shards", 0)) != 1:
		_fail("resume/idempotence failed: " + JSON.stringify(resumed), 6)
		return

	manifest["production"] = true
	if not _write_json_atomic(ROOT.path_join("manifest.json"), manifest):
		_fail("cannot rewrite manifest", 7)
		return
	var rejected: Dictionary = installer.inspect(ROOT)
	if bool(rejected.get("ok", false)) or not str(rejected.get("error", "")).contains("below 1 GiB"):
		_fail("production floor was not enforced", 8)
		return

	var result_path := OS.get_environment("AURORAFOX_KNOWLEDGE_SMOKE_RESULT").strip_edges()
	if result_path.is_empty():
		_fail("AURORAFOX_KNOWLEDGE_SMOKE_RESULT is missing", 9)
		return
	var state_path := "user://knowledge/pack-installs/aurorafox-smoke.json"
	var proof := {
		"schema": "aurorafox.installed-knowledge-smoke.v1",
		"passed": true,
		"offline": true,
		"external_ai_required": false,
		"pack_id": "aurorafox-smoke",
		"state_path": ProjectSettings.globalize_path(state_path),
		"manifest_path": ProjectSettings.globalize_path(ROOT.path_join("manifest.json")),
		"shard_path": ProjectSettings.globalize_path(shard_path),
		"state_sha256": FileAccess.get_sha256(state_path).to_lower(),
		"manifest_sha256": FileAccess.get_sha256(ROOT.path_join("manifest.json")).to_lower(),
		"shard_sha256": FileAccess.get_sha256(shard_path).to_lower(),
	}
	if not _write_json_atomic(result_path, proof):
		_fail("cannot persist installed smoke result", 10)
		return
	print("AURORA_KNOWLEDGE_PACK_INSTALLER_OK verified=true resumable=true offline=true")
	quit(0)

func _write_text_atomic(path: String, content: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var temporary := path + ".tmp-" + str(Time.get_ticks_usec())
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.flush()
	file.close()
	if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
		DirAccess.remove_absolute(temporary)
		return false
	return DirAccess.rename_absolute(temporary, path) == OK

func _write_json_atomic(path: String, value: Dictionary) -> bool:
	return _write_text_atomic(path, JSON.stringify(value, "  ") + "\n")

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)
