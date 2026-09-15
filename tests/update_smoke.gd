extends SceneTree

func _init() -> void:
	var updater := AuroraUpdateManager.new()
	if updater == null:
		push_error("AuroraUpdateManager failed to instantiate")
		quit(2)
		return

	var defaults: Dictionary = AuroraUpdateManager.DEFAULT_SETTINGS
	if not bool(defaults.get("auto_check", false)):
		push_error("Updater auto_check must be enabled by default")
		quit(3)
		return
	if not bool(defaults.get("auto_download", false)):
		push_error("Updater auto_download must be enabled by default")
		quit(4)
		return
	if not bool(defaults.get("auto_apply", false)):
		push_error("Updater auto_apply must be enabled by default")
		quit(5)
		return
	if int(defaults.get("check_interval_hours", 0)) != 1:
		push_error("Updater should check stable releases hourly by default")
		quit(6)
		return

	if updater._compare_versions("0.4.1", "0.4.0") != 1:
		push_error("Updater failed newer-version comparison")
		quit(7)
		return
	if updater._compare_versions("v0.4.0", "0.4.0") != 0:
		push_error("Updater failed equal-version comparison")
		quit(8)
		return
	if updater._compare_versions("0.3.99", "0.4.0") != -1:
		push_error("Updater failed older-version comparison")
		quit(9)
		return
	# A client that already contains the updater must be able to jump straight
	# from an arbitrarily old semantic version to a current multi-part version.
	for legacy in ["0.0.1", "0.1", "0.4.0", "1.0.0", "v1.1.9"]:
		if updater._compare_versions("9.8.7.6", legacy) != 1:
			push_error("Direct legacy-to-current version jump failed for " + legacy)
			quit(21)
			return

	var source := FileAccess.get_file_as_string("res://update/update_manager.gd")
	if not source.contains('response["apply"] = apply_downloaded_update(manual)'):
		push_error("Verified updates are not automatically applied")
		quit(10)
		return
	if not source.contains('response["download"] = await download_update(manual)'):
		push_error("Background/manual visibility mode is not preserved through download")
		quit(11)
		return
	if not source.contains("func set_auto_apply"):
		push_error("Updater auto_apply state is not exposed")
		quit(12)
		return
	if not source.contains('const MANIFEST_URL := "https://github.com/Treninem/AI/releases/latest/download/update.json"'):
		push_error("Permanent legacy update manifest URL changed")
		quit(22)
		return
	if not source.contains('const MANIFEST_SIG_URL := "https://github.com/Treninem/AI/releases/latest/download/update.sig"'):
		push_error("Current signed manifest sidecar URL changed")
		quit(23)
		return

	var file := FileAccess.open("res://update/manifest.template.json", FileAccess.READ)
	if file == null:
		push_error("Update manifest template is missing")
		quit(13)
		return
	var manifest_text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(manifest_text)
	if not parsed is Dictionary:
		push_error("Update manifest template is invalid JSON")
		quit(14)
		return
	var assets = parsed.get("assets", {})
	if not assets is Dictionary or not assets.has("windows") or not assets.has("android"):
		push_error("Update manifest does not define both platform assets")
		quit(15)
		return
	for platform in ["windows", "android"]:
		var asset = assets.get(platform, {})
		if not asset is Dictionary or not asset.has("url") or not asset.has("sha256"):
			push_error("Legacy manifest asset contract missing for " + platform)
			quit(24)
			return
	var compatibility = parsed.get("compatibility", {})
	if not compatibility is Dictionary or not bool(compatibility.get("legacy_manifest", false)) or not bool(compatibility.get("direct_update", false)):
		push_error("Manifest no longer declares direct legacy updater compatibility")
		quit(25)
		return
	if str(compatibility.get("windows_strategy", "")) != "full_zip_replace":
		push_error("Windows legacy update strategy changed")
		quit(26)
		return
	if str(compatibility.get("android_strategy", "")) != "same_package_signed_apk":
		push_error("Android legacy update strategy changed")
		quit(27)
		return

	# Exercise the same RSA-SHA256 primitives used by the production updater.
	var crypto := Crypto.new()
	var private_key := crypto.generate_rsa(3072)
	if private_key == null:
		push_error("Godot failed to generate RSA key")
		quit(16)
		return
	var public_path := "user://aurora_update_smoke.pub"
	if private_key.save(public_path, true) != OK:
		push_error("Godot failed to save public RSA key")
		quit(17)
		return
	var public_key := CryptoKey.new()
	if public_key.load(public_path, true) != OK or not public_key.is_public_only():
		push_error("Godot failed to reload public RSA key")
		quit(18)
		return
	var payload := manifest_text.to_utf8_buffer()
	var digest := _sha256(payload)
	var signature := crypto.sign(HashingContext.HASH_SHA256, digest, private_key)
	if signature.is_empty() or not crypto.verify(HashingContext.HASH_SHA256, digest, signature, public_key):
		push_error("RSA manifest signature verification failed")
		quit(19)
		return
	var tampered := payload.duplicate()
	if not tampered.is_empty(): tampered[0] = tampered[0] ^ 1
	if crypto.verify(HashingContext.HASH_SHA256, _sha256(tampered), signature, public_key):
		push_error("RSA signature incorrectly accepted tampered manifest")
		quit(20)
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(public_path))

	updater.free()
	print("AURORA_UPDATE_GODOT_SMOKE_OK automatic=true legacy_direct_update=true signed_current=true")
	quit(0)

func _sha256(data: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK: return PackedByteArray()
	if ctx.update(data) != OK: return PackedByteArray()
	return ctx.finish()
