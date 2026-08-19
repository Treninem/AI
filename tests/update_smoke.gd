extends SceneTree

func _init() -> void:
	var updater := AuroraUpdateManager.new()
	if updater == null:
		push_error("AuroraUpdateManager failed to instantiate")
		quit(2)
		return

	if updater._compare_versions("0.4.1", "0.4.0") != 1:
		push_error("Updater failed newer-version comparison")
		quit(3)
		return
	if updater._compare_versions("v0.4.0", "0.4.0") != 0:
		push_error("Updater failed equal-version comparison")
		quit(4)
		return
	if updater._compare_versions("0.3.99", "0.4.0") != -1:
		push_error("Updater failed older-version comparison")
		quit(5)
		return

	var file := FileAccess.open("res://update/manifest.template.json", FileAccess.READ)
	if file == null:
		push_error("Update manifest template is missing")
		quit(6)
		return
	var manifest_text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(manifest_text)
	if not parsed is Dictionary:
		push_error("Update manifest template is invalid JSON")
		quit(7)
		return
	var assets = parsed.get("assets", {})
	if not assets is Dictionary or not assets.has("windows") or not assets.has("android"):
		push_error("Update manifest does not define both platform assets")
		quit(8)
		return

	# Exercise the same RSA-SHA256 primitives used by the production updater.
	var crypto := Crypto.new()
	var private_key := crypto.generate_rsa(3072)
	if private_key == null:
		push_error("Godot failed to generate RSA key")
		quit(9)
		return
	var public_path := "user://aurora_update_smoke.pub"
	if private_key.save(public_path, true) != OK:
		push_error("Godot failed to save public RSA key")
		quit(10)
		return
	var public_key := CryptoKey.new()
	if public_key.load(public_path, true) != OK or not public_key.is_public_only():
		push_error("Godot failed to reload public RSA key")
		quit(11)
		return
	var payload := manifest_text.to_utf8_buffer()
	var digest := _sha256(payload)
	var signature := crypto.sign(HashingContext.HASH_SHA256, digest, private_key)
	if signature.is_empty() or not crypto.verify(HashingContext.HASH_SHA256, digest, signature, public_key):
		push_error("RSA manifest signature verification failed")
		quit(12)
		return
	var tampered := payload.duplicate()
	if not tampered.is_empty(): tampered[0] = tampered[0] ^ 1
	if crypto.verify(HashingContext.HASH_SHA256, _sha256(tampered), signature, public_key):
		push_error("RSA signature incorrectly accepted tampered manifest")
		quit(13)
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(public_path))

	updater.free()
	print("AURORA_UPDATE_GODOT_SMOKE_OK")
	quit(0)

func _sha256(data: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK: return PackedByteArray()
	if ctx.update(data) != OK: return PackedByteArray()
	return ctx.finish()
