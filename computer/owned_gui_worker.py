"""Spawn-importable bootstrap: parent must install ownership before GUI effects."""


def run_owned_worker(target, kind, payload, queue, launch_gate):
    # A dead/unavailable parent must never leave an unauthorized GUI worker.
    # This bounds the authority handshake, not the owner's operation budget.
    if not launch_gate.wait(timeout=5.0):
        queue.put({"ok": False, "error": "launch_authorization_timeout", "retryable": False})
        return
    target(kind, payload, queue)
