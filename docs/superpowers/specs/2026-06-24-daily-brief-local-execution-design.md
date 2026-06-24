# Daily Brief — Local Execution Design

**Date:** 2026-06-24
**Status:** Approved; building
**Supersedes:** Sub-project 3 ("Daily routine — scheduled cloud agent") of
`2026-06-19-daily-brief-automation-design.md`. Hosting, distill, and the routine itself
are unchanged.

## Problem

The brief ran as a scheduled Claude **cloud** routine. That sandbox enforces an egress
allow-policy: every outbound HTTPS (RSS feeds, article pages, the r.jina.ai proxy) returns
a policy-403; only the `WebSearch` tool works. But `brief-routine.md` Step 1 (RSS sweep +
fetch candidates) and Step 3 (mandatory fetch-to-verify, no hallucination) both require
fetching arbitrary URLs. In closed egress both collapse → ~0 new items every run.

Verified 2026-06-24 from the Mac: the same feeds return 200/301 and the jina proxy 200.
The failure is the *environment*, not the feeds or the routine.

## Decision

Run the daily job **locally on the Mac** via a `launchd` user agent, where egress is open
and the GoodLinks taste data already lives. Cost: $0 extra — the local `claude` CLI uses
the existing subscription (no API key). The cloud routine has been deleted.

| Question | Decision |
|----------|----------|
| Where it runs | Local `launchd` user agent |
| Build approach | Agent does it all — `claude` headless follows `brief-routine.md` verbatim |
| Schedule | 10:30 daily, `Asia/Tokyo` (Mac is JST) |
| Taste refresh | `distill_interests.jl` runs before each brief |
| Auth | macOS login keychain (subscription + GitHub token); `claude setup-token` fallback |
| Permissions | `--dangerously-skip-permissions` (trusted personal repo) |
| Publish target | `main` → live via GitHub Pages (no PR) |

## Components

1. **`scripts/run_brief.sh`** — wrapper: explicit PATH → `git pull --ff-only` →
   `distill_interests.jl` (non-fatal) → `claude -p "<follow brief-routine.md>"
   --dangerously-skip-permissions`. Tees to `~/Library/Logs/daily-brief/<date>.log`;
   `osascript` notification on failure. A `BRIEF_PREVIEW=1` env var switches to a dry-run
   (Steps 1–5 → `editions/_preview.html`, no publish, no commit).
2. **`scripts/org.garrek.daily-brief.plist`** — LaunchAgent template (repo-tracked).
   Installed copy at `~/Library/LaunchAgents/`. `StartCalendarInterval` 10:30, runs the
   wrapper, captures stdout/stderr for catastrophic (pre-log) failures.
3. **Wake guarantee (optional, one-time):** `sudo pmset repeat wake MTWRFSU 10:25:00`.
   Without it, `launchd` runs the missed job on next wake.

## Reliability

`claude` (subscription) and `git push` (GitHub token via `osxkeychain`) both read the login
keychain. A user LaunchAgent runs in the logged-in session, so both work whenever the user
is logged in — even at the lock screen. Only a full **logout** breaks it; the `setup-token`
env-var path is the fallback.

## Unchanged

`brief-routine.md`, `interests.toml`, `template.html`, `assets/brief.css`,
`distill_interests.jl`. Quiet/empty-day safety and the no-fabrication rule are already in
the routine (Steps 3, 7).

## Verify

1. `BRIEF_PREVIEW=1 bash scripts/run_brief.sh` → real fetched items in `editions/_preview.html`.
2. Install + `launchctl kickstart` the agent; watch the log.
3. Confirm a real run publishes `editions/<date>.html` + `index.html` and pushes to `main`.
