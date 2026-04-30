-- photo_urls の要素を文字列から {url, caption} オブジェクト形式へ変換
UPDATE public.meeting_reports
SET photo_urls = (
    SELECT jsonb_agg(
        CASE
            WHEN jsonb_typeof(elem) = 'string'
            THEN jsonb_build_object('url', elem #>> '{}', 'caption', '')
            ELSE elem
        END
    )
    FROM jsonb_array_elements(photo_urls) elem
)
WHERE photo_urls IS NOT NULL
  AND jsonb_typeof(photo_urls) = 'array'
  AND photo_urls != '[]'::jsonb;
