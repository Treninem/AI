@tool
extends EditorPlugin

var export_plugin: AndroidExportPlugin

func _enter_tree() -> void:
	export_plugin = AndroidExportPlugin.new()
	add_export_plugin(export_plugin)

func _exit_tree() -> void:
	if export_plugin != null:
		remove_export_plugin(export_plugin)
	export_plugin = null

class AndroidExportPlugin extends EditorExportPlugin:
	var _plugin_name := "AuroraFoxRuntime"
	var _sherpa_name := "sherpa-onnx-1.13.4.aar"

	func _supports_platform(platform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform, debug) -> PackedStringArray:
		var variant := "debug" if debug else "release"
		var prefix := _plugin_name + "/bin/" + variant + "/"
		return PackedStringArray([
			prefix + _plugin_name + ("-debug.aar" if debug else "-release.aar"),
			prefix + _sherpa_name
		])

	func _get_android_dependencies(_platform, _debug) -> PackedStringArray:
		return PackedStringArray([])

	func _get_name() -> String:
		return _plugin_name
