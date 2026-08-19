class_name ApiPrivateExperienceStore
extends ExperienceStore

func _ready() -> void:
	# External API conversations must not load the desktop owner's private
	# skills/checkpoints/failures and must not persist their own raw task data.
	skills = []
	checkpoints = []
	failures = []

func _save_array(_path: String, _data: Array) -> void:
	# Keep the request-local experience ephemeral.
	pass
