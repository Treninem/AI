extends SceneTree

const BENCHMARK := preload("res://benchmarks/core/core_benchmark.gd")

func _initialize() -> void:
	var correct := [
		"Лёд плавает, потому что плотность льда меньше плотности воды.",
		"Лёд имеет меньшую плотность, чем вода.",
		"Лёд плавает в воде, потому что он менее плотный, чем вода.",
		"Лёд плавает в воде, потому что он менее плотен, чем вода.",
		"Вода плотнее льда, поэтому лёд плавает."
	]
	var wrong := [
		"Лёд плавает, потому что он легче льда, чем вода.",
		"Лёд плавает, потому что плотность воды меньше плотности льда.",
		"Лёд плавает в воде, потому что он менее плотный, чем лёд.",
		"Лёд плавает в воде, потому что он не менее плотный, чем вода.",
		"Лёд плавает в воде, потому что он не менее плотен, чем вода.",
		"Лёд плавает в воде, потому что он более плотен, чем вода.",
		"Лёд плавает благодаря меньшему давлению воды."
	]
	for answer in correct:
		if not BENCHMARK._ice_density_answer_correct(answer):
			push_error("Correct factual answer rejected")
			quit(1)
			return
	for answer in wrong:
		if BENCHMARK._ice_density_answer_correct(answer):
			push_error("Wrong factual answer accepted")
			quit(1)
			return
	print("CORE_FACTUAL_VALIDATOR_SMOKE_PASS")
	quit(0)
