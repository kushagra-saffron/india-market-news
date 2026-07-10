-- Move market news tables to public schema for reliable PostgREST access on hosted Supabase.

CREATE TABLE IF NOT EXISTS public.mn_tickers (
    symbol TEXT PRIMARY KEY,
    nse_symbol TEXT NOT NULL,
    company_name TEXT NOT NULL DEFAULT '',
    series TEXT NOT NULL DEFAULT '',
    isin TEXT NOT NULL DEFAULT '',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_mn_tickers_nse_symbol ON public.mn_tickers (nse_symbol);

CREATE TABLE IF NOT EXISTS public.mn_fetch_runs (
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

CREATE TABLE IF NOT EXISTS public.mn_news_items (
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

CREATE INDEX IF NOT EXISTS idx_mn_news_ticker_published ON public.mn_news_items (ticker, published_at DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_mn_news_first_seen ON public.mn_news_items (first_seen_at DESC);

CREATE TABLE IF NOT EXISTS public.mn_corporate_actions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_hash TEXT NOT NULL UNIQUE,
    ticker TEXT NOT NULL,
    event_type TEXT NOT NULL,
    event_date_raw TEXT NOT NULL,
    details TEXT NOT NULL DEFAULT '',
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_mn_corp_ticker ON public.mn_corporate_actions (ticker, event_date_raw DESC);

CREATE OR REPLACE FUNCTION public.mn_purge_old_news(retention_days INTEGER DEFAULT 90)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM public.mn_news_items
    WHERE COALESCE(published_at, first_seen_at) < now() - make_interval(days => retention_days);
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

CREATE OR REPLACE VIEW public.mn_latest_news AS
SELECT id, ticker, company_name, title, summary, published_at, source, first_seen_at
FROM public.mn_news_items
WHERE COALESCE(published_at, first_seen_at) >= now() - interval '90 days'
ORDER BY COALESCE(published_at, first_seen_at) DESC NULLS LAST;

CREATE OR REPLACE VIEW public.mn_ticker_corporate_actions AS
SELECT id, ticker, event_type, event_date_raw AS event_date, details, first_seen_at, last_seen_at
FROM public.mn_corporate_actions
ORDER BY ticker, event_date_raw DESC;

ALTER TABLE public.mn_news_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mn_corporate_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mn_tickers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mn_fetch_runs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read mn news" ON public.mn_news_items;
CREATE POLICY "Public read mn news" ON public.mn_news_items FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read mn corp" ON public.mn_corporate_actions;
CREATE POLICY "Public read mn corp" ON public.mn_corporate_actions FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read mn tickers" ON public.mn_tickers;
CREATE POLICY "Public read mn tickers" ON public.mn_tickers FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read mn fetch runs" ON public.mn_fetch_runs;
CREATE POLICY "Public read mn fetch runs" ON public.mn_fetch_runs FOR SELECT USING (true);

GRANT SELECT ON public.mn_news_items, public.mn_corporate_actions, public.mn_tickers, public.mn_fetch_runs, public.mn_latest_news, public.mn_ticker_corporate_actions TO anon, authenticated;
GRANT ALL ON public.mn_news_items, public.mn_corporate_actions, public.mn_tickers, public.mn_fetch_runs TO service_role;
GRANT EXECUTE ON FUNCTION public.mn_purge_old_news(INTEGER) TO service_role;

NOTIFY pgrst, 'reload schema';
