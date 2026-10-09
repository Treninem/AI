extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var store = load("res://scripts/knowledge_store.gd").new()
	var escaped_solidus := '{"text":"docs\\/api","source":"manual","kind":"knowledge"}'
	var decoded = JSON.parse_string(escaped_solidus)
	if not decoded is Dictionary or str(decoded.get("text", "")) != "docs/api":
		push_error("invalid escaped-solidus fixture")
		quit(1)
		return
	if store._raw_search_row_misses(escaped_solidus, "docs/api", PackedStringArray(["docs/api"])):
		push_error("raw prefilter dropped an escaped-solidus match")
		quit(1)
		return
	if not store._raw_search_row_misses('{"text":"unrelated"}', "docs/api", PackedStringArray(["docs/api"])):
		push_error("raw prefilter failed to skip an unrelated row")
		quit(1)
		return
	print("AURORA_KNOWLEDGE_SEARCH_PREFILTER_OK")
	quit()
