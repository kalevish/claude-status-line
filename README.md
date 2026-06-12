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

## Pricing

The today/MTD **cost** figures are estimated from a hard-coded rate table in
`statusline-usage.py`. The shipped defaults are Anthropic list prices as of
**June 2026** (USD per million tokens):

| Model family | Input | Output | Cache write (1.25×) | Cache read (0.1×) |
|--------------|------:|-------:|--------------------:|------------------:|
| Fable 5      | $10.00 | $50.00 | $12.50 | $1.00 |
| Opus         |  $5.00 | $25.00 |  $6.25 | $0.50 |
| Sonnet       |  $3.00 | $15.00 |  $3.75 | $0.30 |
| Haiku        |  $1.00 |  $5.00 |  $1.25 | $0.10 |

The key is matched as a **substring** of the model id (e.g. `"opus"` matches
`claude-opus-4-8`). A model whose family isn't in the table contributes **tokens
but $0 cost** — so an unknown model silently undercounts spend.

> ⚠️ **UPDATE THESE RATES FOR YOUR OWN PLAN BEFORE TRUSTING THE COST.**
> These are public list prices and **will drift** as Anthropic changes pricing
> or adds models. Your actual rate may differ (volume discounts, enterprise
> agreements, a model family not listed). Edit the `RATES` dict at the top of
> `statusline-usage.py` to match what *you* pay. The token counts are always
> accurate; the dollar figures are only as good as this table.

## Customizing

- **Colors / layout** — the ANSI color vars and the final two `echo -e` lines in
  `statusline.sh` control the look.
- **Refresh interval** — the `-mmin +1` (60s) test in `statusline.sh` controls
  how often the background scan runs.

## Notes

- Token cost is an **estimate** based on the rates you configure; it won't match
  a billing dashboard to the penny.
- The MTD scan only reads files modified in the current month, so it stays fast
  even with a large transcript history.
