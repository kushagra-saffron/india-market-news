-- Reliable corporate-action upsert that always refreshes enrichment fields.

CREATE OR REPLACE FUNCTION public.mn_upsert_corporate_actions(rows JSONB)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    updated_count INTEGER := 0;
BEGIN
    IF rows IS NULL OR jsonb_typeof(rows) <> 'array' OR jsonb_array_length(rows) = 0 THEN
        RETURN 0;
    END IF;

    WITH payload AS (
        SELECT
            COALESCE(item->>'content_hash', '') AS content_hash,
            COALESCE(item->>'ticker', '') AS ticker,
            COALESCE(item->>'event_type', '') AS event_type,
            COALESCE(item->>'event_date_raw', '') AS event_date_raw,
            COALESCE(item->>'details', '') AS details,
            COALESCE(item->>'date_label', '') AS date_label,
            COALESCE(item->>'document_url', '') AS document_url,
            COALESCE(
                (item->>'last_seen_at')::timestamptz,
                now()
            ) AS last_seen_at
        FROM jsonb_array_elements(rows) AS item
        WHERE COALESCE(item->>'content_hash', '') <> ''
    )
    INSERT INTO public.mn_corporate_actions AS ca (
        content_hash,
        ticker,
        event_type,
        event_date_raw,
        details,
        date_label,
        document_url,
        last_seen_at
    )
    SELECT
        content_hash,
        ticker,
        event_type,
        event_date_raw,
        details,
        date_label,
        document_url,
        last_seen_at
    FROM payload
    ON CONFLICT (content_hash) DO UPDATE
    SET
        ticker = EXCLUDED.ticker,
        event_type = EXCLUDED.event_type,
        event_date_raw = EXCLUDED.event_date_raw,
        details = EXCLUDED.details,
        date_label = EXCLUDED.date_label,
        document_url = EXCLUDED.document_url,
        last_seen_at = EXCLUDED.last_seen_at;

    GET DIAGNOSTICS updated_count = ROW_COUNT;
    RETURN updated_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.mn_upsert_corporate_actions(JSONB) TO service_role;

NOTIFY pgrst, 'reload schema';
