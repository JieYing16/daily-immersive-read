#!/usr/bin/env python3
"""Generate reads.json (the app's data file) from daily_reads.md.

Replaces the old build_reader.py, which baked a whole HTML page. The reader is
now a static PWA (index.html + app.js + app.css + styles.css) that fetches this
JSON, so a new day only changes data — the shell stays cached.

    pip install markdown
    python build_reader.py
"""
import json
import math
import re
import shutil
import sys
from datetime import datetime
from pathlib import Path

try:
    import markdown
except ImportError:
    sys.exit("Missing dependency. Run: pip install markdown")

BASE = Path(__file__).parent
SRC = BASE / "daily_reads.md"
OUT = BASE / "reads.json"

WORDS_PER_MIN = 200


def slug(s):
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def parse_days(text):
    parts = re.split(r"(?m)^##\s+(\d{4}-\d{2}-\d{2})\s*$", text)
    days = []
    for i in range(1, len(parts), 2):
        date = datetime.strptime(parts[i].strip(), "%Y-%m-%d")
        body = re.sub(r"(?m)^---\s*$", "", parts[i + 1]).strip()
        blocks = [b.strip() for b in re.split(r"(?m)(?=^###\s*Topic:)", body) if b.strip()]
        days.append((date, blocks))
    days.sort(key=lambda d: d[0], reverse=True)
    return days


def split_block(block):
    """Pull the topic, title and the special lines out of one topic block."""
    topic = ""
    m = re.search(r"(?m)^###\s*Topic:\s*(.+)$", block)
    if m:
        topic = m.group(1).strip()
        block = re.sub(r"(?m)^###\s*Topic:\s*.+$", "", block)

    title = ""
    tm = re.search(r"(?m)^\*\*(.+?)\*\*\s*$", block)
    if tm:
        title = tm.group(1).strip()
        block = block.replace(tm.group(0), "", 1)

    why = note = source = ""
    keep = []
    for line in block.splitlines():
        s = line.strip()
        if s.startswith("**Why it matters:**"):
            why = s[len("**Why it matters:**"):].strip()
        elif s.startswith("**Jargon note:**"):
            note = s
        elif re.match(r"^\*Source", s):
            source = s.strip("*").strip()
        else:
            keep.append(line)
    return topic, title, "\n".join(keep).strip(), why, note, source


def build():
    md = markdown.Markdown(extensions=["extra"])

    def conv(text):
        md.reset()
        return md.convert(text) if text else ""

    days = []
    for date, blocks in parse_days(SRC.read_text(encoding="utf-8")):
        key = date.strftime("%Y-%m-%d")
        entries = []
        for block in blocks:
            topic, title, body, why, note, source = split_block(block)
            words = len(re.findall(r"\w+", " ".join([body, why, note])))
            entries.append({
                "id": "%s-%s" % (key, slug(topic) or "entry"),
                "topic": topic,
                "title": title,
                "mins": max(1, min(4, math.ceil(words / WORDS_PER_MIN))),
                "bodyHtml": conv(body),
                "whyHtml": conv(why).replace("<p>", "").replace("</p>", "").strip(),
                "noteHtml": conv(note),
                "sourceHtml": source,
            })
        days.append({
            "date": key,
            "label": "%s, %d %s" % (date.strftime("%A"), date.day, date.strftime("%B %Y")),
            "entries": entries,
        })

    payload = {"generated": datetime.now().isoformat(timespec="seconds"), "days": days}
    OUT.write_text(json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8")
    print("Wrote %s (%d days, %d entries)" % (
        OUT, len(days), sum(len(d["entries"]) for d in days)))
    publish(OUT)


def publish(data_file):
    """Copy reads.json to a local publish dir (e.g. OneDrive), if configured."""
    cfg = BASE / "publish_path.txt"
    if not cfg.exists():
        return
    candidates = [ln.strip() for ln in cfg.read_text(encoding="utf-8").splitlines() if ln.strip()]
    dest = _resolve_dest(candidates)
    if dest is None:
        print("Publish skipped: no destination found from %s" % candidates)
        return
    shutil.copy2(data_file, dest / data_file.name)
    print("Published to %s" % (dest / data_file.name))


def _resolve_dest(candidates):
    for c in candidates:
        p = Path(c)
        if p.is_dir():
            return p
    for c in candidates:
        name = Path(c.replace("\\", "/")).name
        for hit in sorted(Path("/sessions").glob("*/mnt/%s" % name)):
            if hit.is_dir():
                return hit
    return None


if __name__ == "__main__":
    build()
