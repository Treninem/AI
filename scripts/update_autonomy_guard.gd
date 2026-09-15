class_name UpdateAutonomyGuard
extends Node

signal autonomy_pause_changed(paused: bool, reason: String)

var updater: AuroraUpdateManager
var coordinator: AuroraAutonomousCoordinator
var core_pipeline: CoreImprovementPipeline

var _saved_hot_improvements := true
var _saved_core_candidates := true
var _paused_hot := false
var _paused_core := false
var _reason := ""

func _ready() -> void:
	call_deferred("_bootstrap")

func _bootstrap() -> void:
	for _i in range(180):
		_bind_existing()
		if updater != null and coordinator != null and core_pipeline != null:
			break
		await get_tree().process_frame
	_bind_existing()
	_connect_signals()
	_reconcile_current_state()

func _bind_existing() -> void:
	updater = get_node_or_null("/root/AuroraUpdate") as AuroraUpdateManager
	var main := get_parent()
	if main == null:
		return
	var coordinator_node := main.get_node_or_null("AutonomousCoordinator")
	if coordinator_node is AuroraAutonomousCoordinator:
		coordinator = coordinator_node
	var pipeline_node := main.get_node_or_null("CoreImprovementPipeline")
	if pipeline_node is CoreImprovementPipeline:
		core_pipeline = pipeline_node

func _connect_signals() -> void:
	if updater == null:
		return
	if not updater.update_available.is_connected(_on_update_available): updater.update_available.connect(_on_update_available)
	if not updater.no_update.is_connected(_on_no_update): updater.no_update.connect(_on_no_update)
	if not updater.download_started.is_connected(_on_download_started): updater.download_started.connect(_on_download_started)
	if not updater.update_ready.is_connected(_on_update_ready): updater.update_ready.connect(_on_update_ready)
	if not updater.update_applying.is_connected(_on_update_applying): updater.update_applying.connect(_on_update_applying)
	if not updater.update_error.is_connected(_on_update_error): updater.update_error.connect(_on_update_error)

func _reconcile_current_state() -> void:
	if updater == null:
		return
	if bool(updater.downloading):
		_pause(true, true, "signed update download in progress")
		return
	if not str(updater.downloaded_path).is_empty():
		var auto_apply := bool(updater.get_settings().get("auto_apply", true))
		_pause(auto_apply, true, "verified signed update waiting for apply")
		return
	_resume_all("no pending signed update")

func _on_update_available(_info: Dictionary) -> void:
	if updater == null:
		return
	var auto_download := bool(updater.get_settings().get("auto_download", true))
	if auto_download:
		_pause(true, true, "signed update selected")
	else:
		_pause(false, true, "new signed update available")

func _on_no_update(_version: String) -> void:
	_resume_all("already current")

func _on_download_started(_info: Dictionary) -> void:
	_pause(true, true, "signed update download in progress")

func _on_update_ready(_info: Dictionary, _path: String) -> void:
	var auto_apply := true
	if updater != null:
		auto_apply = bool(updater.get_settings().get("auto_apply", true))
	_pause(auto_apply, true, "verified signed update ready")

func _on_update_applying(_info: Dictionary) -> void:
	_pause(true, true, "signed update applying")

func _on_update_error(_message: String) -> void:
	# Update transport failures never stop AuroraFox. Resume autonomous work on
	# the currently verified local version and let the updater retry later.
	_resume_all("update unavailable; continue current local version")

func _pause(pause_hot: bool, pause_core: bool, reason: String) -> void:
	if coordinator != null and pause_hot:
		if not _paused_hot:
			_saved_hot_improvements = coordinator.autonomous_hot_improvements
		coordinator.autonomous_hot_improvements = false
		_paused_hot = true
	elif coordinator != null and _paused_hot and not pause_hot:
		coordinator.autonomous_hot_improvements = _saved_hot_improvements
		_paused_hot = false
	if core_pipeline != null and pause_core:
		if not _paused_core:
			_saved_core_candidates = core_pipeline.autonomous_core_candidates
		core_pipeline.autonomous_core_candidates = false
		_paused_core = true
	elif core_pipeline != null and _paused_core and not pause_core:
		core_pipeline.autonomous_core_candidates = _saved_core_candidates
		_paused_core = false
	_reason = reason
	autonomy_pause_changed.emit(_paused_hot or _paused_core, reason)

func _resume_all(reason: String) -> void:
	if coordinator != null and _paused_hot:
		coordinator.autonomous_hot_improvements = _saved_hot_improvements
	if core_pipeline != null and _paused_core:
		core_pipeline.autonomous_core_candidates = _saved_core_candidates
	_paused_hot = false
	_paused_core = false
	_reason = reason
	autonomy_pause_changed.emit(false, reason)

func status() -> Dictionary:
	return {
		"paused_hot_improvements": _paused_hot,
		"paused_core_candidates": _paused_core,
		"reason": _reason,
		"updater_bound": updater != null,
		"coordinator_bound": coordinator != null,
		"core_pipeline_bound": core_pipeline != null,
		"update_settings": updater.get_settings() if updater != null else {}
	}
