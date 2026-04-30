---
# LLM Wiki — Schema & Rules

## Vault Structure

```
Obsidian_vault/
├── CLAUDE.md              ← this file
├── index.md               ← master catalog of all wiki pages
├── log.md                 ← append-only chronological history
├── work-data/             ← data engineering, analytics, SQL, tooling
│   ├── _overview.md, concepts/, entities/, sources/
├── ai/                    ← LLMs, ML, AI systems, agents
│   ├── _overview.md, concepts/, entities/, sources/
└── raw/                   ← immutable source files (human-owned, never modify)
```

**Rules:** `raw/` is read-only. Every page must link to at least one other via `[[page-name]]`. Filenames: lowercase, hyphens only. Never delete — set `status: deprecated` in frontmatter.

---

## Page Frontmatter

```yaml
---
tags: [concept|entity|source|overview]
topic: work-data | ai
sources: N
updated: YYYY-MM-DD
---
```

---

## Workflows

**Ingest** (trigger: `ingest <file>`): Read source from `raw/` → write `<topic>/sources/<slug>.md` → create/update concept and entity pages → update `_overview.md` if synthesis shifts → update `index.md` → append `log.md` → deliver change report listing pages created/updated + key extractions + contradictions flagged → wait for approval before finalizing.

**Query** (trigger: user question about vault): Read `index.md` → read relevant pages → answer with `[[wiki-links]]` as citations → offer to file as new page if reusable → update `index.md` + append `log.md` if filed.

**Lint** (trigger: `lint` or `health check`): Check for orphans, superseded claims, missing concept pages, broken cross-refs, data gaps → report by severity (high/medium/low) → append `log.md`.

---

## Constraints

- Never summarize a source without reading it in full.
- Never update a page without reading its current state first.
- Flag contradictions; do not silently overwrite old claims.
- `index.md` and `log.md` always up to date before delivering any report.
- Source pages: factual. Concept/entity pages: synthetic.
