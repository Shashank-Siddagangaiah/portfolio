# LLM Wiki — Schema & Rules

This file governs how the LLM wiki agent operates inside this Obsidian vault.
Every session begins by reading this file. Every action follows the rules here.

---

## Vault Structure

```
Obsidian_vault/
├── CLAUDE.md              ← this file (schema & rules)
├── index.md               ← master catalog of all wiki pages
├── log.md                 ← append-only chronological history
│
├── work-data/             ← topic: data engineering, analytics, SQL, tooling
│   ├── _overview.md       ← evolving synthesis of the whole area
│   ├── concepts/          ← ideas, techniques, patterns, methodologies
│   ├── entities/          ← tools, platforms, companies, people
│   └── sources/           ← one summary page per ingested source
│
├── ai/                    ← topic: LLMs, ML, AI systems, agents
│   ├── _overview.md
│   ├── concepts/
│   ├── entities/
│   └── sources/
│
└── raw/                   ← immutable source files (never modify)
    ├── work-data/
    └── ai/
```

**Rules:**
- `raw/` is read-only. Never create or edit files there.
- The LLM owns everything outside `raw/`. The human owns `raw/`.
- Every wiki page must link to at least one other wiki page using `[[page-name]]`.
- Filenames: lowercase, hyphens only (e.g., `dbt-core.md`, `vector-search.md`).

---

## Page Frontmatter

Every wiki page (except `index.md` and `log.md`) must have this frontmatter:

```yaml
---
tags: [concept|entity|source|overview]
topic: work-data | ai
sources: N          # number of sources that informed this page
updated: YYYY-MM-DD
---
```

---

## Ingest Workflow (Mode: Supervised)

Triggered when the user says "ingest [file or topic]".

### Steps

1. **Read** the source from `raw/<topic>/`.
2. **Extract** key information:
   - Core claims / main argument
   - Entities mentioned (tools, people, companies, techniques)
   - Concepts introduced or developed
   - Anything that contradicts existing wiki pages
3. **Write** a source summary page at `<topic>/sources/<slug>.md`.
4. **Create or update** concept pages in `<topic>/concepts/`.
5. **Create or update** entity pages in `<topic>/entities/`.
6. **Update** `<topic>/_overview.md` if the source shifts the synthesis.
7. **Update** `index.md` — add new pages, update existing entries.
8. **Append** to `log.md` with format:
   ```
   ## [YYYY-MM-DD] ingest | <Source Title>
   ```
9. **Deliver change report** to the user (see format below).
10. **Wait** for user approval or revision requests before finalizing.

### Change Report Format

```
### Ingest Complete: <Source Title>

**Pages created:** N
- <topic>/sources/<slug>.md
- <topic>/concepts/<page>.md (new)

**Pages updated:** N
- <topic>/entities/<page>.md — added X, revised Y
- <topic>/_overview.md — updated synthesis

**Key extractions:**
- [bullet] Core claim or insight
- [bullet] Notable entity or technique

**Flags:**
- ⚠ Contradicts [[existing-page]] on claim X — needs review
- ℹ No existing page for concept Y — created stub
```

---

## Query Workflow

Triggered when the user asks a question about the wiki content.

### Steps

1. Read `index.md` to identify relevant pages.
2. Read the relevant pages.
3. Synthesize an answer with `[[wiki-links]]` as citations.
4. If the answer is substantial and reusable, offer to file it as a new wiki page.
5. If filed, update `index.md` and append to `log.md`:
   ```
   ## [YYYY-MM-DD] query | <Question Summary>
   ```

---

## Lint Workflow

Triggered when the user says "lint" or "health check".

Check for:
- Pages with no inbound links (orphans)
- Claims in older pages superseded by newer sources
- Concepts mentioned across multiple pages but lacking their own page
- Missing cross-references between related pages
- Data gaps that a web search could fill

Deliver a lint report listing issues by severity (high / medium / low).
Append to `log.md`:
```
## [YYYY-MM-DD] lint | health check
```

---

## Cross-Reference Rules

- When creating a source page, link to every concept and entity page it touches.
- When updating a concept page, link back to all sources that mention it.
- When updating `_overview.md`, link to the specific pages being synthesized.
- Never leave a page as an island.

---

## Naming Conventions

| Content type | Directory | Example filename |
|---|---|---|
| Source summary | `<topic>/sources/` | `attention-is-all-you-need.md` |
| Concept | `<topic>/concepts/` | `retrieval-augmented-generation.md` |
| Entity (tool/platform) | `<topic>/entities/` | `dbt-core.md` |
| Entity (person) | `<topic>/entities/` | `andrej-karpathy.md` |
| Entity (company) | `<topic>/entities/` | `databricks.md` |
| Topic overview | `<topic>/` | `_overview.md` |

---

## Session Start Protocol

At the start of every new session:
1. Read `index.md` to orient to current wiki state.
2. Read the last 10 entries of `log.md` to understand recent activity.
3. Confirm ready: "Wiki loaded. [N] pages across work-data and ai. Last activity: [date/action]."

---

## Constraints

- Never summarize a source without reading it in full.
- Never update a page without reading its current state first.
- Never delete wiki pages — mark as `status: deprecated` in frontmatter instead.
- Flag contradictions; do not silently overwrite old claims.
- Keep source summary pages factual. Keep concept/entity pages synthetic.
- `index.md` and `log.md` are always up to date before the change report is delivered.
