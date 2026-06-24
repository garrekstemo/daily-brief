#!/bin/bash
# Daily Brief - local runner (launchd-invoked).
# Refresh taste, then run brief-routine.md headless and publish to main.
# Set BRIEF_PREVIEW=1 for a dry-run: writes editions/_preview.html, no publish/commit.

set -uo pipefail

REPO="/Users/garrek/Developer/daily-brief"
LOGDIR="$HOME/Library/Logs/daily-brief"
DATE="$(TZ=Asia/Tokyo date +%Y-%m-%d)"

# launchd hands us a minimal PATH; make the tools we need findable.
export PATH="$HOME/.local/bin:$HOME/.juliaup/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

mkdir -p "$LOGDIR"
LOG="$LOGDIR/$DATE.log"
# Interactive run: show output live AND log it. launchd run (no TTY): log only.
if [ -t 1 ]; then exec > >(tee -a "$LOG") 2>&1; else exec >>"$LOG" 2>&1; fi

log()    { echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] $*"; }
notify() { /usr/bin/osascript -e "display notification \"$1\" with title \"Daily Brief\"" >/dev/null 2>&1 || true; }
fail()   { log "FAIL: $1"; notify "$1"; exit 1; }

MODE="publish"; [[ "${BRIEF_PREVIEW:-0}" == "1" ]] && MODE="preview"
log "=== run start ($DATE Asia/Tokyo) mode=$MODE ==="

cd "$REPO" || fail "repo not found at $REPO"
command -v claude >/dev/null 2>&1 || fail "claude CLI not on PATH"

# 1. Sync (fast-forward only; never auto-merge).
if git pull --ff-only --quiet; then
  log "git pull: ok"
else
  fail "git pull is not fast-forward (or offline) - aborting"
fi

# 2. Taste refresh (non-fatal: a stale profile still beats no brief).
if command -v julia >/dev/null 2>&1; then
  if julia "$REPO/scripts/distill_interests.jl"; then log "distill: ok"; else log "distill: FAILED (continuing)"; fi
else
  log "distill: julia not found, skipping"
fi

# 3. Generate (and, in publish mode, commit + push from inside the routine).
if [[ "$MODE" == "preview" ]]; then
  PROMPT="Read brief-routine.md and follow Steps 1-5 exactly. For Step 6, DEVIATE: write the rendered HTML ONLY to editions/_preview.html. Do NOT write index.html or editions/<today>.html, do NOT modify archive.html, current.json, or published-hashes.txt, and do NOT git commit or push. This is a dry-run preview."
else
  PROMPT="Read brief-routine.md and follow it exactly to generate and publish today's edition."
fi

log "claude: starting ($MODE)"
if claude -p "$PROMPT" --dangerously-skip-permissions; then
  log "=== run done (mode=$MODE) ==="
  [[ "$MODE" == "preview" ]] && notify "Preview ready: editions/_preview.html"
else
  rc=$?
  fail "claude exited $rc - see $LOGDIR/$DATE.log"
fi
