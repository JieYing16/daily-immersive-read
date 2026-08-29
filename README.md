# Daily Immersive Read

Four short reads a day — AI technology, geopolitics, environment, economics —
written into a markdown log on the laptop and published as an installable
mobile app.

**📱 Live app: <https://jieying16.github.io/daily-immersive-read/>**

Open that link on your phone and add it to the Home Screen. It works offline
after the first visit, and a new day appears on its own — nothing to install,
no app store.

---

## How it works

```
                  ┌── scheduler/run_daily.ps1 (Windows Task Scheduler) ──┐
                  │                                                      │
   claude -p ─────┤                                                      │
   (writes today) │                                                      │
                  ▼                                                      ▼
        daily_reads.md  ──►  build_reader.py  ──►  reads.json  ──►  commit + push
        (source of truth)     (generator)          (data)                │
                                                                         ▼
                                              GitHub Pages ──►  index.html + app.js
                                                                (shell, cached by sw.js)
```

The reader is a static app shell that **fetches** its content, so a new day
changes only `reads.json`. The phone re-downloads one JSON file, not the whole
app.

Once a day, whenever the laptop is actually awake:

1. **Generate** — Claude searches the web and appends today's four topics to
   `daily_reads.md`.
2. **Build** — `build_reader.py` parses the markdown into `reads.json`.
3. **Publish** — `commit_daily_reads.ps1` commits both files and pushes to
   `main`; GitHub Pages serves the result a minute or two later.

Every step is idempotent. Twenty triggers in a day still produce one set of
entries, and a day the laptop stayed shut simply doesn't happen — there is no
streak to break.

---

## The app

| Screen | What it does |
| --- | --- |
| **Today** | The four topic cards on one screen, no scrolling. Opening one auto-marks it read; the pill toggles that back. |
| **Progress** | A 35-day grid, filled per day read. No streak counter, deliberately. |
| **Archive** | Every past day, newest first. |
| **Bookmarks** | Anything you saved while reading. |
| **Settings** | Theme (light/dark/auto), text size, topics, reminder time, export/import. |
| **Account** | Placeholder — see [Not wired up yet](#not-wired-up-yet). |

Two behaviours worth knowing:

- **No fresh day?** The app serves the newest day you haven't finished, with a
  note saying so, rather than an empty screen.
- **Bonus read** appears only once today's four are done, drawn from the oldest
  unopened entry in the archive. Below it is a topic request box.

All reading state lives in `localStorage` under the key `dir.v1`, on the device.
Settings → Export writes it out as JSON; Import reads it back.

---

## Repository layout

| File | Purpose |
| --- | --- |
| `daily_reads.md` | **Source of truth.** The whole log, newest day first. |
| `build_reader.py` | Parses `daily_reads.md` → `reads.json`. |
| `reads.json` | Generated data — **commit it**, it is what the phone fetches. |
| `index.html` | App shell — top bar, drawer mount, nothing content-specific. |
| `app.js` | Screens, routing, reading state (vanilla JS, no build step). |
| `app.css` | App layer on top of the design tokens. |
| `styles.css` | Design-system tokens. Copied in; don't edit here. |
| `sw.js` | Service worker — shell cached, `reads.json` network-first. |
| `manifest.webmanifest`, `icon-*.png` | PWA install metadata. |
| `commit_daily_reads.ps1` | Commits `daily_reads.md` + `reads.json`, pushes to `main`. |
| `scheduler/run_daily.ps1` | The daily job: generate → build → commit. |
| `scheduler/install_task.ps1` | Registers the Windows scheduled task. |
| `publish_path.txt` | Optional local copy destination. Gitignored (personal path). |

---

## Getting started

```bash
git clone https://github.com/JieYing16/daily-immersive-read.git
cd daily-immersive-read

python -m venv .venv
.venv\Scripts\Activate.ps1        # PowerShell; bash: source .venv/Scripts/activate
pip install -r requirements.txt

python build_reader.py            # daily_reads.md -> reads.json
```

To preview locally, serve the folder over HTTP — opening `index.html` straight
from the filesystem won't work, because the app fetches `reads.json` and
registers a service worker, and both need a real origin:

```bash
python -m http.server 8000
# then open http://localhost:8000/
```

Requirements: **Python 3.8+** and the `markdown` package. The daily automation
additionally needs the [Claude CLI](https://claude.com/claude-code) on `PATH`
and Windows PowerShell 5.1.

---

## Entry format

`build_reader.py` parses `daily_reads.md` by structure, so the shape below is a
contract, not a style preference. The daily generation prompt points here for it.

````markdown
# Daily Immersive Read Log        ← file heading, once, at the top

## 2026-08-29                     ← one day; newest first

### Topic: AI Technology          ← topic name (drives the card colour)

**Amazon Retires AI's Original Human Workforce**   ← bold title, 5–8 words

- 3–5 bullets, roughly 150–200 words in total.
- **Bold** the numbers, names and dates that carry the point.

**Why it matters:** One paragraph on why a non-expert should care.

**Jargon note:** *Optional.* Defines one term used above.

*Source: CNBC / Fast Company, August 25–27, 2026*

### Topic: Geopolitics
…                                 ← then Environment, then Economics

---                               ← separates this day from the previous one

## 2026-08-15
…
````

What the parser actually enforces:

- Days split on `^## YYYY-MM-DD`; topics split on `^### Topic:`.
- The **first** standalone bold line in a topic block becomes the title.
- Lines starting `**Why it matters:**`, `**Jargon note:**` and `*Source…` are
  lifted into their own fields; everything else is the body.
- `---` lines are stripped, so they are free to use as day separators.
- Reading time is computed from word count (200 wpm, clamped to 1–4 minutes).
- Entry IDs are `<date>-<slugified-topic>`, so **renaming a topic creates a new
  entry** — the old one reverts to unread on every device.

Topic names that have a card colour: `AI Technology`, `Geopolitics`,
`Environment` (or `Environment/Climate`), `Economics`. Anything else renders in
the neutral grey.

---

## The daily automation

### Install

```powershell
# Run as Administrator
.\scheduler\install_task.ps1
```

This registers a scheduled task, **Daily Immersive Read**, with three triggers:
at logon, on resume from sleep (+2 min, to let the network settle), and hourly
all day. Because `run_daily.ps1` exits immediately when today's header is
already in `daily_reads.md`, the overlapping triggers collapse to exactly one
generation per day — at the first moment the laptop is awake.

The task deliberately does **not** wake the machine. Laptop shut all day means
nothing runs, and the next wake picks it up.

```powershell
.\scheduler\install_task.ps1 -Uninstall     # remove the task
```

### Run it by hand

```powershell
.\scheduler\run_daily.ps1 -DryRun    # report what would happen, change nothing
.\scheduler\run_daily.ps1            # generate (if needed), build, commit, push
.\scheduler\run_daily.ps1 -Force     # regenerate even if today already exists
```

Log: `%LOCALAPPDATA%\daily-immersive-read\run_daily.log`

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Done — or nothing to do. |
| `1` | Unhandled error; see the log. |
| `2` | `claude` not found on `PATH`. Edit `$ClaudeExe` in `run_daily.ps1`. |
| `3` | Generation ran but wrote no `## <today>` header. Nothing was committed. |

### Branch safety

`commit_daily_reads.ps1` commits first and pushes second, so a refused push
never loses the day's entries. It pushes `HEAD:main`, and **stops with an error
if you are on a feature branch** rather than quietly fast-forwarding `main` to
whatever else is on that branch. To override deliberately:

```powershell
.\commit_daily_reads.ps1 -PushFromAnyBranch
```

### Local copy (optional)

If `publish_path.txt` exists, `build_reader.py` also copies `reads.json` to the
first directory listed in it — handy for a OneDrive folder the phone already
syncs. The file is gitignored because it holds a machine-specific path; create
it with one absolute path per line, or leave it out entirely.

---

## Deployment

GitHub Pages serves the repository root of `main` — no build step, no workflow.
Push, wait a minute, done.

**When you change the shell** (`index.html`, `app.js`, `app.css`, `styles.css`),
bump the cache name in `sw.js`:

```js
const CACHE = 'dir-v3';   // → 'dir-v4'
```

The `activate` handler deletes every cache whose name differs, which is what
forces phones to drop the old JavaScript instead of serving it for another
launch or two. Then close and reopen the PWA once so the new worker takes over.
Content-only days need no bump — `reads.json` is network-first.

---

## Not wired up yet

**Accounts.** The Sign in buttons currently explain what is missing. To make
them real: create a free Firebase project, enable the Google and Apple providers
plus Firestore, and add this to `index.html` before `app.js`:

```html
<script type="module">
  import { initializeApp } from 'https://www.gstatic.com/firebasejs/10.12.0/firebase-app.js';
  window.FB = initializeApp({ apiKey: '…', authDomain: '…', projectId: '…' });
</script>
```

Then replace the `data-auth` handler in `app.js` with `signInWithPopup` and sync
the `dir.v1` object to a `users/{uid}` document. Google/Apple sign-in means no
password to store, reset or leak — which also answers account recovery: Google
and Apple handle it, not us. Multi-user hosting comes free with the same setup,
since each user's state is keyed by `uid`.

**Topic requests.** Queued topics sit in `localStorage`. For the laptop to see
them they need somewhere shared — the same Firestore document is the natural
home once accounts exist.

**Reminders.** The time in Settings is stored but never fires. On iOS, PWA web
push requires the app be installed to the Home Screen; a Shortcuts automation
works in the meantime.

---

## License

MIT — see [LICENSE](LICENSE).
