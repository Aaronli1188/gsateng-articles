-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Schedule: every day at 23:00 UTC = 7:00 AM Taiwan time (UTC+8)
-- Calls the refresh-sentences Edge Function via pg_net
SELECT cron.schedule(
  'refresh-sentences-daily',
  '0 23 * * *',
  $$
  SELECT net.http_post(
    url := current_setting('app.settings.supabase_url') || '/functions/v1/refresh-sentences',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key')
    ),
    body := '{}'::jsonb
  );
  $$
);
