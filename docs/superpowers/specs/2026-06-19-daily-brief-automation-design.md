# Daily Brief — Automation Design

**Date:** 2026-06-19
**Status:** Approved for planning
**Goal:** Take the existing Daily Brief scaffold from "runs once, by hand" to "publishes itself every morning, live on the web," and add the local taste-refresh script the README already advertises.

## Context

The repo (`github.com/garrekstemo/daily-brief`) already contains a complete *scaffold*:

- `brief-routine.md` — the full instruction set a generator follows: RSS sweep + topical
  search → dedup by URL hash → fetch-verify → score against a taste profile → route to
  main/sidebar → render HTML → publish via `git push`.
- `interests.toml` — topics, curiosities, watchlist feeds, regulars, and an auto-distilled
  `[exemplars]` block.
- `template.html`, `assets/brief.css`, `archive.html`, one published edition
  (`editions/2026-06-19.html`), and two hash ledgers (`goodlinks-hashes.txt`,
  `published-hashes.txt`).

Three gaps separate the scaffold from a running product, plus one missing helper:

1. **Not live** — no hosting. README points at `brief.garrek.org`; nothing serves it.
2. **No schedule** — `brief-routine.md` is just a document; nothing runs it daily.
3. **Missing helper** — `distill_interests.jl` (taste refresh) is referenced by the README
   but absent from the repo.

This design covers all three plus a validation step, built in dependency order.

## Decisions (locked)

| Question | Decision |
|----------|----------|
| Hosting | GitHub Pages from `main` root + custom domain `brief.garrek.org` |
| Schedule time | 06:00 daily, `Asia/Tokyo` |
| Distill status | Build fresh |
| Test strategy | Dry-run preview (no publish, no git, no ledger writes) |
| Seen-ledger scope | All **non-deleted** GoodLinks links |
| Distill path | `scripts/distill_interests.jl` (README reference updated to match) |

## GoodLinks data source (verified)

- Store: `~/Library/Group Containers/group.com.ngocluu.goodlinks/Data/data.sqlite`
- Read **read-only / immutable** so a running GoodLinks app is never disturbed:
  `file:<path>?mode=ro&immutable=1`.
- Relevant `link` columns: `url`, `title`, `author`, `starred` (bool), `readAt` (double),
  `addedAt` (double), `deletedAt` (double, 0 = live).
- Timestamps are **Unix epoch seconds** (e.g. `addedAt ≈ 1.78e9`) → `unix2datetime`.
- Current counts: 39 total, 31 non-deleted, 13 read, 1 starred. (Author fields can carry
  scraping cruft, e.g. ScienceDirect "links open overlay panel…"; exemplars use `title`,
  not `author`, so this does not matter.)

---

## Sub-project 1 — Test run (dry-run preview)

**Purpose:** exercise the exact pipeline a cloud routine will follow, surface bugs in
`brief-routine.md`, and produce something to eyeball — *without* fighting same-day dedup
or polluting state.

**Why not a real re-run today:** today's edition exists and its hashes are already in
`published-hashes.txt`; a re-run would dedup against itself, go thin, and Step 7's failure
-safety would abort. So we preview instead.

**Mechanism:**
- Run `brief-routine.md` Steps 1–5 in full (including the non-negotiable fetch-verify in
  Step 3 — every included item must be actually fetched; no fabricated titles/blurbs).
- Deviate only at Step 6 (Publish): write the rendered HTML to **`editions/_preview.html`**
  (gitignored) instead of `editions/<today>.html` / `index.html`. Do **not** append to
  `published-hashes.txt`, do **not** touch `archive.html`, do **not** commit or push.
- Open `editions/_preview.html` locally and review: discovery quality, scoring/routing
  sanity, blurb honesty, HTML correctness (jump anchors, escaping, "yesterday" link).
- Fix any `brief-routine.md` bugs found. If the preview is clearly better than the current
  `2026-06-19.html`, optionally promote it (overwrite today's edition for real).

**Artifacts:** add `editions/_preview.html` to `.gitignore`.

**Done when:** a preview renders with real, fetched items and no routine bugs remain; user
has seen it.

---

## Sub-project 2 — Hosting (GitHub Pages + brief.garrek.org)

**Files added at repo root:**
- `CNAME` — single line `brief.garrek.org`.
- `.nojekyll` — disable Jekyll so `assets/` and any underscore files are served verbatim.

**Repo configuration:**
- Enable GitHub Pages, source = deploy from branch `main`, folder `/` (root). Preferred via
  `gh api -X POST repos/garrekstemo/daily-brief/pages` (build_type = legacy, source branch
  `main` / `/`). Fallback if `gh` lacks write scope: user enables it in Settings → Pages.
- After DNS resolves, enable "Enforce HTTPS" (GitHub auto-provisions a Let's Encrypt cert;
  can take minutes to a few hours).

**User's manual step (DNS):** at the `garrek.org` DNS provider, add
`CNAME  brief  →  garrekstemo.github.io.`
Verify with `dig +short brief.garrek.org` (should chain to `garrekstemo.github.io`) and
then `curl -I https://brief.garrek.org`.

**Why absolute paths are fine:** the site links `/assets/…`, `/editions/…`, `/archive.html`
as root-absolute. A custom domain serves the repo root at the domain apex, so these
resolve. (The default `…github.io/daily-brief/` project URL would 404 on them — this is the
reason the custom domain is part of the design, not an afterthought.)

**Done when:** `https://brief.garrek.org` serves the current edition over HTTPS.

---

## Sub-project 3 — Daily routine (scheduled cloud agent)

**What:** a Claude Code **scheduled cloud routine** that runs daily at 06:00 `Asia/Tokyo`
and whose task prompt is, in effect: *"You are in the `daily-brief` repo. Read
`brief-routine.md` and follow it exactly to generate and publish today's edition."*

**Why this mechanism (vs. alternatives):**
- It *is* "a Claude routine" — matches the stated goal.
- No machine left on (vs. local `launchd`/cron on the Mac).
- No API-key/secret plumbing (vs. a scheduled GitHub Action calling the Claude API).

**Schedule:** cron `0 6 * * *`, timezone `Asia/Tokyo`. `brief-routine.md` already computes
the *Tokyo* run date independent of the sandbox clock, so even though 06:00 JST = 21:00 UTC
the *previous* calendar day, the edition is dated correctly.

**Dependency to verify at setup (explicit, not assumed):** the cloud routine environment
must (a) have web **search + fetch**, and (b) be able to `git push` to this repo. The first
scheduled run is the real proof. **Fallback if either is unavailable:** a scheduled GitHub
Action that runs the generation against the Claude API — flagged to the user, not silently
substituted.

**Safety:** `brief-routine.md` Step 7 already guarantees thin/empty days do not overwrite a
good `index.html` and that nothing fabricated is ever published. No change needed.

**Done when:** the routine is registered, visible in the schedule list, and a manual
trigger (or the first 06:00 run) publishes an edition end-to-end.

---

## Sub-project 4 — distill_interests.jl (local taste refresh)

**What:** `scripts/distill_interests.jl` — a dependency-free Julia helper the user runs
locally to refresh the taste profile from GoodLinks.

**Conventions (per global CLAUDE.md):** Julia ≥ 1.10; no `##` comments; no `const`; no
`using Printf` (use `round` + interpolation); prefer `eachindex`, `something`.

**No external dependencies / no `Project.toml`:**
- Read SQLite by shelling out to the system `sqlite3` CLI with a tab-separated query against
  the read-only/immutable URI — avoids SQLite.jl and a Julia environment for a one-file
  helper.
- Hash with the `SHA` standard library. URL normalization with base regex.

**`url_hash` — must byte-for-byte match the Python in `brief-routine.md`:**
```
strip → drop leading scheme (^https?://, case-insensitive)
      → cut at first '#', then at first '?'
      → split host / path on first '/'
      → host: strip leading 'www.', lowercase
      → path: rstrip('/')
      → norm = host           (if path empty)
               host * "/" * path
      → sha256(norm) hex
```
The script includes **self-test assertions** on known `url → sha256` pairs (computed to
match the Python reference) and errors out if Julia and Python disagree. *Invariant:* the
two implementations are duplicated across languages and MUST stay in sync; both this spec
and `brief-routine.md` note this.

**Inputs → outputs:**
- Query non-deleted links (`deletedAt = 0`).
- **`goodlinks-hashes.txt`** ← sorted, unique `url_hash` of every non-deleted link's URL.
- **`interests.toml` `[exemplars]` block** ← regenerate ONLY the `titles = [...]` list
  between the TOML-comment markers `# <<exemplars:auto>>` / `# <<end:exemplars>>`; everything else
  in the file is preserved untouched. Selection: starred first, then most-recently-read by
  `readAt` desc; dedupe; clean whitespace; cap at ~8 titles; TOML-escape.
- Idempotent; safe to re-run; prints a count summary (links scanned, hashes written,
  exemplars chosen) using interpolation.

**README:** update the path reference from `research-assistant/scripts/distill_interests.jl`
to `scripts/distill_interests.jl`.

**Done when:** running `julia scripts/distill_interests.jl` rewrites both outputs correctly,
self-tests pass, and re-running is a no-op on unchanged data.

---

## Cross-cutting invariants

- **Hash parity:** `url_hash` exists in two languages (`brief-routine.md` Python, distill
  Julia). They must produce identical output; distill self-tests enforce it.
- **No fabrication:** every published/previewed item is actually fetched; no invented title,
  source, author, date, or blurb (`brief-routine.md` Step 3).
- **Privacy:** the repo stores topic preferences and URL *hashes* only — never a
  name-attached reading history. distill writes hashes, not URLs.

## Out of scope

- Redesigning the page layout / `brief.css`.
- Changing the scoring model or topic taxonomy beyond what distill refreshes.
- Multi-user / multiple taste profiles.

## Build order

1. Test run (validates `brief-routine.md`) →
2. Hosting (something to look at; DNS has external latency, start early) →
3. Schedule (depends on a trustworthy routine) →
4. distill_interests.jl (independent; supports long-term quality).

---

## Amendment — 2026-06-20: close the publish loop (auto-merge)

The spec flagged a dependency to verify at the first real run: *"the cloud routine
environment must ... be able to `git push` to this repo."* The first scheduled run
(2026-06-20) settled it: the routine **cannot** push to `main`. Generation worked end to
end (RSS sweep, fetch-verify, score, render were all correct), but instead of `git push`
landing on `main`, the cloud environment pushed to a `claude/*` branch and opened a PR
(`#1`). GitHub Pages deploys from `main` only, so the PR sat unmerged and the live page
never updated.

The spec's named fallback — rebuild generation as a scheduled GitHub Action against the
Claude API — is **not** taken, because it solves a problem we don't have: generation is
fine; only the final publish hop is missing.

**Decision:** keep the cloud routine exactly as-is and close the loop inside the repo with
a GitHub Actions workflow (`.github/workflows/auto-merge-brief.yml`) that auto-merges the
routine's daily PR:

- Trigger: `pull_request` (`opened`/`reopened`/`synchronize`), guarded by
  `startsWith(github.head_ref, 'claude/')` so only routine branches auto-merge.
- Merge with the built-in `GITHUB_TOKEN` (`gh pr merge --merge --delete-branch`); a short
  retry absorbs GitHub's asynchronous mergeability computation. No PAT, no secrets.
- After merge, explicitly `POST /repos/{repo}/pages/builds` — insurance against the
  "events from `GITHUB_TOKEN` don't re-trigger automation" caveat for the legacy Pages
  build.

**Prerequisite (one-time):** the repo's default workflow token permission was `read`; set
to `write` (`actions/permissions/workflow`, `default_workflow_permissions=write`) so the
token can merge.

**Trade-off (accepted):** fully hands-off means the routine's output publishes unreviewed.
Mitigated by the existing no-fabrication rule (Step 3) and thin/empty-day safety (Step 7);
the `claude/*` guard keeps the auto-merge scoped to routine PRs only.

**Follow-up (same day): the routine opens its PR as a _draft_.** The first auto-merge run
(PR #2) failed every retry with `GraphQL: Pull Request is still a draft` — the cloud
harness opens the routine's PR in draft state and does not mark it ready. Two fixes:
(1) the workflow now runs `gh pr ready` before merging; (2) `ready_for_review` was added to
the trigger types as a safety net (e.g. if a human marks it ready). `gh pr ready` performed
with `GITHUB_TOKEN` does not itself re-trigger the workflow, so there is no recursion.
