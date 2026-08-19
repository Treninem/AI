class_name AuroraComponentRegistry
extends RefCounted

const REPORT_SCHEMA_VERSION := 1

const CORE_TOOLS := [
	"system_info",
	"git_status",
	"workspace_create",
	"workspace_test"
]

const WINDOWS_INTEGRATION_TOOLS := [
	"project_index_status",
	"index_project",
	"search_project",
	"search_symbols",
	"workspace_import_project",
	"project_compare_file",
	"project_apply_file"
]

const KNOWLEDGE_TOOLS := [
	"analyze_file",
	"search_file_cache"
]

func build_report(
	agent_core: Variant,
	self_improver: Variant,
	runtime_extensions: Variant,
	tool_registry: Variant,
	memory_store: Variant,
	ai_client: Variant,
	services: Dictionary = {}
) -> Dictionary:
	var platform := str(services.get("platform", OS.get_name()))
	var available_tools: Array[String] = []
	if tool_registry is ToolRegistry:
		for name in tool_registry.tools.keys():
			available_tools.append(str(name))
	available_tools.sort()

	var required_tools: Array[String] = []
	for name in CORE_TOOLS:
		required_tools.append(str(name))
	if platform == "Windows":
		for name in WINDOWS_INTEGRATION_TOOLS:
			required_tools.append(str(name))

	var missing_required: Array[String] = []
	for name in required_tools:
		if name not in available_tools:
			missing_required.append(name)

	var knowledge_missing: Array[String] = []
	for name in KNOWLEDGE_TOOLS:
		if name not in available_tools:
			knowledge_missing.append(name)

	var components := {
		"agent_core": agent_core is AgentCore,
		"self_improver": self_improver is SelfImprover,
		"runtime_extensions": runtime_extensions is RuntimeExtensionManager,
		"tool_registry": tool_registry is ToolRegistry,
		"memory": memory_store is MemoryStore,
		"ai_client": ai_client is AIClient,
		"voice": bool(services.get("voice", false)),
		"update": bool(services.get("update", false)),
		"file_intelligence": bool(services.get("file_intelligence", false)),
		"project_index": bool(services.get("project_index", false)) or platform != "Windows"
	}

	var missing_components: Array[String] = []
	for key in components.keys():
		if not bool(components[key]):
			missing_components.append(str(key))

	var compatible := missing_components.is_empty() and missing_required.is_empty()
	return {
		"schema_version": REPORT_SCHEMA_VERSION,
		"ok": compatible,
		"compatible": compatible,
		"platform": platform,
		"components": components,
		"missing_components": missing_components,
		"tools_count": available_tools.size(),
		"tools": available_tools,
		"missing_required_tools": missing_required,
		"missing_knowledge_tools": knowledge_missing,
		"hot_extension_contract": "RefCounted/aurora_ext_*",
		"update_contract": "AuroraUpdate",
		"godot_target": "4.7.1"
	}
