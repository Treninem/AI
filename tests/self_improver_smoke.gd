extends SceneTree

func _init() -> void:
	var improver := SelfImprover.new()
	if SelfImprover.MIN_MUTATIONS != 3 or SelfImprover.MAX_MUTATIONS != 10:
		push_error("Mutation tournament must stay within 3..10 candidates")
		improver.free()
		quit(2)
		return
	if not improver.has_method("run_mutation_tournament"):
		push_error("SelfImprover mutation tournament API is missing")
		improver.free()
		quit(3)
		return
	if improver._safe_generated_path("res://generated/new_skill.gd") != "res://generated/new_skill.gd":
		push_error("Generated module path should be allowed")
		improver.free()
		quit(4)
		return
	for denied in ["res://scripts/main.gd", "res://project.godot", "res://generated/../scripts/main.gd", "C:/secret.gd", "res://generated/config.json"]:
		if not improver._safe_generated_path(denied).is_empty():
			push_error("SelfImprover accepted protected path: " + denied)
			improver.free()
			quit(5)
			return
	if not improver._contains_unfinished_markers("extends Node\n# TODO implement later"):
		push_error("SelfImprover did not reject TODO marker")
		improver.free()
		quit(6)
		return
	if not improver._contains_unfinished_markers("class_name ExampleStub"):
		push_error("SelfImprover did not reject stub marker")
		improver.free()
		quit(7)
		return
	if improver._contains_unfinished_markers("class_name Example\nextends Node\nfunc ready_value(): return 1"):
		push_error("SelfImprover rejected normal code")
		improver.free()
		quit(8)
		return
	var score := improver._deterministic_candidate_score(
		"robust context ranking",
		{
			"reason": "robust context ranking with deterministic input validation and explicit edge handling",
			"verification": "Godot parser and workspace tests must pass",
			"content": "extends RefCounted\nfunc aurora_extension_manifest(): return {}\nfunc run(args):\n\tif args is Dictionary:\n\t\treturn clamp(1, 0, 1)\n\treturn 0\n"
		},
		{"ok": true, "test": {"ok": true}}
	)
	if score <= 60.0 or score > 75.0:
		push_error("Deterministic mutation score is outside expected bounds: " + str(score))
		improver.free()
		quit(9)
		return
	improver.free()
	print("AURORA_SELF_IMPROVER_SMOKE_OK tournament=3..10")
	quit(0)
