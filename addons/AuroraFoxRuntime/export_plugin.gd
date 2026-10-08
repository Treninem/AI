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
	var _tesseract_dependency := "cz.adaptech.tesseract4android:tesseract4android:4.9.0"
	var _compress_dependency := "org.apache.commons:commons-compress:1.27.1"
	var _zstd_dependency := "com.github.luben:zstd-jni:1.5.7-3@aar"
	var _xz_dependency := "org.tukaani:xz:1.10"
	var _rar_dependency := "com.github.junrar:junrar:8.0.0"
	var _xls_dependency := "org.apache.poi:poi:5.5.1"
	var _jitpack_repo := "https://jitpack.io"

	func _export_begin(features: PackedStringArray, _debug: bool, _path: String, _flags: int) -> void:
		if not features.has("android"): return
		# Coupled CLI installation precedes this hook. Configure the final app,
		# not only the plugin AAR, before AGP compresses the bundled Core.
		var build_path := "res://android/build/build.gradle"
		var source := FileAccess.get_file_as_string(build_path)
		if not source.contains("com.android.application"):
			push_error("AuroraFox: installed Android application template is missing")
			return
		var policy := FileAccess.get_file_as_string("res://tools/android_core_assets.gradle")
		if policy.is_empty():
			push_error("AuroraFox: Android Core asset policy is missing")
			return
		var policy_file := FileAccess.open("res://android/build/aurorafox_assets.gradle", FileAccess.WRITE)
		if policy_file == null:
			push_error("AuroraFox: cannot write Android Core asset policy")
			return
		policy_file.store_string(policy)
		policy_file.close()
		var marker := "apply from: 'aurorafox_assets.gradle'"
		if not source.contains(marker):
			var build_file := FileAccess.open(build_path, FileAccess.WRITE)
			if build_file == null:
				push_error("AuroraFox: cannot configure Android application assets")
				return
			build_file.store_string(source + "\n" + marker + "\n")
			build_file.close()

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
		# Godot APK. Export PDF/OCR, TAR and the Android Zstd JNI runtime explicitly.
		return PackedStringArray([_pdfbox_dependency, _tesseract_dependency, _compress_dependency, _zstd_dependency, _xz_dependency, _rar_dependency, _xls_dependency])

	func _get_android_dependencies_maven_repos(_platform, _debug) -> PackedStringArray:
		# Google and Maven Central are included by Godot; Tesseract4Android 4.9.0
		# is distributed through JitPack and must be resolvable by the APK export.
		return PackedStringArray([_jitpack_repo])

	func _get_name() -> String:
		return _plugin_name
