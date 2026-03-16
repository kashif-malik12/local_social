# Server Ops

## Automated Backups

The VPS backup script is [backup_supabase_vps.sh](/C:/Users/ALI/Documents/VS%20Projects/local_social/scripts/backup_supabase_vps.sh).

It creates timestamped backups under `~/backups/supabase/` on the VPS and includes:

- PostgreSQL dump from `supabase-db`
- storage volume archive
- Supabase `.env`, `docker-compose.yml`, and edge functions archive

Default retention is `5` days and can be overridden with `RETENTION_DAYS`.

Recommended cron:

```cron
15 */6 * * * /home/deploy/bin/backup_supabase_vps.sh >> /home/deploy/backups/supabase/backup.log 2>&1
```

## Important Limitation

These backups are stored on the same VPS. That protects against app mistakes and partial corruption, but not VPS loss.

Before launch, add an offsite copy target such as:

- Backblaze B2
- S3 / Cloudflare R2
- another VPS or NAS

## Monitoring

The lightweight VPS monitoring script is [monitor_vps_health.sh](/C:/Users/ALI/Documents/VS%20Projects/local_social/scripts/monitor_vps_health.sh).

It logs:

- Docker container status
- public app and Supabase endpoint HTTP status
- disk usage
- memory usage
- uptime and load

Recommended cron:

```cron
*/10 * * * * /home/deploy/bin/monitor_vps_health.sh
```

Output log:

```text
/home/deploy/monitoring/health.log
```

This is operational visibility, not alerting. Before launch, add:

- external uptime monitoring
- alerting for repeated failures
- offsite log shipping if needed

## Daily Summary Email

The daily summary mailer is [daily_server_summary.py](/C:/Users/ALI/Documents/VS%20Projects/local_social/scripts/daily_server_summary.py).

It sends one email per day using the SMTP settings already stored in `~/supabase-project/.env` and includes:

- current disk and memory status
- current Docker container status
- latest backup snapshot presence
- recent health log tail

Recommended cron:

```cron
0 8 * * * ALERT_EMAIL_TO=ali.kashifmalik@gmail.com /home/deploy/bin/daily_server_summary.py >> /home/deploy/monitoring/daily_summary.log 2>&1
```

Change `ALERT_EMAIL_TO` if you want the summary sent elsewhere.

## Critical Alert Email

The critical alert mailer is [critical_server_alert.py](/C:/Users/ALI/Documents/VS%20Projects/local_social/scripts/critical_server_alert.py).

It checks for:

- required Docker containers missing or unhealthy
- app URL down
- storage health URL down
- disk usage above threshold

It uses a cooldown to avoid spam. Default values:

- recipient: `ali.kashifmalik@gmail.com`
- cooldown: `30` minutes
- disk threshold: `90%`

Recommended cron:

```cron
*/5 * * * * ALERT_EMAIL_TO=ali.kashifmalik@gmail.com /home/deploy/bin/critical_server_alert.py >> /home/deploy/monitoring/critical_alert.log 2>&1
```

You can force a test alert manually with:

```bash
FORCE_ALERT=1 ALERT_EMAIL_TO=ali.kashifmalik@gmail.com /home/deploy/bin/critical_server_alert.py
```
