-- India market news schema (Zerodha → Supabase)
-- Project: india-market-news (imrcllmpldvjoyjyluhr, ap-northeast-1)
-- Retention: 90 days

CREATE SCHEMA IF NOT EXISTS market_news;

CREATE TABLE IF NOT EXISTS market_news.tickers (
    symbol TEXT PRIMARY KEY,
    nse_symbol TEXT NOT NULL,
    company_name TEXT NOT NULL DEFAULT '',
    series TEXT NOT NULL DEFAULT '',
    isin TEXT NOT NULL DEFAULT '',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_market_news_tickers_nse_symbol
    ON market_news.tickers (nse_symbol);

CREATE TABLE IF NOT EXISTS market_news.fetch_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_type TEXT NOT NULL DEFAULT 'scheduled',
    status TEXT NOT NULL DEFAULT 'running',
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ,
    tickers_total INTEGER NOT NULL DEFAULT 0,
    tickers_ok INTEGER NOT NULL DEFAULT 0,
    tickers_failed INTEGER NOT NULL DEFAULT 0,
    news_seen INTEGER NOT NULL DEFAULT 0,
    news_inserted INTEGER NOT NULL DEFAULT 0,
    news_skipped INTEGER NOT NULL DEFAULT 0,
    corp_seen INTEGER NOT NULL DEFAULT 0,
    corp_inserted INTEGER NOT NULL DEFAULT 0,
    corp_skipped INTEGER NOT NULL DEFAULT 0,
    retention_deleted INTEGER NOT NULL DEFAULT 0,
    duration_seconds NUMERIC,
    error_message TEXT
);

CREATE TABLE IF NOT EXISTS market_news.news_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_hash TEXT NOT NULL UNIQUE,
    ticker TEXT NOT NULL,
    company_name TEXT NOT NULL DEFAULT '',
    title TEXT NOT NULL,
    summary TEXT NOT NULL DEFAULT '',
    published_at TIMESTAMPTZ,
    source TEXT NOT NULL DEFAULT 'zerodha',
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_market_news_news_ticker_published
    ON market_news.news_items (ticker, published_at DESC NULLS LAST);

CREATE INDEX IF NOT EXISTS idx_market_news_news_first_seen
    ON market_news.news_items (first_seen_at DESC);

CREATE TABLE IF NOT EXISTS market_news.corporate_actions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_hash TEXT NOT NULL UNIQUE,
    ticker TEXT NOT NULL,
    event_type TEXT NOT NULL,
    event_date_raw TEXT NOT NULL,
    details TEXT NOT NULL DEFAULT '',
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_market_news_corp_ticker
    ON market_news.corporate_actions (ticker, event_date_raw DESC);

-- 90-day retention purge
CREATE OR REPLACE FUNCTION market_news.purge_old_news(retention_days INTEGER DEFAULT 90)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = market_news
AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM market_news.news_items
    WHERE COALESCE(published_at, first_seen_at) < now() - make_interval(days => retention_days);

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

-- UI-friendly views
CREATE OR REPLACE VIEW market_news.latest_news AS
SELECT
    id,
    ticker,
    company_name,
    title,
    summary,
    published_at,
    source,
    first_seen_at
FROM market_news.news_items
WHERE COALESCE(published_at, first_seen_at) >= now() - interval '90 days'
ORDER BY COALESCE(published_at, first_seen_at) DESC NULLS LAST;

CREATE OR REPLACE VIEW market_news.ticker_corporate_actions AS
SELECT
    id,
    ticker,
    event_type,
    event_date_raw AS event_date,
    details,
    first_seen_at,
    last_seen_at
FROM market_news.corporate_actions
ORDER BY ticker, event_date_raw DESC;

-- RLS: public read for UI, writes via service role only
ALTER TABLE market_news.news_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE market_news.corporate_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE market_news.tickers ENABLE ROW LEVEL SECURITY;
ALTER TABLE market_news.fetch_runs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public read news"
    ON market_news.news_items FOR SELECT
    USING (true);

CREATE POLICY "Public read corporate actions"
    ON market_news.corporate_actions FOR SELECT
    USING (true);

CREATE POLICY "Public read tickers"
    ON market_news.tickers FOR SELECT
    USING (true);

CREATE POLICY "Public read fetch runs"
    ON market_news.fetch_runs FOR SELECT
    USING (true);

-- Expose schema to PostgREST API
GRANT USAGE ON SCHEMA market_news TO anon, authenticated, service_role;
GRANT SELECT ON ALL TABLES IN SCHEMA market_news TO anon, authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA market_news TO service_role;
GRANT ALL ON ALL TABLES IN SCHEMA market_news TO service_role;
GRANT EXECUTE ON FUNCTION market_news.purge_old_news(INTEGER) TO service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA market_news
    GRANT SELECT ON TABLES TO anon, authenticated;

-- Expose schema to PostgREST (Supabase REST API)
ALTER ROLE authenticator SET pgrst.db_schemas = 'public, graphql_public, market_news';
NOTIFY pgrst, 'reload config';
