from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_api_health_poll_does_not_parse_empty_offline_response():
    source = read("api/gateway_manager.gd")
    poll = source.split("func _poll() -> void:", 1)[1].split("func _set_online", 1)[0]
    empty_guard = "if code == 200 and not text.is_empty():"
    assert empty_guard in poll
    assert poll.index(empty_guard) < poll.index("JSON.parse_string(text)")


def test_computer_client_handles_http_and_empty_body_before_json_parse():
    source = read("scripts/computer_client.gd")
    request = source.split("func _json_request", 1)[1].split("func health", 1)[0]
    http_guard = "if code < 200 or code >= 300:"
    empty_guard = "if text.is_empty():"
    parser = "JSON.parse_string(text)"
    assert request.index(http_guard) < request.index(parser)
    assert request.index(empty_guard) < request.index(parser)

