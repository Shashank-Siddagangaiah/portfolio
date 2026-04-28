---
tags: [overview]
topic: ai
sources: 2
updated: 2026-04-23
---

# AI & LLMs — Overview

This is the evolving synthesis of everything in the `ai` topic area.
It covers large language models, AI agents, ML systems, inference infrastructure,
prompting, retrieval, and the practical application of AI in engineering workflows.

Updated by the LLM wiki agent as new sources are ingested.

---

## Current State of Knowledge

Two sources ingested (2026-04-23). Knowledge base is focused on **practical AI tool adoption in data engineering workflows**, specifically Claude Code CLI and ChatGPT as daily engineering tools.

**Primary finding:** AI tools are integrated at every phase of the engineering process — design, build, debug, validate, deliver. Six structured workflow skills enforce engineering rigor rather than ad-hoc prompting.

**Governance:** All AI output is validated against production data. No sensitive customer data shared with external tools. Decisions documented in vault for auditability.

---

## Key Themes

### 1. Structured Workflows Over Ad-Hoc Prompting
AI value comes from repeatable, structured skills (Brainstorming, TDD, Debugging, Planning, Verification, Code Review) — not one-off prompts. See [[ai/concepts/ai-tools-daily-workflow]].

### 2. Validation-First Approach
Every AI-generated SQL is manually reviewed. Cross-source validation (EDW vs AWM vs BIM) confirms accuracy at every milestone. AI is a reasoning aid, not an authority.

### 3. Industry Context
78% of enterprises are deploying AI in at least one function (McKinsey 2025). Text-to-SQL tools are in production at Uber, Pinterest, and Intuit. AI fluency is now a baseline expectation in data engineering. See [[ai/sources/ai-adoption-research-2025]].

---

## Open Questions

- How do structured AI workflows scale to team-level adoption? What standards are needed?
- What is the right boundary between AI-assisted SQL and fully manual review?
- How can the Obsidian vault best serve as a shared team knowledge base for validated patterns?

---

## See Also

- [[ai/concepts/ai-tools-daily-workflow]] — Practical AI tool usage in daily data engineering
- [[ai/sources/ai-adoption-research-2025]] — Industry statistics and enterprise adoption trends
- [[work-data/_overview]] — Data engineering context these tools operate in
