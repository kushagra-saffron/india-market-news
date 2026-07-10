from __future__ import annotations

import logging
import os
from datetime import datetime, timezone
from typing import Any

from supabase import Client, create_client

from india_market_news.models import CorporateActionItem, NewsItem, TickerSnapshot

logger = logging.getLogger(__name__)

RETENTION_DAYS = 90


class SupabaseStore:
    def __init__(self, client: Client):
        self.client = client

    @classmethod
    def from_env(cls) -> SupabaseStore:
        url = os.environ["SUPABASE_URL"]
        key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
        return cls(create_client(url, key))

    def start_fetch_run(self, run_type: str) -> str:
        row = (
            self.client.schema("market_news")
            .table("fetch_runs")
            .insert(
                {
                    "run_type": run_type,
                    "status": "running",
                }
            )
            .execute()
        )
        return row.data[0]["id"]

    def finish_fetch_run(
        self,
        run_id: str,
        *,
        status: str,
        stats: dict[str, Any],
        error_message: str | None = None,
    ) -> None:
        payload = {
            "status": status,
            "completed_at": datetime.now(timezone.utc).isoformat(),
            "error_message": error_message,
            **stats,
        }
        self.client.schema("market_news").table("fetch_runs").update(payload).eq(
            "id", run_id
        ).execute()

    def upsert_news(self, items: list[NewsItem]) -> tuple[int, int]:
        if not items:
            return 0, 0

        rows = [
            {
                "content_hash": item.content_hash,
                "ticker": item.ticker,
                "company_name": item.company_name,
                "title": item.title,
                "summary": item.summary,
                "published_at": item.published_at.isoformat() if item.published_at else None,
                "source": "zerodha",
            }
            for item in items
        ]

        before = self._count_news_hashes([row["content_hash"] for row in rows])
        self.client.schema("market_news").table("news_items").upsert(
            rows,
            on_conflict="content_hash",
            ignore_duplicates=True,
        ).execute()
        inserted = max(len(rows) - before, 0)
        skipped = len(rows) - inserted
        return inserted, skipped

    def upsert_corporate_actions(
        self, items: list[CorporateActionItem]
    ) -> tuple[int, int]:
        if not items:
            return 0, 0

        rows = [
            {
                "content_hash": item.content_hash,
                "ticker": item.ticker,
                "event_type": item.event_type,
                "event_date_raw": item.event_date,
                "details": item.details,
            }
            for item in items
        ]

        before = self._count_corp_hashes([row["content_hash"] for row in rows])
        self.client.schema("market_news").table("corporate_actions").upsert(
            rows,
            on_conflict="content_hash",
            ignore_duplicates=True,
        ).execute()
        inserted = max(len(rows) - before, 0)
        skipped = len(rows) - inserted
        return inserted, skipped

    def apply_retention(self, days: int = RETENTION_DAYS) -> int:
        result = (
            self.client.schema("market_news")
            .rpc("purge_old_news", {"retention_days": days})
            .execute()
        )
        return int(result.data or 0)

    def sync_tickers(self, tickers: list[dict[str, str]]) -> None:
        if not tickers:
            return
        rows = [
            {
                "symbol": row["symbol"],
                "nse_symbol": row["nse_symbol"],
                "company_name": row.get("company_name") or "",
                "series": row.get("series") or "",
                "isin": row.get("isin") or "",
            }
            for row in tickers
        ]
        self.client.schema("market_news").table("tickers").upsert(
            rows,
            on_conflict="symbol",
        ).execute()

    def _count_news_hashes(self, hashes: list[str]) -> int:
        if not hashes:
            return 0
        result = (
            self.client.schema("market_news")
            .table("news_items")
            .select("content_hash")
            .in_("content_hash", hashes)
            .execute()
        )
        return len(result.data or [])

    def _count_corp_hashes(self, hashes: list[str]) -> int:
        if not hashes:
            return 0
        result = (
            self.client.schema("market_news")
            .table("corporate_actions")
            .select("content_hash")
            .in_("content_hash", hashes)
            .execute()
        )
        return len(result.data or [])


def snapshots_to_items(
    snapshots: list[TickerSnapshot],
) -> tuple[list[NewsItem], list[CorporateActionItem]]:
    news: list[NewsItem] = []
    corp: list[CorporateActionItem] = []
    for snapshot in snapshots:
        if snapshot.error:
            continue
        news.extend(snapshot.news)
        corp.extend(snapshot.corporate_actions)
    return news, corp
