from __future__ import annotations

import logging
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

import httpx

from india_market_news.models import TickerSnapshot
from india_market_news.zerodha import USER_AGENT, fetch_ticker

logger = logging.getLogger(__name__)


class NewsFetcher:
    def __init__(self, *, max_workers: int = 20, retry_count: int = 2):
        self.max_workers = max_workers
        self.retry_count = retry_count

    def fetch_tickers(
        self,
        tickers: list[str],
        *,
        exchange: str = "NSE",
    ) -> list[TickerSnapshot]:
        tickers = [ticker.strip().upper() for ticker in tickers if ticker.strip()]
        if not tickers:
            return []

        snapshots: list[TickerSnapshot] = []
        with ThreadPoolExecutor(max_workers=self.max_workers) as pool:
            futures = {
                pool.submit(self._fetch_with_retry, ticker, exchange): ticker
                for ticker in tickers
            }
            for future in as_completed(futures):
                ticker = futures[future]
                try:
                    snapshots.append(future.result())
                except Exception as exc:
                    logger.error("Fetch crashed for %s: %s", ticker, exc)
                    snapshots.append(
                        TickerSnapshot(
                            ticker=ticker,
                            exchange=exchange,
                            company_name=ticker,
                            url=f"https://zerodha.com/markets/stocks/{exchange}/{ticker}/",
                            tcm_id=None,
                            error=str(exc),
                        )
                    )

        order = {ticker: index for index, ticker in enumerate(tickers)}
        snapshots.sort(key=lambda item: order.get(item.ticker, len(order)))
        return snapshots

    def _fetch_with_retry(self, ticker: str, exchange: str) -> TickerSnapshot:
        last: TickerSnapshot | None = None
        for attempt in range(self.retry_count + 1):
            with httpx.Client(
                headers={"User-Agent": USER_AGENT},
                timeout=25.0,
                follow_redirects=True,
            ) as client:
                snapshot = fetch_ticker(ticker, exchange=exchange, client=client)

            if not snapshot.error or "429" not in snapshot.error:
                return snapshot

            last = snapshot
            sleep_for = min(2 ** attempt, 8)
            logger.warning(
                "Rate limited on %s (attempt %d), sleeping %ds",
                ticker,
                attempt + 1,
                sleep_for,
            )
            time.sleep(sleep_for)

        return last or TickerSnapshot(
            ticker=ticker,
            exchange=exchange,
            company_name=ticker,
            url=f"https://zerodha.com/markets/stocks/{exchange}/{ticker}/",
            tcm_id=None,
            error="Unknown fetch failure",
        )
