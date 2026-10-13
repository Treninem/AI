extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var chat = load("res://scripts/main.gd").new()
	if chat._is_core_startup_failure("Core request deadline: no_progress"):
		_fail("request deadline was misclassified as startup")
		return
	if not chat._core_failure_message("Core request deadline: no_progress").contains("не успел ответить вовремя"):
		_fail("request deadline did not receive an honest timeout message")
		return
	if not chat._is_core_startup_failure("AuroraFox Core продолжает подготовку в фоне"):
		_fail("actual startup failure was not recognized")
		return
	if not chat._is_core_startup_failure("AuroraFox Core не успел подготовиться за 120 секунд"):
		_fail("startup preparation deadline was not recognized")
		return
	if not chat._core_failure_message("AuroraFox Core продолжает подготовку в фоне").contains("запускается в фоне"):
		_fail("startup failure lost its recovery status")
		return
	if chat._core_failure_message("invalid local response").contains("запускается"):
		_fail("generic request error was misreported as startup")
		return
	chat.free()
	print("CHAT_DEADLINE_STATUS_SMOKE_PASS")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
