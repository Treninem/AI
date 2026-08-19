extends SceneTree

func _init() -> void:
	var improver := SelfImprover.new()
	if SelfImprover.MIN_MUTATIONS != 3 or SelfImprover.MAX_MUTATIONS != 10:
		push_error("Mutation tournament must stay within 3..10 candidates")
		improver.free()
		quit(2)
		return
	if not improver.has_method("run_mutation_tournament") or not improver.has_method("_runtime_contract_test"):
		push_error("SelfImprover tournament/runtime verification API is missing")
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

	var valid_extension := """extends RefCounted

func aurora_extension_manifest() -> Dictionary:
	return {
		"name": "smoke",
		"description": "deterministic smoke extension",
		"tools": [{
			"name": "aurora_ext_smoke_rank",
			"description": "rank an integer",
			"schema": {"value": "int"},
			"method": "_rank"
		}]
	}

func aurora_extension_self_test() -> Dictionary:
	return {"ok": _rank({"value": 3}) == 6}

func _rank(args: Dictionary) -> int:
	return int(args.get("value", 0)) * 2
"""
	var proposal := {
		"path": "res://generated/smoke.gd",
		"content": valid_extension,
		"reason": "robust context ranking with deterministic input validation and explicit edge handling",
		"verification": "Godot compiler, manifest contract and extension self-test must pass"
	}
	var validation := improver._validate_proposal(proposal)
	if not validation.get("ok", false):
		push_error("Valid generated extension was rejected: " + JSON.stringify(validation))
		improver.free()
		quit(9)
		return
	var runtime_test := improver._runtime_contract_test(valid_extension)
	if not runtime_test.get("ok", false) or not runtime_test.get("compiled", false):
		push_error("Generated extension runtime contract test failed: " + JSON.stringify(runtime_test))
		improver.free()
		quit(10)
		return
	var declared_tools = runtime_test.get("tools", [])
	if not declared_tools is Array or "aurora_ext_smoke_rank" not in declared_tools:
		push_error("Generated extension manifest tool was not verified")
		improver.free()
		quit(11)
		return

	var broken_self_test := valid_extension.replace('return {"ok": _rank({"value": 3}) == 6}', 'return {"ok": false, "error": "intentional smoke failure"}')
	var failed := improver._runtime_contract_test(broken_self_test)
	if failed.get("ok", false):
		push_error("SelfImprover accepted a mutation whose self-test failed")
		improver.free()
		quit(12)
		return

	var score := improver._deterministic_candidate_score(
		"robust context ranking",
		proposal,
		{"ok": true, "test": {"ok": true}}
	)
	if score <= 60.0 or score > 75.0:
		push_error("Deterministic mutation score is outside expected bounds: " + str(score))
		improver.free()
		quit(13)
		return
	improver.free()
	print("AURORA_SELF_IMPROVER_SMOKE_OK tournament=3..10 runtime_contract=true")
	quit(0)
