extends SceneTree

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# Persistent user controls must be able to stop every autonomous mutation and
	# learning loop without touching normal chat/local inference.
	var coordinator := AuroraAutonomousCoordinator.new()
	var pipeline := CoreImprovementPipeline.new()
	var curator := AuroraLearningCurator.new()
	var settings := AutonomySettingsManager.new()
	settings.coordinator = coordinator
	settings.core_pipeline = pipeline
	settings.learning_curator = curator
	settings.settings = settings.DEFAULT_SETTINGS.duplicate(true)

	settings.settings["master_enabled"] = false
	settings._apply()
	if coordinator.autonomous_enabled or coordinator.autonomous_hot_improvements or coordinator.autonomous_research_enabled:
		_fail("Autonomy master-stop did not disable coordinator loops", 2)
		return
	if pipeline.autonomous_core_candidates:
		_fail("Autonomy master-stop did not disable core candidates", 3)
		return
	if curator.enabled:
		_fail("Autonomy master-stop did not disable autonomous learning", 4)
		return

	settings.settings["master_enabled"] = true
	settings.settings["autonomous_learning"] = true
	settings.settings["autonomous_cycles"] = true
	settings.settings["hot_improvements"] = false
	settings.settings["core_candidates"] = true
	settings._apply()
	if not coordinator.autonomous_enabled or not coordinator.autonomous_research_enabled:
		_fail("Autonomy preferences did not restore selected learning/cycle loops", 5)
		return
	if coordinator.autonomous_hot_improvements:
		_fail("Hot improvements ignored their dedicated user switch", 6)
		return
	if not pipeline.autonomous_core_candidates or not curator.enabled:
		_fail("Core candidates or learning did not respect enabled settings", 7)
		return

	# Research curation should favor higher-provenance sources and persist stable
	# fingerprints for deduplication. Personal local_documents are explicitly
	# rejected by the promotion handler (source contract below).
	var arxiv := {
		"source": "arxiv",
		"title": "Robust retrieval augmented local agents",
		"summary": "A sufficiently detailed research summary describing retrieval, evaluation, provenance, regression testing and robust local inference behavior for autonomous assistants."
	}
	var weak_reddit := {
		"source": "reddit/programming",
		"title": "idea",
		"summary": "short",
		"metadata": {"score": 0, "comments": 0}
	}
	if curator._quality_score(arxiv) <= curator.MIN_PROMOTION_SCORE:
		_fail("High-provenance research did not reach promotion threshold", 8)
		return
	if curator._quality_score(weak_reddit) >= curator.MIN_PROMOTION_SCORE:
		_fail("Low-signal community item unexpectedly reached promotion threshold", 9)
		return
	var fp1 := curator._fingerprint(arxiv)
	var fp2 := curator._fingerprint(arxiv.duplicate(true))
	if fp1.is_empty() or fp1 != fp2:
		_fail("Autonomous research deduplication fingerprint is not stable", 10)
		return
	var learned := curator._knowledge_text(arxiv)
	if not learned.begins_with("[UNTRUSTED_EXTERNAL_RESEARCH_DATA]"):
		_fail("Autonomous internet knowledge lost untrusted-data boundary", 11)
		return
	var curator_source := FileAccess.get_file_as_string("res://agent/learning_curator.gd")
	if not curator_source.contains('if source == "local_documents":'):
		_fail("Learning curator no longer protects personal local documents", 12)
		return

	# Autonomous core rewriting must remain narrowly allowlisted and keep updater,
	# permissions and its own verifier outside the model-writable surface.
	if not pipeline._target_allowed("scripts/agent_core.gd") or not pipeline._target_allowed("scripts/memory_store.gd"):
		_fail("Expected intelligence targets are missing from the core allowlist", 13)
		return
	for protected in [
		"update/update_manager.gd",
		"scripts/runtime_extension_manager.gd",
		"scripts/windows_trusted_project_bridge.gd",
		"scripts/core_improvement_pipeline.gd",
		"project.godot"
	]:
		if pipeline._target_allowed(protected):
			_fail("Protected file entered autonomous core allowlist: " + protected, 14)
			return
	if pipeline._sha256_text("AuroraFox") != "AuroraFox".sha256_text().to_lower():
		_fail("Core candidate SHA-256 helper is inconsistent", 15)
		return

	# Background updater failures must be logged/returned but must not emit the
	# user-facing update_error signal. Manual failures remain visible.
	var updater := AuroraUpdateManager.new()
	var visible_errors := [0]
	updater.update_error.connect(func(_message): visible_errors[0] = int(visible_errors[0]) + 1)
	var background := updater._fail("offline background test", false)
	if int(visible_errors[0]) != 0 or not bool(background.get("background", false)):
		_fail("Background updater error became user-blocking", 16)
		return
	var manual := updater._fail("manual update test", true)
	if int(visible_errors[0]) != 1 or bool(manual.get("background", true)):
		_fail("Manual updater error visibility contract failed", 17)
		return

	coordinator.free()
	pipeline.free()
	curator.free()
	settings.free()
	updater.free()
	print("AURORA_AUTONOMY_LEARNING_SMOKE_OK")
	quit(0)
