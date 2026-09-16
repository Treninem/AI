extends SceneTree

class FakeResearchAI:
	extends AIClient
	var imports: Array = []

	func import_knowledge_text(text: String, source := "manual", metadata: Dictionary = {}) -> Dictionary:
		imports.append({"text": text, "source": source, "metadata": metadata.duplicate(true)})
		return {"ok": true, "source": source}

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
	# rejected by the promotion handler.
	var arxiv := {
		"source": "arxiv",
		"title": "Robust retrieval augmented local agents",
		"summary": "A sufficiently detailed research summary describing retrieval, evaluation, provenance, regression testing and robust local inference behavior for autonomous assistants.",
		"url": "https://arxiv.org/abs/2609.12345?utm_source=aurora#details",
		"observed_at": "2026-09-16T07:00:00Z"
	}
	var weak_reddit := {
		"source": "reddit/programming",
		"title": "idea",
		"summary": "short",
		"url": "https://www.reddit.com/r/programming/comments/example",
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
	var canonical := curator._canonical_url(str(arxiv.get("url", "")))
	if canonical.contains("utm_source") or canonical.contains("#"):
		_fail("Research provenance URL kept tracking/fragment noise", 12)
		return
	var content_hash := curator._content_hash(arxiv)
	var same_content_other_url := arxiv.duplicate(true)
	same_content_other_url["url"] = "https://mirror.example/research/2609.12345?gclid=tracking"
	if content_hash.is_empty() or curator._content_hash(same_content_other_url) != content_hash:
		_fail("Content-level research dedupe is not URL-independent", 13)
		return

	# Collector is an observation layer only. It must never bypass the curator by
	# writing raw web/local-document results directly into long-term MemoryStore.
	var collector_source := FileAccess.get_file_as_string("res://agent/research_collector.gd")
	if collector_source.contains("memory.learn(") or collector_source.contains("if _learn(item)"):
		_fail("ResearchCollector still bypasses LearningCurator promotion authority", 14)
		return
	if not collector_source.contains('"queued_for_curation"') or not collector_source.contains('"learned": 0'):
		_fail("ResearchCollector no longer exposes observation-only curation contract", 15)
		return
	var curator_source := FileAccess.get_file_as_string("res://agent/learning_curator.gd")
	if not curator_source.contains('if source == "local_documents":'):
		_fail("Learning curator no longer protects personal local documents", 16)
		return

	# Integration-level curation contract: one strong web observation is promoted;
	# an identical-content mirror is deduplicated, weak community content is
	# rejected and a local document never enters automatic Core Knowledge.
	var fake_ai := FakeResearchAI.new()
	var gate := AuroraLearningCurator.new()
	gate.ai = fake_ai
	gate.enabled = true
	gate._seen.clear()
	gate._seen_content.clear()
	gate._stats = {"considered": 0, "promoted": 0, "rejected": 0, "duplicates": 0, "invalid_provenance": 0}
	var local_doc := {
		"source": "local_documents",
		"title": "private notes.txt",
		"summary": "Personal local notes must never be promoted by autonomous web research.",
		"url": "C:/Users/Test/Documents/private notes.txt"
	}
	gate._on_research_completed({
		"query": "robust local agents",
		"items": [arxiv, same_content_other_url, weak_reddit, local_doc]
	})
	if fake_ai.imports.size() != 1:
		_fail("Curator did not enforce single authoritative promotion path", 17)
		return
	var promoted: Dictionary = fake_ai.imports[0]
	var promoted_meta: Dictionary = promoted.get("metadata", {})
	if not bool(promoted_meta.get("untrusted_external", false)):
		_fail("Promoted research lost untrusted_external metadata", 18)
		return
	if str(promoted_meta.get("canonical_url", "")).contains("utm_source"):
		_fail("Promoted research metadata kept non-canonical URL", 19)
		return
	if str(promoted_meta.get("content_sha256", "")) != content_hash:
		_fail("Promoted research metadata lost content SHA-256", 20)
		return
	if str(promoted_meta.get("provenance_fingerprint", "")).is_empty():
		_fail("Promoted research metadata lost provenance fingerprint", 21)
		return
	if str(promoted_meta.get("evidence_tier", "")) != "research_preprint":
		_fail("Promoted research metadata lost evidence tier", 22)
		return
	var gate_stats: Dictionary = gate.status().get("stats", {})
	if int(gate_stats.get("promoted", 0)) != 1 or int(gate_stats.get("duplicates", 0)) != 1 or int(gate_stats.get("rejected", 0)) != 2:
		_fail("Curator promotion/rejection/deduplication accounting is inconsistent", 23)
		return

	# Autonomous core rewriting must remain narrowly allowlisted and keep updater,
	# permissions and its own verifier outside the model-writable surface.
	if not pipeline._target_allowed("scripts/agent_core.gd") or not pipeline._target_allowed("scripts/memory_store.gd"):
		_fail("Expected intelligence targets are missing from the core allowlist", 24)
		return
	for protected in [
		"update/update_manager.gd",
		"scripts/runtime_extension_manager.gd",
		"scripts/windows_trusted_project_bridge.gd",
		"scripts/core_improvement_pipeline.gd",
		"project.godot"
	]:
		if pipeline._target_allowed(protected):
			_fail("Protected file entered autonomous core allowlist: " + protected, 25)
			return
	if pipeline._sha256_text("AuroraFox") != "AuroraFox".sha256_text().to_lower():
		_fail("Core candidate SHA-256 helper is inconsistent", 26)
		return

	# Background updater failures must stay silent to the UI but must always emit
	# an internal attempt-failed signal so UpdateAutonomyGuard can resume work.
	var updater := AuroraUpdateManager.new()
	var visible_errors := [0]
	var attempt_failures := [0]
	var last_background := [false]
	updater.update_error.connect(func(_message): visible_errors[0] = int(visible_errors[0]) + 1)
	updater.update_attempt_failed.connect(func(_message, background):
		attempt_failures[0] = int(attempt_failures[0]) + 1
		last_background[0] = bool(background)
	)
	var background := updater._fail("offline background test", false)
	if int(visible_errors[0]) != 0 or int(attempt_failures[0]) != 1 or not bool(last_background[0]) or not bool(background.get("background", false)):
		_fail("Background updater failure did not preserve silent internal recovery contract", 27)
		return
	var manual := updater._fail("manual update test", true)
	if int(visible_errors[0]) != 1 or int(attempt_failures[0]) != 2 or bool(last_background[0]) or bool(manual.get("background", true)):
		_fail("Manual updater error visibility/internal recovery contract failed", 28)
		return

	# Regression: an update may pause hot/core improvements before a background
	# download fails. The internal failure signal must restore the saved state.
	coordinator.autonomous_hot_improvements = true
	pipeline.autonomous_core_candidates = true
	var guard := UpdateAutonomyGuard.new()
	guard.coordinator = coordinator
	guard.core_pipeline = pipeline
	guard._pause(true, true, "test update selected")
	if coordinator.autonomous_hot_improvements or pipeline.autonomous_core_candidates:
		_fail("Update guard did not pause autonomous changes", 29)
		return
	guard._on_update_attempt_failed("offline", true)
	if not coordinator.autonomous_hot_improvements or not pipeline.autonomous_core_candidates:
		_fail("Silent updater failure left autonomy paused", 30)
		return
	if bool(guard.status().get("paused_hot_improvements", true)) or bool(guard.status().get("paused_core_candidates", true)):
		_fail("Update guard status remained paused after updater failure", 31)
		return

	fake_ai.free()
	gate.free()
	coordinator.free()
	pipeline.free()
	curator.free()
	settings.free()
	updater.free()
	guard.free()
	print("AURORA_AUTONOMY_LEARNING_SMOKE_OK")
	quit(0)
