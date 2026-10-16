extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# Scores come from an isolated production MemoryStore probe on the ice task.
	# Do not touch user:// in a smoke test that can run on an owner machine.
	var ice_rows := [
		{"kind": "user_task", "content": "Почему лёд плавает в воде? Ответь одним коротким предложением.", "retrieval_score": 0.944},
		{"kind": "fact", "content": "Лёд плавает в воде, потому что его плотность меньше плотности воды.", "retrieval_score": 0.549},
		{"kind": "benchmark_fact", "content": "The AuroraFox benchmark memory marker is CEDAR-58.", "retrieval_score": 0.382}
	]
	var ice_lines := AgentCore._relevant_direct_memory_lines(ice_rows)
	var ice_prompt := " | ".join(ice_lines)
	var marker_rows := [
		{"kind": "benchmark_fact", "content": "The AuroraFox benchmark memory marker is CEDAR-58.", "retrieval_score": 0.657},
		{"kind": "user_task", "content": "Using your relevant local long-term memory, reply only with the benchmark memory marker.", "retrieval_score": 0.474}
	]
	var marker_prompt := " | ".join(AgentCore._relevant_direct_memory_lines(marker_rows))
	var passed := ice_prompt.contains("плотность меньше") and not ice_prompt.contains("CEDAR-58") and not ice_prompt.contains("Ответь одним") and marker_prompt.contains("CEDAR-58")
	if passed:
		print("DIRECT_CHAT_MEMORY_RELEVANCE_OK")
	else:
		push_error("Direct chat included stale memory or discarded relevant synthetic memory")
	quit(0 if passed else 1)
