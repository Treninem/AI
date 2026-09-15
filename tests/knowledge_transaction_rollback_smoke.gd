extends SceneTree

func _init() -> void:
	var root := "user://knowledge_transaction_rollback_test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	var source := root.path_join("replace_me.json")
	var store := KnowledgeStore.new()
	var transaction := KnowledgeImportTransaction.new()
	var registry := KnowledgeSourceRegistry.new()

	_cleanup_source(store, registry, source)
	var old_file := FileAccess.open(source, FileAccess.WRITE)
	if old_file == null:
		_fail("cannot create initial rollback fixture", 2)
		return
	old_file.store_string('{"fact":"OLD_ROLLBACK_MARKER","description":"stable source before failed replacement"}')
	old_file.close()

	var first := transaction.import_file(store, source, {"scope":"core_knowledge", "imported_by":"rollback_smoke"})
	if not bool(first.get("ok", false)) or str(first.get("transaction", "")) != "committed":
		_fail("initial knowledge import did not commit: %s" % str(first), 3)
		return
	var old_fingerprint := str(first.get("fingerprint_sha256", ""))
	if old_fingerprint.is_empty():
		_fail("initial source fingerprint missing", 4)
		return
	if store.search("OLD_ROLLBACK_MARKER", 4).is_empty():
		_fail("initial source is not searchable", 5)
		return

	# Make the same path large enough to use the bounded streaming JSON route.
	# A valid value is emitted first, then the malformed array fails after the
	# knowledge indexes have already been mutated. This exercises real rollback.
	var broken := FileAccess.open(source, FileAccess.WRITE)
	if broken == null:
		_fail("cannot overwrite rollback fixture", 6)
		return
	broken.store_string('{"value":"NEW_PARTIAL_MARKER","broken":[1,2,')
	var block := " ".repeat(1024 * 1024)
	for _i in range(9):
		broken.store_string(block)
	broken.store_string('}')
	broken.close()

	var failed := transaction.import_file(store, source, {"scope":"core_knowledge", "imported_by":"rollback_smoke"})
	if bool(failed.get("ok", false)):
		_fail("malformed replacement unexpectedly committed", 7)
		return
	if str(failed.get("transaction", "")) != "rolled_back":
		_fail("failed replacement did not roll back: %s" % str(failed), 8)
		return
	if str(failed.get("transaction_mode", "")) != "source_scoped_journal":
		_fail("source-scoped journal was not used", 9)
		return
	if store.search("OLD_ROLLBACK_MARKER", 4).is_empty():
		_fail("old knowledge was not restored after partial failure", 10)
		return
	if not store.search("NEW_PARTIAL_MARKER", 4).is_empty():
		_fail("partially imported replacement survived rollback", 11)
		return

	var restored_record := registry.record_for_source(source)
	if str(restored_record.get("fingerprint_sha256", "")) != old_fingerprint:
		_fail("registry fingerprint was not restored", 12)
		return
	for journal in [KnowledgeImportTransaction.DB_BACKUP, KnowledgeImportTransaction.STRUCTURED_BACKUP, KnowledgeImportTransaction.REGISTRY_BACKUP]:
		if FileAccess.file_exists(journal):
			_fail("transaction journal was not cleaned: %s" % journal, 13)
			return

	_cleanup_source(store, registry, source)
	if FileAccess.file_exists(source):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(source))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root))
	print("KNOWLEDGE_TRANSACTION_ROLLBACK_SMOKE_OK old_restored=true partial_removed=true source_scoped=true")
	quit(0)

func _cleanup_source(store: KnowledgeStore, registry: KnowledgeSourceRegistry, source: String) -> void:
	store.remove_source(source)
	registry.remove_source(source)

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)
