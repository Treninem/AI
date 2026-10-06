extends SceneTree
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	while EditorInterface.get_resource_filesystem().is_scanning():
		await process_frame
	var plugin_script = load("res://addons/AuroraFoxRuntime/export_plugin.gd")
	var exporter = plugin_script.AndroidExportPlugin.new()
	var build_path := "res://android/build/build.gradle"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(build_path.get_base_dir()))
	var original_exists := FileAccess.file_exists(build_path)
	var original := FileAccess.get_file_as_string(build_path) if original_exists else ""
	var policy_path := "res://android/build/aurorafox_assets.gradle"
	var policy_exists := FileAccess.file_exists(policy_path)
	var old_policy := FileAccess.get_file_as_string(policy_path) if policy_exists else ""
	var fixture := FileAccess.open(build_path, FileAccess.WRITE)
	fixture.store_string("plugins { id 'com.android.application' }\n")
	fixture.close()
	exporter._export_begin(PackedStringArray(["Android"]), false, "probe.apk", 0)
	exporter._export_begin(PackedStringArray(["Android"]), false, "probe.apk", 0)
	var result := FileAccess.get_file_as_string(build_path)
	assert(result.count("apply from: 'aurorafox_assets.gradle'") == 1)
	assert(FileAccess.get_file_as_string(policy_path) == FileAccess.get_file_as_string("res://tools/android_core_assets.gradle"))
	if original_exists:
		var restore := FileAccess.open(build_path, FileAccess.WRITE)
		restore.store_string(original)
		restore.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(build_path))
	if policy_exists:
		var restore_policy := FileAccess.open(policy_path, FileAccess.WRITE)
		restore_policy.store_string(old_policy)
		restore_policy.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(policy_path))
	exporter = null
	print("AURORA_ANDROID_ASSET_EXPORT_HOOK_OK")
	for child in root.get_children():
		if child.get_class() == "EditorNode": child.queue_free()
	await process_frame
	quit(0)
