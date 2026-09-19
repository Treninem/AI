class_name AuroraMutationRecord
extends RefCounted

var id: String = ""
var reason: String = ""
var description: String = ""
var baseline_sha: String = ""
var candidate_sha: String = ""
var result: String = "pending"

func create(new_id: String, new_reason: String, new_description: String) -> void:
	id = new_id
	reason = new_reason
	description = new_description

func accept() -> void:
	result = "accepted"

func reject() -> void:
	result = "rejected"
