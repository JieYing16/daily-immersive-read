# Daily Immersive Read

> Personal knowledge log that turns a daily markdown journal into a readable, mobile-friendly HTML feed.

**Goal:** Deliver one short, digestible piece of new information daily (1–2 min read) to broaden my knowledge across four rotating topics.

## Topics (rotate daily or mix)

- **AI technology** — new tools, techniques, how AI/ML systems are built, research breakthroughs
- **Geopolitics** — major developments, conflicts, policy shifts, international relations
- **Environment/climate** — global warming, El Niño/La Niña, conservation news, climate science
- **Economics** — markets, macroeconomic trends, trade, monetary policy, economic concepts explained

## Entry format

- Title (catchy, 5–8 words)
- 3–5 bullet points or a short paragraph (~150–200 words total)
- One "Why it matters" takeaway line
- Source/date if referencing real news

**Style:** Clear, neutral tone; no jargon without explanation; beginner-friendly.

## How it works

`daily_reads.md` is the single source of truth — an append-only log. Each new
entry is added under a `## YYYY-MM-DD` header. Running the build script
regenerates `daily_reads.html`, a styled, dark-mode-aware reader grouped by month.

```
daily_reads.md   ──►  build_reader.py  ──►  daily_reads.html
(source of truth)      (generator)          (generated; gitignored)
```

## Setup

```bash
pip install -r requirements.txt
```

## Usage

1. Add a new dated entry to `daily_reads.md` (see existing entries for the format).
2. Rebuild the reader:

   ```bash
   python build_reader.py
   ```

3. Open `daily_reads.html` in Safari on your iPhone for large, readable text.

## Project structure

| File                | Purpose                                            |
| ------------------- | -------------------------------------------------- |
| `daily_reads.md`    | Append-only log of entries (source of truth)       |
| `build_reader.py`   | Generates the HTML reader from the log             |
| `daily_reads.html`  | Generated reader — **not tracked** (rebuild it)    |
| `requirements.txt`  | Python dependencies                                |

## Notes

- `daily_reads.html` is a build artifact and is gitignored. Run `build_reader.py`
  to regenerate it after pulling changes.

## License

[MIT](LICENSE) © 2026 Jie Ying Lim
