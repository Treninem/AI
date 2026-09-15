"""AuroraFox external API gateway package."""

from __future__ import annotations

import os
from typing import Any

knowledge_bootstrap: dict[str, Any] = {"ok": True, "skipped": True}

# The production API service runs as the dedicated ``aurorafox`` user. The
# deployment updater and its pytest gate run as root with the same environment,
# so explicitly skip bootstrap for root: otherwise CI/update tests could start
# a background database build with root-owned files in /var/lib/aurorafox.
_is_root = bool(hasattr(os, "geteuid") and os.geteuid() == 0)
if (
    os.getenv("AURORAFOX_DEPLOYMENT", "").strip().lower() == "reg-ru"
    and os.getenv("AURORAFOX_KNOWLEDGE_MATERIALIZER", "") != "1"
    and not _is_root
):
    try:
        from api.knowledge_bundle import bootstrap_server_knowledge

        knowledge_bootstrap = bootstrap_server_knowledge()
    except Exception as exc:  # API availability must not depend on cache build.
        knowledge_bootstrap = {"ok": False, "error": str(exc)}

__all__ = ["knowledge_bootstrap"]
