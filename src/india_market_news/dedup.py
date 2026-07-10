from __future__ import annotations

import hashlib
import re


def _normalize_text(value: str) -> str:
    return re.sub(r"\s+", " ", value.strip().lower())


def news_content_hash(ticker: str, title: str, published_at: str | None) -> str:
    """Stable hash for deduplicating news across fetch runs."""
    parts = [
        ticker.upper(),
        _normalize_text(title),
        published_at or "",
    ]
    raw = "|".join(parts)
    return hashlib.sha256(raw.encode()).hexdigest()


def corporate_action_hash(ticker: str, event_type: str, event_date: str) -> str:
    raw = "|".join([
        ticker.upper(),
        _normalize_text(event_type),
        event_date.strip(),
    ])
    return hashlib.sha256(raw.encode()).hexdigest()
