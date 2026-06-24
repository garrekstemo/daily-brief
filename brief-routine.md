# Daily Brief — Routine Instructions

You are updating the Daily Brief. It is a **rolling front page**, not a fresh daily
snapshot: each run *adds* the day's new finds to the top and lets older items *age off the
bottom* after `settings.display_window_days`. A quiet morning means fewer new items pushed
in — never a blank page. You have this repo and web access (search + fetch). Work entirely
within this repo. Follow these steps exactly.

## Fetching (applies to every fetch below)
Claude's cloud egress IP is blocked (HTTP 403) by many publishers — Cloudflare-fronted
Substacks, Marginal Revolution, and others — for **both** their feed XML and their article
pages. Web *search* is not blocked; only fetch is. So whenever a step says to "fetch" a URL,
use this rule:

1. **Try the URL directly first.**
2. **If the direct fetch fails** (403, empty, or obviously blocked), **retry the direct
   fetch with a real browser User-Agent via `curl`.** Many publishers — notably FT, The
   Economist, NYT, and Foreign Affairs — 403 the default fetch agent but serve a normal
   browser UA, returning the real feed XML:
   ```
   curl -sSL --max-time 25 \
     -A 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17 Safari/605.1.15' \
     '<the-original-url>'
   ```
3. **If the browser-UA fetch also fails, retry through the reader proxy:** fetch
   `https://r.jina.ai/<the-original-url>` instead. The proxy fetches the target from an
   unblocked IP and returns clean text. Example: to read `https://www.noahpinion.blog/feed`,
   fetch `https://r.jina.ai/https://www.noahpinion.blog/feed`. **Caveat: the proxy mangles
   some feeds — notably FT, whose entries come back as title-less `ft.com/content/<uuid>`
   links. If the proxy output has no usable titles/links, treat the fetch as failed rather
   than guessing URLs** (so FT in practice must be reached by the browser-UA fetch in step 2).
4. **If direct, browser-UA, and proxy all fail,** treat it as a failed fetch and follow
   that step's normal skip/drop rule.

Prefer the earliest method that works; fall onward only when one fails. **In your run
summary, note which sources needed the browser-UA fetch, which needed the proxy, and which
failed all ways** — so a future change in the block is visible, not silent.

## 0. Inputs
- `interests.toml` — settings, topics (with `id`/`label`/`hint`), curiosities,
  regulars (core outlets, each with an RSS `feed`), watchlist (RSS feeds), exemplars.
- `current.json` — **the rolling page state**: the items currently displayed. Each item
  has `url`, `hash`, `title`, `source`, `author`, `date` (article publish date, drives the
  displayed age), `topic`, `column` (`main`/`sidebar`), `score`, `added` (the run date it
  first appeared, drives aging), and `blurb` (main items only). This is the source of truth
  for what the page shows — do not hand-edit; the routine rewrites it each run.
- `goodlinks-hashes.txt` and `published-hashes.txt` — URL hashes already seen.
- `template.html` — the edition skeleton. `assets/brief.css` — styling.

Today's date is the run date in **Asia/Tokyo**. Use ISO `YYYY-MM-DD` for filenames
and a friendly `Weekday · D Month YYYY` for display.

## 1. Gather candidates
The recency cutoff is `now − settings.recency_hours`, where `now` is the current instant
in **Asia/Tokyo**; compare it against each item's publish time (normalize the feed's
pubDate to UTC first) and keep items at or after the cutoff.

- **RSS sweep:** for each `regular` and each `watchlist` entry with a non-empty `feed`,
  fetch it **using the Fetching rule above (direct first, then the `r.jina.ai` proxy)** and
  keep items newer than the cutoff. A feed may error, 301-redirect, or have gone stale — skip any feed that
  fails both direct and proxy, or whose newest item predates the cutoff. That is normal,
  not a failure. When you read a feed through the proxy, take each item's real link, title,
  and date from the feed entry; if the proxy mangles an item's URL, fall back to a search
  for that specific title rather than guessing the URL.
- **Topical search:** for each `topic.hint` and each `curiosities` entry, run a
  recency-biased web search; collect promising results. This is where finds beyond the
  regular outlets come from.
- Regulars are now swept by their `feed` in the RSS sweep above — that is their primary
  path, and it sidesteps the paywall/crawler block. Items reached this way are verified by
  the feed entry (Step 3), so they need no article fetch even when the page is paywalled.
  As a *supplement*, you may run a light topical search across the `regulars` for on-topic
  pieces missing from a feed; several are paywalled or block crawlers (FT, Economist, NYT,
  New Yorker, Atlantic), so if a search fetch fails, skip it — a thin supplemental pass is
  expected, not an error.

## 2. De-duplicate
Compute each candidate's hash with this exact algorithm (must match the Julia distill):

```python
import hashlib, re
def url_hash(u):
    s = u.strip()
    s = re.sub(r'^https?://', '', s, flags=re.I)
    s = s.split('#', 1)[0].split('?', 1)[0]
    host, _, path = s.partition('/')
    host = re.sub(r'^www\.', '', host.lower())
    path = path.rstrip('/')
    norm = host if not path else host + '/' + path
    return hashlib.sha256(norm.encode()).hexdigest()
```

Drop any candidate whose hash is in `goodlinks-hashes.txt`, in `published-hashes.txt`,
already present in `current.json` (it's still on the page), or in an edition from the last
`settings.dedup_window_days` days (`editions/`). What survives is the **new** items only.

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

Score each new item 0–1 for relevance to `topics` + `exemplars`. (Carried-forward items
keep the score already stored in `current.json` — do not re-score them.)

## 4. Merge into the rolling page
Build the new page state from `current.json` plus today's new items:

1. **Load** `current.json` (its `items` list). If the file is missing, start from an empty
   list.
2. **Age out:** drop every existing item whose age exceeds the window —
   `today − item.added > settings.display_window_days` days. (Aged-out items stay in
   `published-hashes.txt`, so they never come back.)
3. **Add new:** for each new item from Step 3, build a record:
   - `column` = `main` if `score ≥ settings.min_main_score`, else `sidebar`.
   - `topic` = its single best-fit `topic.id`.
   - `added` = today; `date` = the article's publish date; `blurb` = the honest one-liner
     (main items only); plus `url`/`hash`/`title`/`source`/`author`/`score`.
   - Append it to the list.
4. **Apply soft caps.** If `main` items exceed `settings.volume_target`, or `sidebar` items
   exceed `settings.sidebar_target`, drop the lowest-scoring items in that column until
   within the cap (break ties by oldest `added`). Dropped-by-cap items also stay in
   `published-hashes.txt` and do not return. **Never pad or fabricate to reach a cap** —
   the caps are ceilings, not quotas.

The resulting list is the new rolling set, used by Steps 5–6.

## 5. Build the HTML
Start from `template.html`. Replace the four markers, drawing from the **rolling set**:

- `<!--DATE-->` → the friendly date (every occurrence).
- `<!--MAIN_ITEMS-->` → the `main`-column items, **grouped by topic** in `interests.toml`
  topic order; within each topic, ordered by `added` desc then `score` desc (so the
  most-recently-added items rise to the top of their section, and score breaks ties within
  the same run). The FIRST item of each topic
  group gets `id="topic-<topic.id>"` so jump links land:

  ```html
  <div class="item" id="topic-science-ai">
    <div class="h"><a href="ARTICLE_URL">HEADLINE</a></div>
    <div class="m">SOURCE · AUTHOR · 6h ago</div>
    <div class="b">One-sentence why-it-matters, from the fetched article or feed summary.</div>
  </div>
  ```
  Omit ` · AUTHOR` when unknown. Compute the relative age ("6h ago", "1d ago", "5d ago")
  from the item's `date` against `now` (Asia/Tokyo) — so carried-forward items age each day.

- `<!--SIDEBAR_ITEMS-->` → the `sidebar` items, newest first (by `added` desc, then `score`
  desc), no blurb:

  ```html
  <div class="si"><div class="h"><a href="ARTICLE_URL">HEADLINE</a></div>
    <div class="m">SOURCE</div></div>
  ```

- `<!--JUMP_LINKS-->` → jump links cover **main-column items only**. Emit one link per
  topic that has ≥1 *main-column* item, showing that topic's main-column count and pointing
  at its `id="topic-<id>"` anchor. Sidebar items still carry a `topic.id` for bookkeeping
  but get no anchor and are not counted. After the topic links, add a "previous edition"
  link:

  ```html
  <a href="#topic-science-ai">Science &amp; AI (7)</a>
  <a href="/editions/<prev>.html">Previous brief →</a>
  ```

  Compute `<prev>` from the filesystem, not by date arithmetic (thin/zero days are skipped,
  so "today − 1 day" is often wrong): it is the greatest `editions/YYYY-MM-DD.html` whose
  date is **strictly before today**. If no such file exists (the first real edition), omit
  the "Previous brief" link entirely.

  The template already hard-codes `<a href="/archive.html">Archive →</a>` immediately after
  this marker — insert the JUMP_LINKS content *before* it; never duplicate or remove it.

Escape `&`, `<`, `>` in all titles/blurbs (`&amp;`, `&lt;`, `&gt;`).

## 6. Publish
1. Write the filled HTML to `editions/<today>.html`.
2. Copy the same HTML to `index.html` (root).
3. Prepend a link to `archive.html` (create it from minimal HTML if it doesn't exist):
   `<a href="/editions/<today>.html">Weekday · D Month YYYY</a><br>`.
4. **Write the new rolling set to `current.json`** (set `updated` to today). This is what
   the next run carries forward.
5. Append each **newly added** item's hash (the ones from Step 3, main + sidebar) to
   `published-hashes.txt`. Do not re-append carried-forward items — they are already there.
6. Commit and push:
   ```bash
   git add -A && git commit -m "Daily Brief — <today>" && git push
   ```

## 7. Quiet days & failure safety
- A day with **zero new items** is normal. Still run Step 4's age-out and re-render, so
  stale items fall off and the dates stay current — the page just carries forward with
  fewer (or no) additions. This is the whole point of the rolling model: never a blank
  main column on a slow news day.
- Only if the rolling set is **completely empty** after the merge (a true cold start with
  nothing to show) do you skip publishing: leave the existing `index.html` in place, write
  nothing, and stop.
- If Step 1 wholly fails (e.g. every feed errors and search is unreachable), do **not**
  rewrite the page from a broken read — leave the previous edition in place and stop.
- Never publish fabricated content to fill a thin day.
