#!/usr/bin/env python3
from __future__ import annotations

import os
import smtplib
import subprocess
from email.message import EmailMessage
from pathlib import Path


HOME = Path.home()
SUPABASE_ENV = HOME / "supabase-project" / ".env"
HEALTH_LOG = HOME / "monitoring" / "health.log"
BACKUP_ROOT = HOME / "backups" / "supabase"


def read_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"')
    return values


def tail_text(path: Path, max_lines: int) -> str:
    if not path.exists():
        return "not available"
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    return "\n".join(lines[-max_lines:]) if lines else "empty"


def command_output(command: list[str]) -> str:
    try:
        result = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
        )
        output = (result.stdout or "") + (result.stderr or "")
        return output.strip() or "no output"
    except Exception as exc:  # pragma: no cover
        return f"error: {exc}"


def latest_backup_info() -> str:
    latest = BACKUP_ROOT / "latest"
    if not latest.exists():
        return "latest backup symlink not found"
    target = latest.resolve()
    dump = target / "db" / "postgres.dump"
    storage = target / "storage" / "storage.tar.gz"
    config = target / "config" / "config.tar.gz"
    parts = [
        f"path: {target}",
        f"db dump: {'yes' if dump.exists() else 'no'}",
        f"storage archive: {'yes' if storage.exists() else 'no'}",
        f"config archive: {'yes' if config.exists() else 'no'}",
    ]
    return "\n".join(parts)


def build_body(recipient: str) -> str:
    hostname = command_output(["hostname"])
    uptime = command_output(["uptime", "-p"])
    free = command_output(["free", "-h"])
    df_root = command_output(["df", "-h", "/"])
    docker_ps = command_output(
        ["docker", "ps", "--format", "table {{.Names}}\t{{.Status}}"]
    )
    health_tail = tail_text(HEALTH_LOG, 40)
    backup_info = latest_backup_info()

    return f"""Daily server summary

Recipient: {recipient}
Hostname: {hostname}
Uptime: {uptime}

Disk:
{df_root}

Memory:
{free}

Containers:
{docker_ps}

Latest backup:
{backup_info}

Recent health log:
{health_tail}
"""


def main() -> int:
    env = read_env(SUPABASE_ENV)
    smtp_host = env.get("SMTP_HOST")
    smtp_port = int(env.get("SMTP_PORT", "465"))
    smtp_user = env.get("SMTP_USER")
    smtp_pass = env.get("SMTP_PASS")
    sender = env.get("SMTP_ADMIN_EMAIL", "hello@allonssy.com")
    sender_name = env.get("SMTP_SENDER_NAME", "Allonssy")
    recipient = os.environ.get("ALERT_EMAIL_TO", "ali.kashifmalik@gmail.com")

    missing = [
        name
        for name, value in [
            ("SMTP_HOST", smtp_host),
            ("SMTP_USER", smtp_user),
            ("SMTP_PASS", smtp_pass),
        ]
        if not value
    ]
    if missing:
        raise SystemExit(f"missing SMTP config: {', '.join(missing)}")

    body = build_body(recipient)
    msg = EmailMessage()
    msg["Subject"] = "Allonssy daily server summary"
    msg["From"] = f"{sender_name} <{sender}>"
    msg["To"] = recipient
    msg.set_content(body)

    with smtplib.SMTP_SSL(smtp_host, smtp_port, timeout=30) as server:
        server.login(smtp_user, smtp_pass)
        server.send_message(msg)

    print(f"sent daily summary to {recipient}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
