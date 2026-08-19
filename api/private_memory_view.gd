class_name ApiPrivateMemoryView
extends MemoryStore

var shared_store: MemoryStore

func _init(store: MemoryStore = null) -> void:
	shared_store = store

func bind(store: MemoryStore) -> void:
	shared_store = store

func _ready() -> void:
	# API-private views must never load or persist the desktop owner's memory.
	memory = []
	knowledge = []
	vectors = {}
	set_process(false)

func remember(_kind: String, _content: String, _source: String = "", _importance: float = 0.55, _confidence: float = 0.85) -> void:
	# Deliberately ephemeral. Conversation history lives in ConversationStore,
	# scoped by API key id + conversation id.
	pass

func learn(_content: String, _source: String = "", _importance: float = 0.65, _confidence: float = 0.80, _kind: String = "knowledge") -> void:
	# Learning from private chat is opt-in through /v1/learn or feedback metadata.
	pass

func recent(_limit: int = 12) -> Array:
	return []

func retrieve(query: String, limit: int = 8, _include_memory: bool = true, _include_knowledge: bool = true) -> Array:
	if shared_store == null:
		return []
	# Shared factual/learned knowledge is allowed; private episodic memory is not.
	return await shared_store.retrieve(query, limit, false, true)

func search_memory(_query: String, _limit: int = 8) -> Array:
	return []

func search_knowledge(query: String, limit: int = 8) -> Array:
	if shared_store == null:
		return []
	return shared_store.search_knowledge(query, limit)

func semantic_status() -> Dictionary:
	if shared_store == null:
		return {"ready": false, "private_view": true}
	var status := shared_store.semantic_status().duplicate(true)
	status["private_view"] = true
	status["episodic_memory_visible"] = false
	return status

func reindex_semantic() -> Dictionary:
	# A private request cannot mutate the shared semantic index.
	return semantic_status()
