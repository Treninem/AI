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
	var _pdfbox_dependency := "com.tom-roush:pdfbox-android:2.0.27.0"
	var _tesseract_dependency := "com.github.adaptech-cz.Tesseract4Android:tesseract4android:4.9.0"
	var _jitpack_repo := "https://jitpack.io"

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
		# Local AAR dependencies are not embedded automatically in the final
		# Godot APK. Export the PDF parser and local Tesseract runtime explicitly.
		return PackedStringArray([_pdfbox_dependency, _tesseract_dependency])

	func _get_android_dependencies_maven_repos(_platform, _debug) -> PackedStringArray:
		# Google and Maven Central are included by Godot; Tesseract4Android 4.9.0
		# is distributed through JitPack and must be resolvable by the APK export.
		return PackedStringArray([_jitpack_repo])

	func _get_name() -> String:
		return _plugin_name
