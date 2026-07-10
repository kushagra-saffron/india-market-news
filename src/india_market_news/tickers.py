from __future__ import annotations

import csv
import re
from pathlib import Path

# Zerodha URL slug uses underscores instead of hyphens.
_SYMBOL_OVERRIDES: dict[str, str] = {
    "BAJAJ-AUTO": "BAJAJ_AUTO",
    "TATAMOTORS": "TMPV",  # demerged; TMPV has more news coverage
}


def normalize_symbol(symbol: str) -> str:
    symbol = symbol.strip().upper()
    if symbol in _SYMBOL_OVERRIDES:
        return _SYMBOL_OVERRIDES[symbol]
    return symbol.replace("-", "_")


def load_tickers_from_csv(
    path: Path | str,
    *,
    series: str | None = "EQ",
) -> list[dict[str, str]]:
    """Load tickers from NSE EQUITY_L.csv format."""
    path = Path(path)
    rows: list[dict[str, str]] = []
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            symbol = (row.get("SYMBOL") or "").strip()
            if not symbol:
                continue
            row_series = (row.get(" SERIES") or row.get("SERIES") or "").strip()
            if series and row_series != series:
                continue
            rows.append(
                {
                    "symbol": symbol,
                    "nse_symbol": normalize_symbol(symbol),
                    "company_name": (row.get("NAME OF COMPANY") or "").strip(),
                    "series": row_series,
                    "isin": (row.get("ISIN NUMBER") or "").strip(),
                }
            )
    return rows


def load_ticker_symbols(
    path: Path | str,
    *,
    series: str | None = "EQ",
) -> list[str]:
    return [row["nse_symbol"] for row in load_tickers_from_csv(path, series=series)]
