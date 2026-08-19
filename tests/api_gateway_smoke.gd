extends SceneTree

func _init() -> void:
	for path in [
		"res://api/agent_bridge.gd",
		"res://api/gateway_manager.gd",
		"res://api/settings_overlay.gd"
	]:
		var script = load(path)
		if script == null or not script.can_instantiate():
			push_error("API script cannot be instantiated: " + path)
			quit(2)
			return

	var bridge_script = load("res://api/agent_bridge.gd")
	var bridge = bridge_script.new()
	if int(bridge.port) != 8770:
		push_error("AgentCore bridge port contract changed unexpectedly")
		bridge.free()
		quit(3)
		return
	bridge.free()

	var manager_script = load("res://api/gateway_manager.gd")
	var manager = manager_script.new()
	if manager.base_url() != "http://127.0.0.1:8768":
		push_error("API local endpoint contract changed unexpectedly: " + manager.base_url())
		manager.free()
		quit(4)
		return
	manager.free()

	var scene_text := FileAccess.get_file_as_string("res://main.tscn")
	for node_name in ["ApiAgentBridge", "ApiGatewayManager", "ApiSettings"]:
		if not scene_text.contains(node_name):
			push_error("main.tscn is missing " + node_name)
			quit(5)
			return

	for file_path in [
		"res://api/server.py",
		"res://api/install_api.ps1",
		"res://api/start_api.ps1",
		"res://api/requirements.txt"
	]:
		if not FileAccess.file_exists(file_path):
			push_error("API runtime file missing: " + file_path)
			quit(6)
			return

	print("AURORA_API_GATEWAY_SMOKE_OK")
	quit(0)
