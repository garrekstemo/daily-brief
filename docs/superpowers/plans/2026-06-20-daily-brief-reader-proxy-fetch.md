# Reader-proxy Fetch + Feeds-First Verification — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the cloud routine survive publisher HTTP 403s by fetching through a reader proxy and treating feed metadata as sufficient verification, so blocked article pages can't zero out the brief.

**Architecture:** Edit one agent-instruction file, `brief-routine.md`. Add a single shared "Fetching" rule (direct-first, then `r.jina.ai` proxy) near the top, then reference it from Step 1 (RSS sweep) and Step 3 (Verify). Step 3 also gains the feeds-as-verification distinction. No code, no dependencies, no account.

**Tech Stack:** Markdown instruction file for a Claude cloud routine; Jina Reader (`r.jina.ai`) as a no-key URL-prefix proxy.

> **Note on testing:** `brief-routine.md` is a prompt/instruction file consumed by the cloud agent — there is no automated test harness for it. Each edit is verified by re-reading the changed region for exact-text correctness and internal consistency. The real acceptance test is a manual cloud routine run (Task 5), which only the user can trigger and which is the only environment that reproduces the 403.

> **Working location:** All edits are in the `daily-brief` repo at `~/Developer/daily-brief`, on `main`. The spec lives at `docs/superpowers/specs/2026-06-20-daily-brief-reader-proxy-fetch-design.md`.

---

### Task 1: Add the shared "Fetching" rule near the top of the routine

**Files:**
- Modify: `brief-routine.md` (insert a new block after the intro paragraph, immediately before `## 0. Inputs`)

- [ ] **Step 1: Make the edit**

Find the end of the intro paragraph and the start of Step 0. The intro currently ends with "...Follow these steps exactly." and is immediately followed by `## 0. Inputs`. Insert the new `## Fetching` block between them.

`old_string`:
```
within this repo. Follow these steps exactly.

## 0. Inputs
```

`new_string`:
```
within this repo. Follow these steps exactly.

## Fetching (applies to every fetch below)
Claude's cloud egress IP is blocked (HTTP 403) by many publishers — Cloudflare-fronted
Substacks, Marginal Revolution, and others — for **both** their feed XML and their article
pages. Web *search* is not blocked; only fetch is. So whenever a step says to "fetch" a URL,
use this rule:

1. **Try the URL directly first.**
2. **If the direct fetch fails** (403, empty, or obviously blocked), **retry through the
   reader proxy:** fetch `https://r.jina.ai/<the-original-url>` instead. The proxy fetches
   the target from an unblocked IP and returns clean text. Example: to read
   `https://www.noahpinion.blog/feed`, fetch
   `https://r.jina.ai/https://www.noahpinion.blog/feed`.
3. **If both the direct fetch and the proxy fail,** treat it as a failed fetch and follow
   that step's normal skip/drop rule.

Only sources the direct fetch couldn't reach hit the proxy, so its keyless rate limit is
rarely a concern. **In your run summary, note which sources needed the proxy and which
failed both ways** — so a future change in the block is visible, not silent.

## 0. Inputs
```

- [ ] **Step 2: Verify the edit**

Re-read `brief-routine.md` lines 1–40. Confirm: (a) the new `## Fetching` block sits between the intro and `## 0. Inputs`; (b) the three numbered sub-rules are intact; (c) the `r.jina.ai` example URL is exactly `https://r.jina.ai/https://www.noahpinion.blog/feed`; (d) the run-summary visibility sentence is present.

- [ ] **Step 3: Commit**

```bash
cd ~/Developer/daily-brief
git add brief-routine.md
git commit -m "Add shared direct-first/proxy-fallback Fetching rule to routine"
```

---

### Task 2: Point the Step 1 RSS sweep at the Fetching rule

**Files:**
- Modify: `brief-routine.md` (the "RSS sweep" bullet under `## 1. Gather candidates`)

- [ ] **Step 1: Make the edit**

`old_string`:
```
- **RSS sweep:** for each watchlist entry with a non-empty `feed`, fetch it and keep
  items newer than the cutoff. A feed may error, 301-redirect, or have gone stale — skip
  any feed that fails to fetch or whose newest item predates the cutoff. That is normal,
  not a failure.
```

`new_string`:
```
- **RSS sweep:** for each watchlist entry with a non-empty `feed`, fetch it **using the
  Fetching rule above (direct first, then the `r.jina.ai` proxy)** and keep items newer
  than the cutoff. A feed may error, 301-redirect, or have gone stale — skip any feed that
  fails both direct and proxy, or whose newest item predates the cutoff. That is normal,
  not a failure. When you read a feed through the proxy, take each item's real link, title,
  and date from the feed entry; if the proxy mangles an item's URL, fall back to a search
  for that specific title rather than guessing the URL.
```

- [ ] **Step 2: Verify the edit**

Re-read the `## 1. Gather candidates` section. Confirm the RSS sweep bullet now references "the Fetching rule above," says "fails both direct and proxy," and contains the proxy-URL-fidelity fallback sentence. Confirm the "Topical search" and regulars bullets are unchanged.

- [ ] **Step 3: Commit**

```bash
cd ~/Developer/daily-brief
git add brief-routine.md
git commit -m "Route Step 1 RSS sweep through the Fetching rule"
```

---

### Task 3: Rewrite Step 3 — proxy fetch + feeds-as-verification

**Files:**
- Modify: `brief-routine.md` (the first paragraph of `## 3. Verify + score (NO hallucination)`)

- [ ] **Step 1: Make the edit**

Replace only the first paragraph (the verification rule). Leave the "Score each new item..." paragraph untouched.

`old_string`:
```
## 3. Verify + score (NO hallucination)
For each new candidate you intend to include, you MUST have actually fetched its page.
Confirm the URL resolves (no 404) and read enough to write an honest blurb.
**Never invent a title, source, author, date, or blurb.** If a fetch fails, drop it.
```

`new_string`:
```
## 3. Verify + score (NO hallucination)
Every item you include must trace to content you actually fetched — **never invent a
title, source, author, date, or blurb.** How you satisfy that depends on where the
candidate came from:

- **Feed-sourced items (from the Step 1 RSS sweep):** the feed entry you already fetched
  carries the publisher's own title, author, date, and summary/description. That **is** the
  verification — write the blurb from the feed's summary. You do **not** need a separate
  article-page fetch. (You may fetch the page via the Fetching rule for a richer blurb, but
  a blocked article page is fine here — the feed entry already verified the item.)
- **Search-discovered items (no feed behind them):** you MUST fetch the page — **using the
  Fetching rule above (direct first, then the `r.jina.ai` proxy)** — confirm the URL
  resolves (no 404), and read enough to write an honest blurb. If both the direct fetch and
  the proxy fail, **drop it.**
```

- [ ] **Step 2: Verify the edit**

Re-read the `## 3.` section. Confirm: (a) the no-hallucination clause is preserved up front; (b) there are two bullets — feed-sourced (no separate fetch required) and search-discovered (fetch via the rule, drop if both fail); (c) the "Score each new item 0–1..." paragraph still follows unchanged.

- [ ] **Step 3: Commit**

```bash
cd ~/Developer/daily-brief
git add brief-routine.md
git commit -m "Step 3: feeds count as verification; search finds use the proxy"
```

---

### Task 4: Whole-file consistency read

**Files:**
- Read only: `brief-routine.md`

- [ ] **Step 1: Read the full file end-to-end**

Read all of `brief-routine.md`. Check:
- The `## Fetching` block is the single definition of the fetch rule (DRY) and both Step 1 and Step 3 reference it by name rather than redefining it.
- No remaining instruction says "if a fetch fails, drop it" unconditionally in a way that contradicts the new feeds-as-verification rule.
- Step 7's failure-safety rules (quiet days, empty rolling set, wholesale Step 1 failure) are untouched and still consistent.
- Section numbering 0–7 is intact and the new `## Fetching` block is unnumbered (so it doesn't disturb the count).

- [ ] **Step 2: Fix any inconsistency inline**

If anything contradicts the design, correct it with a targeted edit and commit:
```bash
cd ~/Developer/daily-brief
git add brief-routine.md
git commit -m "Tidy routine wording for fetch-rule consistency"
```
If nothing needs fixing, skip this step.

---

### Task 5: Validate with a manual cloud run (acceptance test)

**Files:** none — this is the only test that reproduces the cloud 403.

> The user triggers this; the agent cannot. Do not claim the fix works until this passes.

- [ ] **Step 1: Push the routine changes so the cloud run uses them**

```bash
cd ~/Developer/daily-brief
git push
```
(Confirm with the user before pushing — pushing to `main` is the user's call.)

- [ ] **Step 2: User triggers one manual routine run**

Ask the user to start a routine run (the same way they tested the auto-merge fix).

- [ ] **Step 3: Confirm fresh feed-sourced items appeared**

After the run, inspect the result:
```bash
cd ~/Developer/daily-brief
git log --oneline -3
```
Open the new `editions/<date>.html` (or `index.html`) and confirm it contains **new** items dated within `recency_hours`, i.e. the proxy path actually pulled content — not just a carry-forward.

- [ ] **Step 4: Read the run's fallback notes**

Check the run summary/output for the proxy-fallback notes added in Task 1: which sources needed the proxy, which failed both ways. Confirm the proxy was actually exercised and that failures (if any) are the expected paywalled/blocked regulars, not the whole watchlist.

- [ ] **Step 5: Record the outcome**

If fresh items published: the fix is validated end-to-end — note it and stop. If the watchlist still came back empty: the proxy itself may be blocked from the cloud egress; capture the run's fallback notes and revisit (the spec's "Known risks" lists the RSS-aggregator fallback).

---

## Self-Review

**Spec coverage:**
- Change A (reader proxy, direct-first) → Task 1 (rule) + Tasks 2–3 (references). ✓
- Change B (feeds-first verification) → Task 3. ✓
- Failure handling / graceful degradation → preserved by referencing existing skip/drop rules; verified in Task 4. ✓
- Run-output visibility of fallbacks → Task 1 rule text + Task 5 Step 4. ✓
- Validation caveat (only a cloud run reproduces the 403) → Task 5. ✓
- Known risk: proxy feed-URL fidelity → Task 2 fallback sentence. ✓
- Files touched: `brief-routine.md` only → all tasks. ✓

**Placeholder scan:** No TBD/TODO; every edit shows exact `old_string`/`new_string`. ✓

**Consistency:** The proxy is named `r.jina.ai` and the rule is "the Fetching rule above" in every task. Step 1 and Step 3 both reference the single rule defined in Task 1 (DRY). ✓
