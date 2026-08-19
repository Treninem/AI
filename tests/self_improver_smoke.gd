extends SceneTree

func _init() -> void:
	var improver := SelfImprover.new()
	if improver._safe_generated_path("res://generated/new_skill.gd") != "res://generated/new_skill.gd":
		push_error("Generated module path should be allowed")
		improver.free()
		quit(2)
		return
	for denied in ["res://scripts/main.gd", "res://project.godot", "res://generated/../scripts/main.gd", "C:/secret.gd", "res://generated/config.json"]:
		if not improver._safe_generated_path(denied).is_empty():
			push_error("SelfImprover accepted protected path: " + denied)
			improver.free()
			quit(3)
			return
	if not improver._contains_unfinished_markers("extends Node\n# TODO implement later"):
		push_error("SelfImprover did not reject TODO marker")
		improver.free()
		quit(4)
		return
	if not improver._contains_unfinished_markers("class_name ExampleStub"):
		push_error("SelfImprover did not reject stub marker")
		improver.free()
		quit(5)
		return
	if improver._contains_unfinished_markers("class_name Example\nextends Node\nfunc ready_value(): return 1"):
		push_error("SelfImprover rejected normal code")
		improver.free()
		quit(6)
		return
	improver.free()
	print("AURORA_SELF_IMPROVER_SMOKE_OK")
	quit(0)
