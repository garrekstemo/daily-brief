# Daily Brief — Reader-proxy fetch + feeds-first verification

**Date:** 2026-06-20
**Status:** Approved design, pending implementation
**Author:** Garrek Stemo (with Claude)

## Problem

The scheduled cloud routine could not pull any websites. `WebFetch` returned
**HTTP 403 Forbidden** for every publisher URL it tried — Marginal Revolution,
the watchlist Substacks (Construction Physics, Statecraft, Slow Boring, Astral
Codex Ten, Noahpinion), Quanta, Nautilus, and others. The block hit on two
fronts at once:

1. **Step 1 RSS sweep** — the feed XML fetches were 403'd.
2. **Step 3 verify** — the article-page fetches were 403'd.

Because Step 3 requires a successful article-page fetch before any item may be
included (the anti-hallucination rule), and every fetch failed, **every
candidate was dropped** and the page carried forward with no new items.

### Root cause

The 403s are **datacenter-IP blocking**, not a routine bug. Most of these
publishers sit behind Cloudflare and reject requests from cloud/datacenter
egress IPs. The watchlist comment in `interests.toml` ("every non-empty feed
returned HTTP 200 when this file was written") reflects testing from a
residential IP; the cloud routine runs from a blocked one.

This was confirmed during design: from a residential IP both the raw feed
(`https://marginalrevolution.com/feed`) and the proxied feed fetched fine, so
the block is specific to the cloud routine's egress IP and **cannot be
reproduced from a local session**.

Note: **WebSearch is not blocked** — only fetch. So the routine can still
*discover* candidates (Step 1 topical search, Step 1 regulars pass); it just
cannot *verify* them.

## Strategy

Stop fetching publishers directly from Claude's blocked IP. Two coordinated
changes, both in `brief-routine.md` (no code, no new dependencies, no account):

- **A — Reader proxy:** route fetches through a service whose IP is not
  blocked, so the actual publisher fetch happens from an unblocked address.
- **B — Feeds-first verification:** treat the feed entry itself as sufficient
  verification, so a blocked *article page* can no longer zero out the brief —
  while keeping the no-hallucination rule fully intact.

## Change A — route fetches through the reader proxy

Both fetch points (Step 1 RSS sweep, Step 3 verify) get one rule:

> **Fetch direct first; on 403 / empty / blocked, retry through the reader
> proxy** by requesting `https://r.jina.ai/<original-url>`. The proxy fetches
> the target from an unblocked IP and returns clean text/markdown.

Rationale for **direct-first** (rather than always-proxy):

- If the block ever lifts, or for any source the proxy can't reach, nothing
  breaks — direct still works.
- It conserves the proxy's keyless rate budget: only blocked sources hit it.

Search is unchanged — it already works.

### Reader proxy: Jina `r.jina.ai`

- Usage is a URL prefix: `https://r.jina.ai/https://site/path`. No SDK.
- **Keyless tier.** `WebFetch` cannot send an `Authorization` header, so a Jina
  API key can't be applied; we stay on the keyless tier. Rate limits are kept
  manageable by direct-first (only blocked sources proxy) and feeds-first
  (≈10 feed pulls + a few search verifications per day, not dozens of article
  fetches).
- Probe (2026-06-20, residential IP): `r.jina.ai/<MR feed>` returned a clean
  list of real titles and ISO dates — the metadata the routine needs.

## Change B — feeds become the primary verifiable source

Today Step 3 demands a full **article-page** fetch for *every* item. That single
requirement is what emptied the brief when article fetches 403'd. New rule:

- **Feed-sourced items:** the feed entry fetched in Step 1 already carries the
  publisher's own title, author, date, and summary/description. That **counts
  as verification** — write the blurb from the feed's own summary. No separate
  article-page fetch required. (Still the publisher's real words — nothing is
  invented; the anti-hallucination rule holds.)
- **Search-discovered items** (no feed behind them): still require a successful
  fetch before inclusion — now via the proxy (direct-first, proxy-fallback). If
  even the proxy fetch fails, **drop the item** (unchanged behavior).

Net effect: on a normal day the brief builds almost entirely from feeds the
proxy can reliably pull, and article-page blocking can no longer zero out the
page.

## Failure handling & graceful degradation

- Per-source failures degrade exactly as today: a feed that fails to fetch
  (direct **and** proxy) is skipped (Step 1); a search item that fails to fetch
  (direct **and** proxy) is dropped (Step 3).
- Step 7's safety rules are untouched: quiet days carry forward, a fully empty
  rolling set skips publishing, a wholesale Step 1 failure leaves the previous
  edition in place. Never publish fabricated content.
- The routine should make its fallback **visible** in run output — note when a
  fetch fell back to the proxy and when both direct and proxy failed — so a
  future block change is diagnosable rather than silent.

## Validation

The cloud 403 **cannot be reproduced from a local session** (the local IP isn't
blocked). The only real proof is a cloud run. Therefore the implementation is
validated by:

1. A manual routine run triggered by the user.
2. Confirming from the resulting commit / `editions/<date>.html` that fresh
   feed-sourced items appeared (i.e. the proxy path actually pulled content).
3. Reviewing the run's fallback notes to see which sources needed the proxy.

## Files touched

- **`brief-routine.md`** only:
  - **Step 1 (RSS sweep):** add the direct-first / proxy-fallback fetch rule for
    each watchlist feed.
  - **Step 3 (Verify + score):** add the proxy-fallback rule for article fetches
    **and** the feed-as-verification rule (feed-sourced items need no separate
    article fetch; search-discovered items still require a successful fetch).
  - Add a short note instructing the routine to surface proxy fallbacks in its
    run output.

No code, no new plugins, no account, no secrets.

## Known risks

- **Feed fidelity through the proxy.** `r.jina.ai` on a feed URL returns parsed
  markdown rather than raw XML. The probe showed clean titles/dates/links, but
  item-**URL** fidelity matters for the Step 2 hash/dedup. The routine should
  treat proxied-feed item URLs carefully when deduping, and prefer the direct
  feed's URLs when the direct fetch succeeds.
- **Proxy availability / rate limits.** If `r.jina.ai` is down or rate-limits,
  blocked sources are skipped that day and the page carries forward — same
  graceful degradation as a normal thin day, not a hard failure.
- **Block surface may shift.** If publishers later block the proxy's IPs too,
  the fallback notes in run output will reveal it, and we revisit (e.g. an RSS
  aggregator API). Out of scope for now.
