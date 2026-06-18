# Daily Brief — Routine Instructions

You are generating today's edition of the Daily Brief. You have this repo and web
access (search + fetch). Work entirely within this repo. Follow these steps exactly.

## 0. Inputs
- `interests.toml` — settings, topics (with `id`/`label`/`hint`), curiosities,
  regulars, watchlist (RSS feeds), exemplars.
- `goodlinks-hashes.txt` and `published-hashes.txt` — URL hashes already seen.
- `template.html` — the edition skeleton. `assets/brief.css` — styling.

Today's date is the run date in **Asia/Tokyo**. Use ISO `YYYY-MM-DD` for filenames
and a friendly `Weekday · D Month YYYY` for display.

## 1. Gather candidates
- **RSS sweep:** for each watchlist entry with a non-empty `feed`, fetch it and keep
  items published within `settings.recency_hours`.
- **Topical search:** for each `topic.hint` and each `curiosities` entry, run a
  recency-biased web search; collect promising results. This is where finds beyond the
  regular outlets come from.
- Also do a light search across the `regulars` for on-topic pieces from the same window.

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
or in an edition from the last `settings.dedup_window_days` days (`editions/`).

## 3. Verify + score (NO hallucination)
For each surviving candidate you intend to include, you MUST have actually fetched its
page. Confirm the URL resolves (no 404) and read enough to write an honest blurb.
**Never invent a title, source, author, date, or blurb.** If a fetch fails, drop it.

Score each item 0–1 for relevance to `topics` + `exemplars`. Separately note items
that are only partial matches, plus a few strong `curiosities`/generally-notable pieces.

## 4. Route
- score ≥ `settings.min_main_score` → **main column**, ordered by score (desc).
- partial match, or strong curiosity/notable → **sidebar list**.
- otherwise drop.
- Respect `settings.volume_target` as a soft cap on the main column. If few items
  clear the bar, the main column is simply shorter — **do not pad or fabricate.**
- Assign each item exactly one `topic.id` (its best fit) for jump anchors + counts.

## 5. Build the HTML
Start from `template.html`. Replace the four markers:

- `<!--DATE-->` → the friendly date (every occurrence).
- `<!--MAIN_ITEMS-->` → one block per main item, in order. For the FIRST item of each
  topic, add `id="topic-<topic.id>"` to its `<div class="item">` so jump links land:

  ```html
  <div class="item" id="topic-science-ai">
    <div class="h"><a href="ARTICLE_URL">HEADLINE</a></div>
    <div class="m">SOURCE · AUTHOR · 6h ago</div>
    <div class="b">One-sentence why-it-matters, from the fetched article.</div>
  </div>
  ```
  Omit ` · AUTHOR` when unknown. Use a relative age ("6h ago", "1d ago").

- `<!--SIDEBAR_ITEMS-->` → one block per sidebar item (no blurb):

  ```html
  <div class="si"><div class="h"><a href="ARTICLE_URL">HEADLINE</a></div>
    <div class="m">SOURCE</div></div>
  ```

- `<!--JUMP_LINKS-->` → one per topic that has ≥1 item, with its count, plus a
  "Yesterday's brief" link to the previous edition file:

  ```html
  <a href="#topic-science-ai">Science &amp; AI (7)</a>
  <a href="/editions/YYYY-MM-DD.html">Yesterday's brief →</a>
  ```

Escape `&`, `<`, `>` in all titles/blurbs (`&amp;`, `&lt;`, `&gt;`).

## 6. Publish
1. Write the filled HTML to `editions/<today>.html`.
2. Copy the same HTML to `index.html` (root).
3. Prepend a link to `archive.html` (create it from minimal HTML if it doesn't exist):
   `<a href="/editions/<today>.html">Weekday · D Month YYYY</a><br>`.
4. Append every published item's hash (main + sidebar) to `published-hashes.txt`.
5. Commit and push:
   ```bash
   git add -A && git commit -m "Daily Brief — <today>" && git push
   ```

## 7. Failure safety
If Step 1 yields zero usable items (e.g. all feeds error), do **not** overwrite
`index.html`. Leave yesterday's edition in place, write nothing, and stop. Never
publish fabricated content to fill a thin day.
