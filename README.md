# Daily Immersive Read — new PWA

Replaces the single generated `index.html`. The reader is now a static app shell
that fetches its content, so a new day changes only `reads.json`.

```
daily_reads.md  ──►  build_reader.py  ──►  reads.json  ──►  index.html + app.js
(source of truth)     (generator)          (data)           (shell, cached)
```

## Files

| File | Purpose |
| --- | --- |
| `index.html` | App shell — top bar, drawer mount, nothing content-specific |
| `app.js` | Screens, routing, reading state (vanilla JS, no build step) |
| `app.css` | App layer on top of the design tokens |
| `styles.css` | Organic design-system tokens (copied; do not edit here) |
| `sw.js` | Service worker — shell cached, `reads.json` network-first |
| `build_reader.py` | Parses `daily_reads.md` → `reads.json` |
| `reads.json` | Generated data (commit it — it is what the phone fetches) |
| `manifest.webmanifest`, `icon-*.png` | Unchanged |

## Migrating the repo

1. Copy this folder's files over the repo root (they replace `index.html`,
   `build_reader.py`, `sw.js`).
2. Delete `daily_reads.html` — no longer generated.
3. Change `commit_daily_reads.ps1` / `scheduler/run_daily.ps1` to commit
   `daily_reads.md` **and `reads.json`** instead of `index.html`.
4. `python build_reader.py`, then push. On the phone, close and reopen the PWA
   once so the new service worker (`dir-v2`) takes over.

## What it does

- **Today** — the four topic cards, all four on one screen, no scrolling.
  Opening one auto-marks it read; the pill toggles that back.
- **No fresh day?** It serves the newest day you haven't finished, with a note
  saying so, instead of an empty screen.
- **Progress** — 35-day grid, filled per day read. No streak, so a day the
  laptop was off costs nothing.
- **Bonus read** — appears only once today's four are done, drawn from the
  oldest unopened entry in the archive. Below it, a topic request box.
- **Archive / Bookmarks / Settings** — theme (light/dark/auto), text size,
  topics, reminder time, export/import.

## Still to wire up

**Accounts.** The Sign in buttons currently explain what's missing. To make them
real, create a free Firebase project, enable Google and Apple providers plus
Firestore, and add to `index.html` before `app.js`:

```html
<script type="module">
  import { initializeApp } from 'https://www.gstatic.com/firebasejs/10.12.0/firebase-app.js';
  window.FB = initializeApp({ apiKey: '…', authDomain: '…', projectId: '…' });
</script>
```

then replace the `data-auth` handler in `app.js` with `signInWithPopup` and sync
the `dir.v1` object to a `users/{uid}` document. Google/Apple sign-in means no
password to store, reset or leak — which also answers the recovery question:
account recovery is handled by Google/Apple, not by us. Multi-user hosting comes
free with the same setup, since each user's state is keyed by `uid`.

**Topic requests.** Queued topics are held in localStorage. For the laptop to
see them they need somewhere shared — the same Firestore document is the natural
place once accounts exist.

**Reminders.** The time in Settings is stored but not yet fired. On iOS, PWA web
push needs the app installed to the Home Screen; the existing Shortcuts
automation still works in the meantime.
