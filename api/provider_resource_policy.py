from __future__ import annotations

import math


def nonnegative_seconds(value, name: str) -> float:
    try:
        seconds = float(value)
    except (TypeError, ValueError, OverflowError):
        raise ValueError(f"{name} must be finite and nonnegative") from None
    if isinstance(value, bool) or not math.isfinite(seconds) or seconds < 0:
        raise ValueError(f"{name} must be finite and nonnegative")
    return seconds


def socket_timeout(seconds: float) -> float | None:
    return seconds if seconds > 0 else None
