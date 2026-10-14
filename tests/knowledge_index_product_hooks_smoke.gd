extends SceneTree

const IndexClientScript = preload("res://scripts/knowledge_index_client.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_path := ProjectSettings.globalize_path(KnowledgeStore.DB_PATH)
	if not source_path.to_lower().contains("index-product-hooks-profile"):
		_fail("isolated synthetic profile required")
		return
	var service := root.get_node_or_null("AuroraKnowledgeIndex")
	if service == null or service._pid != 0:
		_fail("index service was missing or started before mutation")
		return
	var client := AIClient.new()
	root.add_child(client)
	var imported: Dictionary = client.import_knowledge_text("Mars has two moons named Phobos and Deimos.", "synthetic://hook")
	if not bool(imported.get("ok", false)):
		_fail("AIClient synthetic import failed")
		return
	if not await _wait_for_build(service):
		_fail("successful import did not produce a background index")
		return
	var indexed: Dictionary = IndexClientScript.search("mars moons", 8)
	if not bool(indexed.get("ok", false)) or indexed.get("results", []).is_empty():
		_fail("imported synthetic fact was not indexed")
		return
	var removed: Dictionary = client.remove_knowledge_source("synthetic://hook")
	if not bool(removed.get("ok", false)) or int(removed.get("removed", 0)) < 1:
		_fail("synthetic source removal failed")
		return
	if not await _wait_for_build(service):
		_fail("successful removal did not rebuild index")
		return
	indexed = IndexClientScript.search("mars moons", 8)
	if not bool(indexed.get("ok", false)) or not indexed.get("results", []).is_empty():
		_fail("removed source remained in indexed results")
		return
	print("KNOWLEDGE_INDEX_PRODUCT_HOOKS_SMOKE_PASS")
	quit(0)

func _wait_for_build(service: Node) -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	await process_frame
	while (service.is_building() or service._pending) and Time.get_ticks_msec() < deadline:
		await process_frame
	return not service.is_building() and not service._pending and FileAccess.file_exists(IndexClientScript.INDEX_PATH)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
