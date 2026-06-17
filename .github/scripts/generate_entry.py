#!/usr/bin/env python3
"""Fetch top news and generate a daily_reads.md entry via GitHub Models (free)."""

import os
import re
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path

import feedparser
from openai import OpenAI

MYT = timezone(timedelta(hours=8))
REPO_ROOT = Path(__file__).resolve().parents[2]
DAILY_READS = REPO_ROOT / "daily_reads.md"

TOPICS = ["AI Technology", "Geopolitics", "Environment", "Economics"]

FEEDS = {
    "AI Technology": "https://hnrss.org/frontpage",
    "Geopolitics":   "http://feeds.bbci.co.uk/news/world/rss.xml",
    "Environment":   "http://feeds.bbci.co.uk/news/science_and_environment/rss.xml",
    "Economics":     "http://feeds.bbci.co.uk/news/business/rss.xml",
}


def pick_topic(existing: str) -> str:
    last = re.search(r"### Topic:\s*(.+)", existing)
    last_topic = last.group(1).strip() if last else ""
    day_idx = datetime.now(MYT).weekday()
    available = [t for t in TOPICS if t.lower() != last_topic.lower()]
    return available[day_idx % len(available)]


def fetch_articles(topic: str) -> list[dict]:
    feed = feedparser.parse(FEEDS[topic])
    articles = []
    for entry in feed.entries[:8]:
        title = entry.get("title", "").strip()
        summary = re.sub(r"<[^>]+>", "", entry.get("summary", entry.get("description", ""))).strip()
        articles.append({"title": title, "summary": summary[:400]})
    return articles


def generate_entry(topic: str, articles: list[dict], today_str: str) -> str:
    client = OpenAI(
        base_url="https://models.inference.ai.azure.com",
        api_key=os.environ["GITHUB_TOKEN"],
    )

    articles_text = "\n\n".join(
        f"Title: {a['title']}\nSummary: {a['summary']}" for a in articles
    )

    response = client.chat.completions.create(
        model="gpt-4o-mini",
        temperature=0.4,
        max_tokens=600,
        messages=[{
            "role": "user",
            "content": f"""Write a daily news digest entry for this markdown log. Topic: {topic}. Date: {today_str}.

Source articles:
{articles_text}

Pick the single most newsworthy story. Output EXACTLY this format — nothing before or after:

### Topic: {topic}

**<Catchy headline summarising the story>**

- <Key fact 1 — define any jargon in plain English>
- <Key fact 2>
- <Key fact 3>
- <Key fact 4 if genuinely needed>

**Why it matters:** <One sentence on the broader significance.>

*Source: <Publication name>, <Month Year>*

Rules: plain English, define jargon on first use, bullet points are facts not opinions, "Why it matters" is one sentence only, source line has no URL."""
        }],
    )
    return response.choices[0].message.content.strip()


def prepend_entry(entry_body: str, today_str: str) -> bool:
    existing = DAILY_READS.read_text(encoding="utf-8") if DAILY_READS.exists() else "# Daily Immersive Read Log\n"

    if f"## {today_str}" in existing:
        print(f"Entry for {today_str} already exists — skipping.")
        return False

    header = "# Daily Immersive Read Log"
    new_block = f"\n\n## {today_str}\n\n{entry_body}\n\n---"
    updated = existing.replace(header, header + new_block, 1)
    DAILY_READS.write_text(updated, encoding="utf-8")
    return True


def main() -> None:
    today_str = datetime.now(MYT).strftime("%Y-%m-%d")
    existing = DAILY_READS.read_text(encoding="utf-8") if DAILY_READS.exists() else ""

    if f"## {today_str}" in existing:
        print(f"Entry for {today_str} already exists — nothing to do.")
        sys.exit(0)

    topic = pick_topic(existing)
    print(f"Date: {today_str} | Topic: {topic}")

    articles = fetch_articles(topic)
    if not articles:
        print("No articles fetched — aborting.")
        sys.exit(1)

    entry = generate_entry(topic, articles, today_str)
    print(f"\nGenerated entry:\n{entry}\n")

    if prepend_entry(entry, today_str):
        print(f"Written to {DAILY_READS}")


if __name__ == "__main__":
    main()
