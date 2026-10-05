extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var client := FileIntelligenceClient.new()
	root.add_child(client)
	var original := client.owner_limits()
	client.apply_owner_limits({"spreadsheet_max_cells": 60001, "xls_max_rows": 12001, "tree_max_items": 6001, "search_max_results": 150, "search_excerpt_chars": 2001}, false, false)
	var actual := client.owner_limits()
	assert(actual.spreadsheet_max_cells == 60001 and actual.xls_max_rows == 12001)
	assert(OS.get_environment("AURORAFOX_FILE_SPREADSHEET_MAX_CELLS") == "60001")
	assert(OS.get_environment("AURORAFOX_FILE_XLS_MAX_ROWS") == "12001")
	assert(int(ProjectSettings.get_setting("aurorafox/files/spreadsheet_max_cells")) == 60001)
	assert(actual.tree_max_items == 6001 and actual.search_max_results == 150 and actual.search_excerpt_chars == 2001)
	assert(OS.get_environment("AURORAFOX_FILE_TREE_MAX_ITEMS") == "6001")
	assert(OS.get_environment("AURORAFOX_FILE_SEARCH_MAX_RESULTS") == "150")
	assert(OS.get_environment("AURORAFOX_FILE_SEARCH_EXCERPT_CHARS") == "2001")
	client.apply_owner_limits(original, false, false)
	client.queue_free()
	print("AURORA_SPREADSHEET_OWNER_LIMITS_OK settings=true environment=true above_old_ceiling=true")
	quit(0)
