# Claude Code Status Line

A two-line status bar for [Claude Code](https://claude.com/claude-code) showing
the model, current repo/branch, a context-usage meter, session cost + timer, and
your **today / month-to-date** token spend across all sessions.

```
[Opus 4.8] 📁 my-repo 🌿 main ████████░░ 80% | ⏱️  12m 34s
Jun 12  ┃ session $0.42  ┃ today $3.10 · 1.2M tok  ┃  MTD $48.70 · 19.4M tok
```

The today/MTD figures are computed by scanning your local Claude Code transcript
files (`~/.claude/projects/**/*.jsonl`) and pricing each assistant message by
model. Nothing leaves your machine.

## How it works

Three scripts and two cache files:

| File | Role |
|------|------|
| `statusline.sh` | Entry point Claude runs on every render. Reads the JSON Claude pipes to stdin, draws the bar, and triggers a background refresh when the cache is stale (>60s). Never blocks the prompt. |
| `statusline-refresh.sh` | Background worker. Runs the Python aggregator and (optionally) the `rtk` savings parse under an atomic lock. |
| `statusline-usage.py` | Scans transcripts, sums per-model token usage, prices it, buckets by local date, writes the usage cache. |
| `~/.claude/.statusline-usage-cache.json` | Cached today/MTD cost + tokens (auto-created). |
| `~/.claude/.statusline-rtk-cache.json` | Cached `rtk` savings (auto-created, only if `rtk` is installed). |

The cache is refreshed in the background under a `mkdir`-based lock so the scan
never delays your prompt. A crashed refresh leaves a stale lock that's reaped
after 5 minutes.

## Requirements

- **Claude Code**
- **`jq`** — `brew install jq` (macOS) / `apt install jq` (Linux)
- **`python3`** — for the usage aggregator
- `git`, `awk`, `date`, `sed` — standard, already on macOS/Linux
- *(optional)* **`rtk`** — a token-saving CLI proxy. If it's not installed, the
  `⚡ rtk` segment is simply omitted; everything else works.

## Install

1. Copy the three scripts into your Claude config dir:

   ```bash
   cp statusline.sh statusline-refresh.sh statusline-usage.py ~/.claude/
   chmod +x ~/.claude/statusline.sh ~/.claude/statusline-refresh.sh
   ```

2. Point Claude Code at the status line. Edit `~/.claude/settings.json` and add
   the `statusLine` block (see `settings.snippet.json`), replacing
   `YOUR_USERNAME` with your actual home path:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "/Users/YOUR_USERNAME/.claude/statusline.sh"
     }
   }
   ```

   Tip: `echo "$HOME/.claude/statusline.sh"` prints the exact path to use.

3. Start (or restart) Claude Code. The first render shows
   `today / MTD — computing…`; the figures appear once the background scan
   finishes (a second or two).

## Customizing

- **Pricing** — edit the `RATES` table in `statusline-usage.py` to match the
  models and current per-million-token prices you care about. The key is matched
  as a substring against the model id (e.g. `"opus"` matches `claude-opus-...`).
- **Colors / layout** — the ANSI color vars and the final two `echo -e` lines in
  `statusline.sh` control the look.
- **Refresh interval** — the `-mmin +1` (60s) test in `statusline.sh` controls
  how often the background scan runs.

## Notes

- Token cost is an **estimate** based on the rates you configure; it won't match
  a billing dashboard to the penny.
- The MTD scan only reads files modified in the current month, so it stays fast
  even with a large transcript history.
