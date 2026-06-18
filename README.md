# Daily Brief

A personalized, Techmeme-style daily reading front page — generated each morning by a
scheduled Claude routine that discovers relevant science / progress / political-economy
articles (including beyond the usual sources) and ranks them against a taste profile.

- **Live page:** https://brief.garrek.org/
- **How it works:** see `brief-routine.md` (cloud routine) and
  `research-assistant/scripts/distill_interests.jl` (local taste refresh).
- **Edit your taste:** change `interests.toml` and commit.

This repo contains only topic preferences and URL *hashes* — never a name-attached
reading history.
