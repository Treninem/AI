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
	var other_cases := [
		{"id": "factual_mars_moons", "correct": ["Марс", "Mars."], "wrong": ["Венера", "Марс и Венера"]},
		{"id": "factual_photosynthesis_gas", "correct": ["Углекислый газ", "CO₂"], "wrong": ["Кислород", "Углекислый газ и кислород"]},
		{"id": "factual_day_night", "correct": ["День и ночь сменяются, потому что Земля вращается вокруг своей оси."], "wrong": ["День и ночь сменяются из-за вращения Земли вокруг Солнца.", "Солнце вращается вокруг оси Земли.", "Земля вращается вокруг оси Солнца."]},
		{"id": "factual_first_spaceflight_year", "correct": ["1961", "1961 год."], "wrong": ["1957", "1961 или 1969"]}
	]
	for case in other_cases:
		for answer in case["correct"]:
			if not BENCHMARK._multi_fact_answer_correct(str(case["id"]), str(answer)):
				push_error("Correct multi-topic factual answer rejected: " + str(case["id"]))
				quit(1)
				return
		for answer in case["wrong"]:
			if BENCHMARK._multi_fact_answer_correct(str(case["id"]), str(answer)):
				push_error("Wrong multi-topic factual answer accepted: " + str(case["id"]))
				quit(1)
				return
	print("CORE_FACTUAL_VALIDATOR_SMOKE_PASS")
	quit(0)
