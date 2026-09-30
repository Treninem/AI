from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_feedback_is_private_exact_and_owner_gated() -> None:
    store = _text("scripts/chat_store.gd")
    main = _text("scripts/main.gd")
    agent = _text("scripts/agent_core.gd")
    experience = _text("scripts/experience_store.gd")
    assert '"id": message_id' in store
    assert '"metadata": metadata.duplicate(true)' in store
    assert "func set_message_feedback" in store
    assert "func feedback_context" in store
    assert '"awaiting_confirmation"' in main
    assert "feedback_dialog.confirmed.connect(_confirm_feedback_learning)" in main
    assert "feedback_dialog.canceled.connect(_decline_feedback_learning)" in main
    assert '"promotion": "owner_confirmation_required"' in agent
    assert "func retract_feedback" in experience
    assert '"source_feedback_id": source_feedback_id' in experience
    assert "if not bool(item.get(\"active\", true))" in experience
    assert "agent.experience.retract_feedback(message_id)" in main
    assert 'pending_feedback_analysis.get("safe_to_save", false)' in main
    review = agent.split("func analyze_user_feedback", 1)[1].split("# execution_guard", 1)[0]
    assert "memory.learn" not in review
    assert "experience.record_failure" not in review
    assert "experience.save_skill" not in review


def test_feedback_controls_are_compact_accessible_and_assistant_only() -> None:
    main = _text("scripts/main.gd")
    controls = main.split("func _add_feedback_controls", 1)[1].split("func _on_message_feedback", 1)[0]
    assert '"FeedbackPositive"' in controls
    assert '"FeedbackNegative"' in controls
    assert '"text": "+"' in controls
    assert '"text": "−"' in controls
    assert "accessibility_name" in controls
    card = main.split("func _add_message_card", 1)[1].split("func _add_feedback_controls", 1)[0]
    assert "if not is_user:" in card
    assert "_add_feedback_controls(body, message)" in card


def test_scripted_greeting_is_never_reported_as_core_reasoning() -> None:
    main = _text("scripts/main.gd")
    assert 'response_origin := "deterministic_ui_greeting"' in main
    assert "AuroraFox Core не использовался" in main
    assert 'response_origin = "core_startup_status"' in main
