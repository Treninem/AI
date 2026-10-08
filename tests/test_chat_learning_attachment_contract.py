from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ATTACHMENTS = (ROOT / "scripts" / "attachment_manager.gd").read_text(encoding="utf-8")
MAIN = (ROOT / "scripts" / "main.gd").read_text(encoding="utf-8")
EXPERIENCE = (ROOT / "scripts" / "experience_store.gd").read_text(encoding="utf-8")
SMOKE = (ROOT / "tests" / "chat_learning_attachment_smoke.gd").read_text(encoding="utf-8")


def test_chat_attachment_path_is_real_product_path():
    assert "attachments.describe(path)" in MAIN
    assert "attachments.analyze(path, shown, false)" in MAIN
    assert "attachments.build_context(attachment_copy)" in MAIN
    assert "files_dropped.connect(_on_files_dropped)" in MAIN


def test_jsonl_and_ndjson_are_first_class_chat_attachments():
    assert '"jsonl"' in ATTACHMENTS
    assert '"ndjson"' in ATTACHMENTS


def test_learning_attachment_types_are_distinct_and_explicit():
    assert '_learning_type_from_filename' in ATTACHMENTS
    assert 'aurorafox_type' in ATTACHMENTS
    assert 'aurorafox_import' in ATTACHMENTS
    assert 'return "knowledge"' in ATTACHMENTS
    assert 'return "training"' in ATTACHMENTS
    assert 'return "skill"' in ATTACHMENTS


def test_knowledge_and_training_use_existing_transactional_store():
    assert "KnowledgeStore.new()" in ATTACHMENTS
    assert "KnowledgeImportTransaction.new()" in ATTACHMENTS
    assert "transaction.import_file(store, path, metadata)" in ATTACHMENTS
    assert '"imported_via": "chat_attachment"' in ATTACHMENTS
    assert '"untrusted_document": true' in ATTACHMENTS
    assert '"auto_execute": false' in ATTACHMENTS


def test_skills_use_existing_experience_store_and_do_not_activate_code():
    assert 'SKILLS_PATH := "user://aurorafox_skills.json"' in EXPERIENCE
    assert "experience.save_skill(skill)" in ATTACHMENTS
    assert '"auto_execute": false' in ATTACHMENTS
    assert "RuntimeExtensionManager" not in ATTACHMENTS
    assert "activate_staged" not in ATTACHMENTS


def test_imported_skill_is_bounded_and_untrusted():
    assert 'OwnerResourcePolicy.value("skill_import_items")' in ATTACHMENTS
    assert 'OwnerResourcePolicy.value("skill_step_items")' in ATTACHMENTS
    assert 'OwnerResourcePolicy.value("skill_tool_items")' in ATTACHMENTS
    assert "0.70" in ATTACHMENTS
    assert "source_code" not in ATTACHMENTS.split("func _sanitize_imported_skill", 1)[1].split("func _owner_experience_store", 1)[0]


def test_chat_reports_import_result_back_to_assistant_context():
    assert "Импорт в локальное обучение AuroraFox" in ATTACHMENTS
    assert "learning_import" in ATTACHMENTS


def test_archive_learning_requires_real_extracted_text():
    assert 'metadata.get("text_entries_extracted", 0)' in ATTACHMENTS
    assert "В архиве не найдено безопасно извлекаемых текстовых знаний" in ATTACHMENTS
    assert "_import_extracted_knowledge(path, extracted_text, deferred_type)" in ATTACHMENTS


def test_neutral_attachment_waits_for_explicit_learning_instruction():
    assert "uploaded_files_2_" in SMOKE
    assert 'analyze(knowledge_path, "Изучи этот файл' in SMOKE
    assert "imported knowledge before the user instruction" in SMOKE
