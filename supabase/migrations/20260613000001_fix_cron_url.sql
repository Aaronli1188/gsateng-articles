-- Fix cron job: use actual URL and anon key (both public)
-- The Edge Function itself uses SB_SERVICE_ROLE_KEY secret for DB operations
SELECT cron.unschedule('refresh-sentences-daily');

SELECT cron.schedule(
  'refresh-sentences-daily',
  '0 23 * * *',
  $$
  SELECT net.http_post(
    url := 'https://tfixkvvlcalsmjhphowv.supabase.co/functions/v1/refresh-sentences',
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRmaXhrdnZsY2Fsc21qaHBob3d2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAwNDg3NTIsImV4cCI6MjA5NTYyNDc1Mn0.koKlWoXShhHR7G4ZxA0smCeXmwB6ULHGDEPVwKWnqM0"}'::jsonb,
    body := '{}'::jsonb
  );
  $$
);
