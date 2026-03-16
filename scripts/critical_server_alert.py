#!/usr/bin/env python3
from __future__ import annotations

import os
import shutil
import smtplib
import subprocess
import time
from email.message import EmailMessage
from pathlib import Path


HOME = Path.home()
SUPABASE_ENV = HOME / "supabase-project" / ".env"
STATE_DIR = HOME / "monitoring"
STATE_FILE = STATE_DIR / "critical_alert_state.txt"
COOLDOWN_SECONDS = int(os.environ.get("ALERT_COOLDOWN_SECONDS", "1800"))
DISK_THRESHOLD = int(os.environ.get("ALERT_DISK_PERCENT", "90"))
RECIPIENT = os.environ.get("ALERT_EMAIL_TO", "ali.kashifmalik@gmail.com")
FORCE_ALERT = os.environ.get("FORCE_ALERT", "0") == "1"


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


def run(command: list[str]) -> tuple[int, str]:
    result = subprocess.run(
        command,
        check=False,
        capture_output=True,
        text=True,
        timeout=30,
    )
    output = ((result.stdout or "") + (result.stderr or "")).strip()
    return result.returncode, output


def check_url(url: str, expected: set[int]) -> str | None:
    code, output = run(
        ["curl", "-k", "-L", "-s", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "20", url]
    )
    status = output.strip() if output else "000"
    if code != 0 or not status.isdigit() or int(status) not in expected:
        return f"url check failed: {url} -> {status}"
    return None


def docker_issues() -> list[str]:
    issues: list[str] = []
    code, output = run(["docker", "ps", "--format", "{{.Names}}|{{.Status}}"])
    if code != 0:
        return [f"docker ps failed: {output or code}"]
    for line in output.splitlines():
        if not line.strip():
            continue
        name, _, status = line.partition("|")
        lowered = status.lower()
        if "unhealthy" in lowered or "restarting" in lowered:
            issues.append(f"container unhealthy: {name} -> {status}")
    required = {
        "supabase-db",
        "supabase-auth",
        "supabase-kong",
        "supabase-storage",
        "supabase-rest",
        "supabase-edge-functions",
    }
    present = {line.partition("|")[0] for line in output.splitlines() if line.strip()}
    missing = sorted(required - present)
    for name in missing:
        issues.append(f"required container missing: {name}")
    return issues


def disk_issue() -> str | None:
    total, used, free = shutil.disk_usage("/")
    used_pct = int((used / total) * 100)
    if used_pct >= DISK_THRESHOLD:
        return f"disk usage high: {used_pct}% used on /"
    return None


def collect_issues() -> list[str]:
    issues: list[str] = []
    issues.extend(docker_issues())
    for possible in [
        disk_issue(),
        check_url("https://app.allonssy.com", {200}),
        check_url("https://supabase.allonssy.com", {401}),
        check_url("https://supabase.allonssy.com/storage/v1/status", {200}),
    ]:
        if possible:
            issues.append(possible)
    return issues


def should_send(now: int) -> bool:
    if FORCE_ALERT:
        return True
    if not STATE_FILE.exists():
        return True
    try:
        last_sent = int(STATE_FILE.read_text(encoding="utf-8").strip() or "0")
    except ValueError:
        return True
    return (now - last_sent) >= COOLDOWN_SECONDS


def mark_sent(now: int) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(str(now), encoding="utf-8")


def send_email(issues: list[str]) -> None:
    env = read_env(SUPABASE_ENV)
    smtp_host = env.get("SMTP_HOST")
    smtp_port = int(env.get("SMTP_PORT", "465"))
    smtp_user = env.get("SMTP_USER")
    smtp_pass = env.get("SMTP_PASS")
    sender = env.get("SMTP_ADMIN_EMAIL", "hello@allonssy.com")
    sender_name = env.get("SMTP_SENDER_NAME", "Allonssy")
    if not smtp_host or not smtp_user or not smtp_pass:
        raise SystemExit("missing SMTP config")

    body = "Critical server alert\n\n" + "\n".join(f"- {item}" for item in issues)
    msg = EmailMessage()
    msg["Subject"] = "Allonssy critical server alert"
    msg["From"] = f"{sender_name} <{sender}>"
    msg["To"] = RECIPIENT
    msg.set_content(body)

    with smtplib.SMTP_SSL(smtp_host, smtp_port, timeout=30) as server:
        server.login(smtp_user, smtp_pass)
        server.send_message(msg)


def main() -> int:
    now = int(time.time())
    issues = collect_issues()
    if FORCE_ALERT:
        issues = issues or ["forced test alert"]
    if not issues:
        print("no critical issues")
        return 0
    if not should_send(now):
        print("issues detected but cooldown active")
        return 0
    send_email(issues)
    mark_sent(now)
    print(f"sent critical alert to {RECIPIENT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
