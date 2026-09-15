class_name AuroraLocalSemanticVectorizer
extends RefCounted

const MODEL_ID := "aurorafox-local-vector-v1"
const DIMENSIONS := 256
const MAX_TOKENS := 768
const MAX_FEATURES := 4096

func embed(text: String) -> Array:
	var tokens := _tokens(text)
	var vector: Array = []
	vector.resize(DIMENSIONS)
	vector.fill(0.0)
	if tokens.is_empty():
		return vector
	var features := 0
	for i in range(mini(tokens.size(), MAX_TOKENS)):
		var token := str(tokens[i])
		_add_feature(vector, "w:" + token, 1.0)
		features += 1
		var stem := _stem(token)
		if stem != token and stem.length() >= 3:
			_add_feature(vector, "s:" + stem, 0.82)
			features += 1
		if i + 1 < tokens.size():
			_add_feature(vector, "b:" + token + "_" + str(tokens[i + 1]), 0.62)
			features += 1
		# Character n-grams make retrieval robust to Russian/English inflection,
		# typos and closely related word forms without any external model.
		if token.length() >= 4:
			var padded := "^" + token + "$"
			for n in [3, 4]:
				for start in range(maxi(0, padded.length() - n + 1)):
					_add_feature(vector, "c%d:%s" % [n, padded.substr(start, n)], 0.20 if n == 3 else 0.14)
					features += 1
					if features >= MAX_FEATURES:
						break
				if features >= MAX_FEATURES:
					break
		if features >= MAX_FEATURES:
			break
	return _normalize(vector)

func similarity(a: Array, b: Array) -> float:
	var count := mini(a.size(), b.size())
	if count <= 0:
		return 0.0
	var value := 0.0
	for i in range(count):
		value += float(a[i]) * float(b[i])
	return value

func model_info() -> Dictionary:
	return {
		"id": MODEL_ID,
		"dimensions": DIMENSIONS,
		"type": "local_feature_hash",
		"network_required": false,
		"external_runtime_required": false
	}

func _add_feature(vector: Array, feature: String, weight: float) -> void:
	var h := int(feature.hash())
	var index := posmod(h, DIMENSIONS)
	var sign_hash := int(("sign:" + feature).hash())
	var sign := -1.0 if (sign_hash & 1) == 1 else 1.0
	vector[index] = float(vector[index]) + weight * sign

func _normalize(vector: Array) -> Array:
	var norm_sq := 0.0
	for value in vector:
		norm_sq += float(value) * float(value)
	if norm_sq <= 0.0000001:
		return vector
	var scale := 1.0 / sqrt(norm_sq)
	for i in range(vector.size()):
		vector[i] = float(vector[i]) * scale
	return vector

func _tokens(text: String) -> Array[String]:
	var normalized := _normalize_text(text)
	var out: Array[String] = []
	for raw in normalized.split(" ", false):
		var token := str(raw).strip_edges()
		if token.length() >= 2:
			out.append(token)
	return out

func _normalize_text(text: String) -> String:
	var out := ""
	var previous_space := true
	for i in range(text.length()):
		var c := text.substr(i, 1).to_lower()
		var code := c.unicode_at(0)
		var alpha_num := (code >= 48 and code <= 57) or (code >= 97 and code <= 122)
		var cyrillic := code >= 0x0400 and code <= 0x052f
		if alpha_num or cyrillic:
			out += c
			previous_space = false
		elif not previous_space:
			out += " "
			previous_space = true
	return out.strip_edges()

func _stem(token: String) -> String:
	if token.length() <= 4:
		return token
	var result := token
	var first := token.unicode_at(0)
	var is_cyrillic := first >= 0x0400 and first <= 0x052f
	if is_cyrillic:
		# Conservative suffix reduction: not a linguistic stemmer, but enough to
		# map many inflected forms into a shared retrieval feature.
		for suffix in [
			"иями", "ями", "ами", "ого", "ему", "ому", "ыми", "ими", "ией", "ией", "иях",
			"ение", "ения", "ений", "ировать", "ирует", "ируют", "анный", "енная", "енные",
			"ость", "ости", "ами", "ями", "ого", "его", "ому", "ему", "ах", "ях", "ов", "ев",
			"ам", "ям", "ом", "ем", "ой", "ей", "ый", "ий", "ая", "яя", "ое", "ее", "ые", "ие",
			"а", "я", "ы", "и", "у", "ю", "е", "о"
		]:
			if result.ends_with(suffix) and result.length() - str(suffix).length() >= 4:
				return result.left(result.length() - str(suffix).length())
	else:
		for suffix in ["ization", "ations", "ation", "ments", "ment", "ingly", "edly", "ing", "ers", "er", "ies", "ed", "es", "s"]:
			if result.ends_with(suffix) and result.length() - str(suffix).length() >= 4:
				return result.left(result.length() - str(suffix).length())
	return result
