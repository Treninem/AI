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
	for legacy in ["0.0.1", "0.1", "0.4.0", "1.0.0", "1.2.0.0", "1.3.0.0", "v1.1.9"]:
		if updater._compare_versions("1.4.0.0", legacy) != 1:
			push_error("Version comparison failed for repair source " + legacy)
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
		push_error("Permanent update manifest URL changed")
		quit(22)
		return
	if not source.contains('const MANIFEST_SIG_URL := "https://github.com/Treninem/AI/releases/latest/download/update.sig"'):
		push_error("Signed manifest sidecar URL changed")
		quit(23)
		return
	if not source.contains('"repair_required": true'):
		push_error("Updater does not expose repair-required state when trust root is missing")
		quit(28)
		return
	if not source.contains("untrusted_remote"):
		push_error("Updater no longer separates untrusted version discovery from trusted assets")
		quit(29)
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
			push_error("Stable manifest asset contract missing for " + platform)
			quit(24)
			return
	var compatibility = parsed.get("compatibility", {})
	if not compatibility is Dictionary:
		push_error("Update compatibility metadata is missing")
		quit(25)
		return
	if not bool(compatibility.get("legacy_manifest", false)) or not bool(compatibility.get("legacy_manifest_readable", false)):
		push_error("Legacy manifest readability contract changed")
		quit(26)
		return
	if bool(compatibility.get("legacy_direct_update", true)):
		push_error("Manifest incorrectly claims legacy direct update is safe")
		quit(27)
		return
	if str(compatibility.get("legacy_repair_required_through", "")) != "1.3.0.0":
		push_error("V1.3 repair boundary changed")
		quit(30)
		return
	if not bool(compatibility.get("signed_direct_update", false)) or str(compatibility.get("signed_update_floor", "")) != "1.4.0.0":
		push_error("V1.4 signed direct-update floor changed")
		quit(31)
		return
	if not str(compatibility.get("windows_strategy", "")).contains("repair"):
		push_error("Windows repair strategy missing")
		quit(32)
		return
	if str(compatibility.get("android_strategy", "")) != "same_package_same_permanent_signing_identity_required":
		push_error("Android signing continuity contract changed")
		quit(33)
		return
	if not FileAccess.file_exists("res://update/release_public.pub"):
		push_error("Permanent update trust root is missing from project resources")
		quit(34)
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
	print("AURORA_UPDATE_GODOT_SMOKE_OK automatic=true legacy_repair_through=1.3.0.0 signed_floor=1.4.0.0")
	quit(0)

func _sha256(data: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK: return PackedByteArray()
	if ctx.update(data) != OK: return PackedByteArray()
	return ctx.finish()
