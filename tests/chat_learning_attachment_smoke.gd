extends SceneTree

class TestHost:
	extends Node
	var ai := AIClient.new()
	var memory := MemoryStore.new()
	var tools := ToolRegistry.new()
	var agent := AgentCore.new()
	var attachments := AttachmentManager.new()

	func setup_nodes() -> void:
		add_child(ai)
		add_child(memory)
		add_child(tools)
		add_child(agent)
		add_child(attachments)
		agent.setup(ai, memory, tools)

var host: TestHost
var failures: Array[String] = []
var token := ""
var knowledge_path := ""
var training_path := ""
var skills_path := ""

func _initialize() -> void:
	call_deferred("_run")

func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)

func _write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("cannot write fixture: " + path)
		return false
	file.store_string(text)
	file.close()
	return true

func _run() -> void:
	token = "CHATLEARN_%s" % str(Time.get_ticks_usec())
	host = TestHost.new()
	root.add_child(host)
	host.setup_nodes()
	await process_frame

	knowledge_path = "user://aurorafox_knowledge_%s.jsonl" % token
	training_path = "user://aurorafox_training_%s.jsonl" % token
	skills_path = "user://aurorafox_skills_%s.jsonl" % token

	if not _write_text(knowledge_path, JSON.stringify({"topic": token, "fact": "violet-cedar knowledge"}) + "\n"):
		_finish()
		return
	if not _write_text(training_path, JSON.stringify({"input": "training prompt " + token, "output": "training answer " + token}) + "\n"):
		_finish()
		return
	var skill_manifest := {"aurorafox_type": "skills"}
	var skill_record := {
		"name": "Chat import skill " + token,
		"goal_pattern": "prepare violet cedar " + token,
		"summary": "Imported through chat attachment",
		"steps": ["inspect request", "produce local result"],
		"tools": ["memory_search"],
		"confidence": 0.66,
		"source_code": "OS.execute('must never activate')"
	}
	if not _write_text(skills_path, JSON.stringify(skill_manifest) + "\n" + JSON.stringify(skill_record) + "\n"):
		_finish()
		return

	var knowledge_item := await host.attachments.analyze(knowledge_path)
	var knowledge_import: Dictionary = knowledge_item.get("learning_import", {})
	if not bool(knowledge_import.get("ok", false)):
		_fail("knowledge chat attachment import failed: " + JSON.stringify(knowledge_import))
	elif str(knowledge_import.get("type", "")) != "knowledge":
		_fail("knowledge attachment type mismatch")

	var training_item := await host.attachments.analyze(training_path)
	var training_import: Dictionary = training_item.get("learning_import", {})
	if not bool(training_import.get("ok", false)):
		_fail("training chat attachment import failed: " + JSON.stringify(training_import))
	elif str(training_import.get("type", "")) != "training":
		_fail("training attachment type mismatch")

	var skills_item := await host.attachments.analyze(skills_path)
	var skills_import: Dictionary = skills_item.get("learning_import", {})
	if not bool(skills_import.get("ok", false)):
		_fail("skills chat attachment import failed: " + JSON.stringify(skills_import))
	elif int(skills_import.get("skills", 0)) != 1:
		_fail("expected one imported skill")
	if bool(skills_import.get("auto_execute", true)):
		_fail("skill attachment must never auto-execute code")

	var verifier := KnowledgeStore.new()
	var knowledge_hits := verifier.search(token, 20)
	if knowledge_hits.is_empty():
		_fail("knowledge attachment was not searchable after import")
	var training_hits := verifier.search("training answer " + token, 20)
	if training_hits.is_empty():
		_fail("training attachment was not searchable after import")

	var skills := host.agent.experience.relevant_skills("prepare violet cedar " + token, 10)
	if skills.is_empty():
		_fail("skill attachment was not available to AgentCore ExperienceStore")
	else:
		var imported: Dictionary = skills[0]
		if float(imported.get("confidence", 1.0)) > 0.70:
			_fail("imported skill confidence exceeds untrusted import ceiling")
		if imported.has("source_code"):
			_fail("executable source field leaked into imported skill")

	var context := host.attachments.build_context([knowledge_item, training_item, skills_item])
	if not context.contains("Импорт в локальное обучение AuroraFox"):
		_fail("chat context does not report learning import result")

	_finish()

func _finish() -> void:
	for path in [knowledge_path, training_path, skills_path]:
		if not path.is_empty() and FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if failures.is_empty():
		print("AURORA_CHAT_LEARNING_ATTACHMENT_OK token=", token)
		quit(0)
	else:
		print("AURORA_CHAT_LEARNING_ATTACHMENT_FAILED ", JSON.stringify(failures))
		quit(1)
