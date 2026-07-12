from __future__ import annotations

import html as htmlmod
import logging
import re
from pathlib import Path

from india_market_news.models import TickerSnapshot
from india_market_news.zerodha import parse_zerodha_page

logger = logging.getLogger(__name__)


def save_snapshot_sections(snapshot: TickerSnapshot, raw_dir: Path) -> Path | None:
    """Persist only #news and #corporate_ations HTML for later parser reprocessing."""
    if snapshot.error and not snapshot.raw_news_html and not snapshot.raw_corp_html:
        return None

    raw_dir.mkdir(parents=True, exist_ok=True)
    path = raw_dir / f"{snapshot.ticker}.html"
    company = htmlmod.escape(snapshot.company_name or snapshot.ticker)
    news = snapshot.raw_news_html or ""
    corp = snapshot.raw_corp_html or ""
    path.write_text(
        (
            "<!DOCTYPE html>\n<html><head>"
            f"<title>{company} Share Price</title>"
            f'<meta name="ticker" content="{htmlmod.escape(snapshot.ticker)}">'
            f'<meta name="exchange" content="{htmlmod.escape(snapshot.exchange)}">'
            "</head><body>\n"
            f'<div id="news" class="subtab_content">{news}</div>\n'
            f'<div id="corporate_ations" class="subtab_content">{corp}</div>\n'
            "</body></html>\n"
        ),
        encoding="utf-8",
    )
    return path


def load_raw_snapshots(raw_dir: Path) -> list[TickerSnapshot]:
    """Re-parse saved section HTML without contacting Zerodha."""
    raw_dir = Path(raw_dir)
    if not raw_dir.exists():
        raise FileNotFoundError(f"Raw directory not found: {raw_dir}")

    snapshots: list[TickerSnapshot] = []
    files = sorted(raw_dir.glob("*.html"))
    logger.info("Reprocessing %d raw HTML files from %s", len(files), raw_dir)
    for path in files:
        html = path.read_text(encoding="utf-8")
        ticker_match = re.search(
            r'<meta name="ticker" content="([^"]+)"',
            html,
            flags=re.IGNORECASE,
        )
        exchange_match = re.search(
            r'<meta name="exchange" content="([^"]+)"',
            html,
            flags=re.IGNORECASE,
        )
        ticker = (
            ticker_match.group(1).strip().upper()
            if ticker_match
            else path.stem.strip().upper()
        )
        exchange = (
            exchange_match.group(1).strip().upper() if exchange_match else "NSE"
        )
        url = f"https://zerodha.com/markets/stocks/{exchange}/{ticker}/"
        snapshots.append(
            parse_zerodha_page(html, exchange=exchange, ticker=ticker, url=url)
        )
    return snapshots
