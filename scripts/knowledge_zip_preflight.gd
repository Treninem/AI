class_name KnowledgeZipPreflight
extends RefCounted

# ZIP field widths/comment length are format structure, not owner budgets.
# ZIPReader allocates the declared expanded member size; inspect it first.
func inspect(path: String, entry_cap: int) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _error("Cannot read ZIP directory")
	var result := _directory(file, entry_cap)
	file.close()
	return result

func _directory(file: FileAccess, entry_cap: int) -> Dictionary:
	var size := file.get_length()
	if size < 22: return _error("Truncated ZIP footer")
	var tail_start := maxi(0, size - 65535 - 22)
	file.seek(tail_start)
	var tail := file.get_buffer(size - tail_start)
	var footer := -1
	for offset in range(tail.size() - 22, -1, -1):
		if tail.decode_u32(offset) == 0x06054b50 and offset + 22 + tail.decode_u16(offset + 20) == tail.size():
			footer = offset
			break
	if footer < 0: return _error("Invalid ZIP footer")
	if tail.decode_u16(footer + 4) != 0 or tail.decode_u16(footer + 6) != 0:
		return _error("Multi-disk ZIP requires File Intelligence")
	var entries := int(tail.decode_u16(footer + 10))
	var central_size := int(tail.decode_u32(footer + 12))
	var central_start := int(tail.decode_u32(footer + 16))
	if entries == 65535 or central_size == 0xffffffff or central_start == 0xffffffff:
		return _error("ZIP64 requires File Intelligence")
	if int(tail.decode_u16(footer + 8)) != entries:
		return _error("Inconsistent ZIP entry count")
	if entry_cap > 0 and entries > entry_cap:
		return _error("ZIP directory exceeds owner entry budget")
	var central_end := central_start + central_size
	if central_end > tail_start + footer: return _error("ZIP directory exceeds archive bounds")
	file.seek(central_start)
	var sizes: Dictionary = {}
	for _index in range(entries):
		if file.get_position() + 46 > central_end: return _error("Truncated ZIP directory entry")
		var header := file.get_buffer(46)
		if header.size() != 46 or header.decode_u32(0) != 0x02014b50:
			return _error("Invalid ZIP directory entry")
		var expanded := int(header.decode_u32(24))
		var compressed := int(header.decode_u32(20))
		var local_offset := int(header.decode_u32(42))
		if expanded == 0xffffffff or compressed == 0xffffffff or local_offset == 0xffffffff:
			return _error("ZIP64 member requires File Intelligence")
		if header.decode_u16(34) != 0 or local_offset + 30 + compressed > central_start:
			return _error("Invalid ZIP member bounds")
		if (header.decode_u16(8) & 1) != 0:
			return _error("Encrypted ZIP requires owner-provided accessible content")
		var name_bytes := int(header.decode_u16(28))
		var remainder := int(header.decode_u16(30)) + int(header.decode_u16(32))
		if file.get_position() + name_bytes + remainder > central_end:
			return _error("ZIP member metadata exceeds directory bounds")
		var name := file.get_buffer(name_bytes).get_string_from_utf8()
		if sizes.has(name): return _error("Duplicate ZIP member identity")
		sizes[name] = expanded
		file.seek(file.get_position() + remainder)
	return {"ok": true, "sizes": sizes, "entries": entries}

func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message, "requires_extractor": true}
