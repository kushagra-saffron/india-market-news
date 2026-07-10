from __future__ import annotations

import logging
import time
from pathlib import Path

from india_market_news.fetcher import NewsFetcher
from india_market_news.supabase_store import SupabaseStore, snapshots_to_items
from india_market_news.tickers import load_tickers_from_csv

logger = logging.getLogger(__name__)


def run_pipeline(
    *,
    ticker_csv: Path,
    store: SupabaseStore,
    run_type: str = "scheduled",
    include_corporate_actions: bool = True,
    max_workers: int = 20,
    batch_size: int = 200,
    series: str | None = "EQ",
) -> dict:
    ticker_rows = load_tickers_from_csv(ticker_csv, series=series)
    tickers = [row["nse_symbol"] for row in ticker_rows]

    run_id = store.start_fetch_run(run_type)
    started = time.perf_counter()

    stats = {
        "tickers_total": len(tickers),
        "tickers_ok": 0,
        "tickers_failed": 0,
        "news_seen": 0,
        "news_inserted": 0,
        "news_skipped": 0,
        "corp_seen": 0,
        "corp_inserted": 0,
        "corp_skipped": 0,
        "retention_deleted": 0,
    }

    try:
        store.sync_tickers(ticker_rows)
        fetcher = NewsFetcher(max_workers=max_workers)

        for offset in range(0, len(tickers), batch_size):
            batch = tickers[offset : offset + batch_size]
            snapshots = fetcher.fetch_tickers(batch)
            ok = sum(1 for snapshot in snapshots if not snapshot.error)
            stats["tickers_ok"] += ok
            stats["tickers_failed"] += len(snapshots) - ok

            news_items, corp_items = snapshots_to_items(snapshots)
            stats["news_seen"] += len(news_items)

            inserted, skipped = store.upsert_news(news_items)
            stats["news_inserted"] += inserted
            stats["news_skipped"] += skipped

            if include_corporate_actions:
                stats["corp_seen"] += len(corp_items)
                corp_inserted, corp_skipped = store.upsert_corporate_actions(corp_items)
                stats["corp_inserted"] += corp_inserted
                stats["corp_skipped"] += corp_skipped

            logger.info(
                "Batch %d-%d: ok=%d news_inserted=%d",
                offset,
                offset + len(batch),
                ok,
                inserted,
            )

        stats["retention_deleted"] = store.apply_retention()
        stats["duration_seconds"] = round(time.perf_counter() - started, 1)
        store.finish_fetch_run(run_id, status="completed", stats=stats)
        return stats

    except Exception as exc:
        stats["duration_seconds"] = round(time.perf_counter() - started, 1)
        store.finish_fetch_run(
            run_id,
            status="failed",
            stats=stats,
            error_message=str(exc),
        )
        raise
