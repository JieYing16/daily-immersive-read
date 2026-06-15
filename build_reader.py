#!/usr/bin/env python3
"""Generate a mobile-friendly HTML reader from daily_reads.md.

Single source of truth = daily_reads.md (append-only log).
Run this after each new entry to refresh daily_reads.html:

    pip install markdown        # one-time
    python build_reader.py

Open daily_reads.html in Safari on your iPhone for large, readable text.
"""
import re
import shutil
import sys
from collections import OrderedDict
from datetime import datetime
from pathlib import Path

try:
    import markdown
except ImportError:
    sys.exit("Missing dependency. Run: pip install markdown")

BASE = Path(__file__).parent
SRC = BASE / "daily_reads.md"
OUT = BASE / "daily_reads.html"

# Topic -> colour accent (falls back to a neutral grey)
TOPIC_COLOURS = {
    "ai technology": "#3b82f6",
    "geopolitics": "#ef4444",
    "environment/climate": "#22c55e",
    "environment": "#22c55e",
    "economics": "#a855f7",
}


def parse_entries(text):
    """Split the log on '## YYYY-MM-DD' headers into (date, body) pairs."""
    parts = re.split(r"(?m)^##\s+(\d{4}-\d{2}-\d{2})\s*$", text)
    entries = []
    for i in range(1, len(parts), 2):
        date_str = parts[i].strip()
        body = re.sub(r"(?m)^---\s*$", "", parts[i + 1]).strip()
        entries.append((datetime.strptime(date_str, "%Y-%m-%d"), body))
    entries.sort(key=lambda e: e[0], reverse=True)  # newest first
    return entries


def render_card(dt, body, md):
    """Turn one day's markdown body into a styled HTML card."""
    topic = ""
    m = re.search(r"(?m)^###\s*Topic:\s*(.+)$", body)
    if m:
        topic = m.group(1).strip()
        body = re.sub(r"(?m)^###\s*Topic:\s*.+$", "", body)

    title = ""
    tm = re.search(r"(?m)^\*\*(.+?)\*\*\s*$", body)
    if tm:
        title = tm.group(1).strip()
        body = body.replace(tm.group(0), "", 1)

    md.reset()
    body_html = md.convert(body.strip())
    # Highlight the takeaway and source lines via CSS hooks
    body_html = body_html.replace(
        "<p><strong>Why it matters:</strong>",
        '<p class="why"><strong>Why it matters:</strong>',
    )
    body_html = re.sub(r"<p><em>(Source[^<]*)</em></p>",
                       r'<p class="source">\1</p>', body_html)

    colour = TOPIC_COLOURS.get(topic.lower(), "#64748b")
    pill = (f'<span class="topic" style="background:{colour}">{topic}</span>'
            if topic else "")
    heading = f'<h2 class="title">{title}</h2>' if title else ""
    day_label = dt.strftime("%A, %-d %B %Y")
    return (f'<article class="card">'
            f'<div class="meta">{pill}'
            f'<span class="date">{day_label}</span></div>'
            f'{heading}{body_html}</article>')


def build():
    entries = parse_entries(SRC.read_text(encoding="utf-8"))
    md = markdown.Markdown(extensions=["extra"])

    months = OrderedDict()
    for dt, body in entries:
        months.setdefault(dt.strftime("%Y-%m"), []).append((dt, body))

    sections = []
    for idx, (key, items) in enumerate(months.items()):
        label = datetime.strptime(key, "%Y-%m").strftime("%B %Y")
        cards = "".join(render_card(dt, body, md) for dt, body in items)
        open_attr = " open" if idx == 0 else ""  # newest month expanded
        sections.append(
            f'<details class="month"{open_attr}>'
            f'<summary>{label}</summary>{cards}</details>'
        )

    generated = datetime.now().strftime("%-d %b %Y, %H:%M")
    html = HEAD + "".join(sections) + FOOT.replace("{{GEN}}", generated)
    OUT.write_text(html, encoding="utf-8")
    print(f"Wrote {OUT} ({len(entries)} entries)")
    publish(OUT)


def publish(html_file):
    """Copy the reader to a local publish dir (e.g. OneDrive) for the iPhone.

    The destination is read from 'publish_path.txt' (one line, an absolute
    folder path). That file is gitignored so the public repo never exposes a
    personal path. Skipped silently if the file is missing.
    """
    cfg = BASE / "publish_path.txt"
    if not cfg.exists():
        return
    dest_dir = Path(cfg.read_text(encoding="utf-8").strip())
    if not dest_dir.is_dir():
        print(f"Publish skipped: {dest_dir} is not a folder")
        return
    shutil.copy2(html_file, dest_dir / html_file.name)
    print(f"Published to {dest_dir / html_file.name}")


HEAD = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>Daily Immersive Read</title>
<style>
  :root { font-size: 19px; }
  * { box-sizing: border-box; }
  body {
    margin: 0; padding: 16px max(16px, env(safe-area-inset-right)) 48px;
    max-width: 700px; margin-inline: auto;
    font-family: -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
    line-height: 1.7; color: #1c1c1e; background: #f2f2f7;
    -webkit-text-size-adjust: 100%;
  }
  h1.page { font-size: 1.7rem; margin: 8px 0 20px; }
  details.month { margin-bottom: 22px; }
  details.month > summary {
    font-size: 1.15rem; font-weight: 700; padding: 12px 4px;
    cursor: pointer; list-style: none; color: #3a3a3c;
    border-bottom: 2px solid #d1d1d6;
  }
  details.month > summary::-webkit-details-marker { display: none; }
  details.month > summary::after { content: " ▾"; color: #8e8e93; }
  details.month:not([open]) > summary::after { content: " ▸"; }
  .card {
    background: #fff; border-radius: 18px; padding: 22px 20px;
    margin: 18px 0; box-shadow: 0 1px 4px rgba(0,0,0,.08);
  }
  .meta { display: flex; flex-wrap: wrap; align-items: center; gap: 10px;
          margin-bottom: 10px; }
  .topic { color: #fff; font-size: .8rem; font-weight: 700;
           letter-spacing: .03em; text-transform: uppercase;
           padding: 3px 10px; border-radius: 999px; }
  .date { color: #8e8e93; font-size: .9rem; }
  h2.title { font-size: 1.4rem; line-height: 1.3; margin: 6px 0 14px; }
  .card ul { padding-left: 1.2em; margin: 12px 0; }
  .card li { margin-bottom: 10px; }
  .card p { margin: 12px 0; }
  .why { background: #fff8e1; border-left: 4px solid #f59e0b;
         padding: 12px 14px; border-radius: 8px; }
  .source { color: #8e8e93; font-size: .85rem; font-style: italic; }
  @media (prefers-color-scheme: dark) {
    body { background: #000; color: #e5e5ea; }
    .card { background: #1c1c1e; box-shadow: none; }
    details.month > summary { color: #d1d1d6; border-color: #38383a; }
    .date, .source { color: #8e8e93; }
    .why { background: #2a2410; border-left-color: #f59e0b; }
  }
</style>
</head>
<body>
<h1 class="page">Daily Immersive Read</h1>
"""

FOOT = """
<p class="source" style="text-align:center;margin-top:32px">
  Generated {{GEN}}
</p>
</body>
</html>
"""

if __name__ == "__main__":
    build()
