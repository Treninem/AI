"""AuroraFox external API gateway package."""

from __future__ import annotations

import os
from typing import Any

knowledge_bootstrap: dict[str, Any] = {"ok": True, "skipped": True}

# The REG.RU API service imports this package on every restart. That makes the
# package initializer a lightweight deployment hook: it validates the compact
# canonical seed immediately and starts deterministic knowledge materialization
# in a detached process. The materializer process itself is guarded to avoid a
# recursive spawn when it imports the ``api`` package through ``python -m``.
if (
    os.getenv("AURORAFOX_DEPLOYMENT", "").strip().lower() == "reg-ru"
    and os.getenv("AURORAFOX_KNOWLEDGE_MATERIALIZER", "") != "1"
):
    try:
        from api.knowledge_bundle import bootstrap_server_knowledge

        knowledge_bootstrap = bootstrap_server_knowledge()
    except Exception as exc:  # API availability must not depend on cache build.
        knowledge_bootstrap = {"ok": False, "error": str(exc)}

__all__ = ["knowledge_bootstrap"]
