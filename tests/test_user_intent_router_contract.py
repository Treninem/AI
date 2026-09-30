from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_attachment_learning_requires_instruction_not_filename_or_payload() -> None:
    manager = _text("scripts/attachment_manager.gd")
    body = manager.split("func _learning_type(item", 1)[1].split("func _learning_type_from_instruction", 1)[0]
    assert "intent_router.learning_type(question)" in body
    assert "_learning_type_from_filename" not in body
    assert "_learning_type_from_payload" not in body
    filename = manager.split("func _learning_type_from_filename", 1)[1].split("func _learning_type_from_payload", 1)[0]
    payload = manager.split("func _learning_type_from_payload", 1)[1].split("func _normalize_learning_type", 1)[0]
    assert 'return ""' in filename
    assert 'return ""' in payload


def test_router_remembers_read_sources_but_separates_questions_and_negation() -> None:
    router = _text("scripts/user_intent_router.gd")
    assert "explicit_negation" in router
    assert "question_not_authorization" in router
    assert "no_durable_learning_authorization" in router
    assert '"learning_type": learning_type_value' in router
    assert '"durable_write_authorized": not learning_type_value.is_empty()' in router
    assert '"изуч"' in router
    assert '"усво"' in router
    assert '"для дообучения"' in router
    assert '"save as skill"' in router
    assert "owner_read_means_remember" in router
    assert '"прочит"' in router
    assert '"посчит"' in router
