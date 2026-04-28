# Graph Report - .  (2026-04-26)

## Corpus Check
- 30 files · ~123,563 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 203 nodes · 304 edges · 15 communities detected
- Extraction: 83% EXTRACTED · 17% INFERRED · 1% AMBIGUOUS · INFERRED: 51 edges (avg confidence: 0.84)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Insurance Data Engineering Standards|Insurance Data Engineering Standards]]
- [[_COMMUNITY_AWM Database Schema|AWM Database Schema]]
- [[_COMMUNITY_Online Accounts Tableau Dashboard|Online Accounts Tableau Dashboard]]
- [[_COMMUNITY_Insurance Data Concepts|Insurance Data Concepts]]
- [[_COMMUNITY_Paperless Report Generator|Paperless Report Generator]]
- [[_COMMUNITY_AWM SQL Query Session|AWM SQL Query Session]]
- [[_COMMUNITY_AI Tools & Workflow|AI Tools & Workflow]]
- [[_COMMUNITY_Portfolio Brand Identity|Portfolio Brand Identity]]
- [[_COMMUNITY_Email Chain Data Issues|Email Chain Data Issues]]
- [[_COMMUNITY_Professional Profile Photo|Professional Profile Photo]]
- [[_COMMUNITY_Portfolio Content & Architecture|Portfolio Content & Architecture]]
- [[_COMMUNITY_NINANI Party Deduplication|NIN/ANI Party Deduplication]]
- [[_COMMUNITY_Person Identity|Person Identity]]
- [[_COMMUNITY_Policy Classification|Policy Classification]]
- [[_COMMUNITY_Workflow Context|Workflow Context]]

## God Nodes (most connected - your core abstractions)
1. `Self-Service Account Dashboard` - 16 edges
2. `AI Tools in Daily Data Engineering Workflow` - 13 edges
3. `Online Account Indicator` - 12 edges
4. `awm.dbo.online_party` - 12 edges
5. `Data Sources — EDW / AWM / BIM / Eloqua` - 11 edges
6. `AI in My Daily Workflow — Presentation` - 10 edges
7. `Online Accounts EDW Rewrite Session (Source)` - 10 edges
8. `awm.dbo.party` - 10 edges
9. `new_paper.sql / new_paper_final.sql Pipeline` - 9 edges
10. `awm.dbo.party_user_account_link` - 9 edges

## Surprising Connections (you probably didn't know these)
- `AI in My Daily Workflow — Presentation` --semantically_similar_to--> `AI Tools in Daily Data Engineering Workflow`  [INFERRED] [semantically similar]
  git_portfolio/ai-at-work-presentation.html → Obsidian_vault/ai/concepts/ai-tools-daily-workflow.md
- `Online Accounts Report — Project Schema (CLAUDE.md)` --conceptually_related_to--> `Tableau No-CTE Constraint (Nested Subquery Rule)`  [INFERRED]
  Online_accounts_report/CLAUDE.md → git_portfolio/ai-at-work-presentation.html
- `Online Accounts Report — Project Schema (CLAUDE.md)` --rationale_for--> `Online Accounts EDW Rewrite Project`  [INFERRED]
  Online_accounts_report/CLAUDE.md → Obsidian_vault/work-data/sources/online-accounts-edw-rewrite-session.md
- `AI in My Daily Workflow — Presentation` --references--> `Claude Code CLI`  [EXTRACTED]
  git_portfolio/ai-at-work-presentation.html → Obsidian_vault/ai/concepts/ai-tools-daily-workflow.md
- `AI in My Daily Workflow — Presentation` --references--> `ChatGPT`  [EXTRACTED]
  git_portfolio/ai-at-work-presentation.html → Obsidian_vault/ai/concepts/ai-tools-daily-workflow.md

## Hyperedges (group relationships)
- **Online Accounts EDW Rewrite — Full Validation Pipeline** — concept_union_all_four_sections, concept_party_id_same_as_link, concept_row_number_dedup, obsidian_edw_rewrite_session [EXTRACTED 0.97]
- **Insurance Data Source Trust Hierarchy (EDW/AWM/BIM/Eloqua)** — concept_edw, concept_awm, concept_bim, concept_eloqua [EXTRACTED 0.98]
- **AI-Assisted Data Engineering Governance Workflow** — concept_claude_code_cli, concept_structured_ai_skills, concept_validation_first, concept_obsidian_vault_knowledge_base [INFERRED 0.88]
- **CIF Data Quality — Superseded Records, Sort Key, and NULL Coercion** — issue_res_issue2_cif_superseded, issue_res_issue3_cif_dedup_sort, issue_res_issue4_null_coercion [INFERRED 0.90]
- **Email Resolution Chain: party_id_same_as_link → party_user_account_link → asp_user_account_detail** — issue_res_party_id_same_as_link, issue_res_party_user_account_link, issue_res_asp_user_account_detail [EXTRACTED 1.00]
- **BIM Fallback Fixes: Join Format, HOH Filter, and Column Name** — issue_res_issue7_bim_join_format, issue_res_issue9_bim_hoh_filter, issue_res_issue10_bim_col_name [INFERRED 0.85]

## Communities

### Community 0 - "Insurance Data Engineering Standards"
Cohesion: 0.09
Nodes (35): AWM (Operational System), BIM (Legacy Reporting), Date Join Logic (effective_from/to_date), Debugging Playbook, ROW_NUMBER Deduplication Pattern, EDW (Enterprise Data Warehouse), Eloqua (Marketing/Contact Data), Household Mapping Logic (+27 more)

### Community 1 - "AWM Database Schema"
Cohesion: 0.09
Nodes (29): awm.dbo.agent_party_link, Column: account_car_full_name, Column: account_creation_completed_car, Column: birth_date, Column: event_date, Column: event_type, Column: first_name, Column: gender_id (+21 more)

### Community 2 - "Online Accounts Tableau Dashboard"
Cohesion: 0.11
Nodes (25): Navigation Breadcrumb: Explore / Digital Services / Digital Dashboard / Online Accounts, Self-Service Account Dashboard, Community Agent Department, Customer Self-Service Department, Customer Service Department, Direct Sales Department, IT - Insurance Systems Department, Operations Department (+17 more)

### Community 3 - "Insurance Data Concepts"
Cohesion: 0.26
Nodes (20): AWM (Operational Data System), BIM (Legacy Reporting System), community_agent AWM Table (AgencyName / Supervisor Dimensions), DriverOnly ~43% Gap vs BIM — Accepted Architecture Difference, EDW (Enterprise Data Warehouse), Eloqua (Marketing / Online Account Flags), is_up_and_running_indicator = 255 (Active Online Account), party_id_same_as_link AWM→EDW Join Bridge (+12 more)

### Community 4 - "Paperless Report Generator"
Cohesion: 0.14
Nodes (14): add_code_block(), add_label(), add_table(), body(), cell_para(), h1(), h3(), issue_section() (+6 more)

### Community 5 - "AWM SQL Query Session"
Cohesion: 0.16
Nodes (18): SQL Query Session — AWM Database Exploration, agent_party_link Columns: party_id, party_anchor_id, insurance_support_type_id, legal_entity_type_id, party_status_id, statutory_title_id, marital_status_id, occupation_type_id, COINS Database Server (E: drive, SXLING instance), AWM Database Schema, user_event_detail Row: Activation Event (2025-11-28), user_event_detail Row: Creation Event (2023-04-27), party_anchor_id = 7746367 (Party Anchor Key), party_user_account_link_id = 293706 (Lookup Key) (+10 more)

### Community 6 - "AI Tools & Workflow"
Cohesion: 0.21
Nodes (17): ChatGPT, CIF Join Validation Pattern, Claude Code CLI, LLM Wiki Agent (Obsidian Vault Maintainer), McKinsey 2025 — 78% Enterprise AI Adoption Statistic, Obsidian Vault as Persistent Engineering Knowledge Base, Online Accounts EDW Rewrite Project, Paperless Report Pipeline (Multi-Source) (+9 more)

### Community 7 - "Portfolio Brand Identity"
Cohesion: 0.43
Nodes (7): Rounded Dark Background Rectangle (#0a0e17, rx=20), Cyan-to-Purple Linear Gradient (#00d4ff → #7c3aed), Portfolio Favicon Icon Design, Monogram Initials 'SS', Personal Brand Identity — Shashank S, Git Portfolio Website, Dark Mode Visual Style

### Community 8 - "Email Chain Data Issues"
Cohesion: 0.38
Nodes (7): asp_user_account_detail (AWM Table), Email Chain Resolution Pipeline, Issue 5 — Email Fan-Out from Partition Bug, Issue 6 — Known Bad Party Anchor IDs, Issue D2 — Orphaned Link Picked as rn=1, party_id_same_as_link (AWM Table), party_user_account_link (AWM Table)

### Community 10 - "Professional Profile Photo"
Cohesion: 0.73
Nodes (6): Business Formal Attire — Blue Suit and Tie, GitHub Portfolio Usage Context — Developer / Engineer Identity, GitHub Profile Photo (profile_github.jpg), Professional Impression — Confident, Polished, Corporate-ready, Shashank Siddagangaiah — Professional Profile Photo Subject, Outdoor Urban Park Setting — City Skyline Background

### Community 11 - "Portfolio Content & Architecture"
Cohesion: 0.5
Nodes (5): Agentic AI CLV Framework (PEMCO), Medallion Architecture (Bronze/Silver/Gold Lakehouse), Portfolio Website (index.html), GitHub Profile README, Portfolio README

### Community 12 - "NIN/ANI Party Deduplication"
Cohesion: 0.7
Nodes (5): ANI (Additional Named Insured) Party, Rationale: Email-Aware Dedup (Priority over NIN), Issue 8 — NIN Dedup Discarding ANI Email, Issue D3 — Grain Dedup Not Email-Aware (NIN Always Wins), NIN (Named Insured / Head of Household) Party

### Community 13 - "Person Identity"
Cohesion: 1.0
Nodes (1): Shashank Siddagangaiah

### Community 14 - "Policy Classification"
Cohesion: 1.0
Nodes (1): Policy Classification Logic (CASE by symbol)

### Community 15 - "Workflow Context"
Cohesion: 1.0
Nodes (1): Development Workflow (STRICT 7-step)

## Ambiguous Edges - Review These
- `SQL Standards and Patterns` → `Issue 2 — CIF Superseded Records Not Filtered`  [AMBIGUOUS]
  Paperless_report/CLAUDE.md · relation: semantically_similar_to
- `Dark Mode Visual Style` → `Git Portfolio Website`  [AMBIGUOUS]
  git_portfolio/favicon.svg · relation: rationale_for

## Knowledge Gaps
- **56 isolated node(s):** `Generate ISSUE_RESOLUTION.docx from ISSUE_RESOLUTION.md content. Run with: C:/Us`, `Set cell background colour via XML (python-docx has no native API).`, `Add a styled table with navy header row.`, `Add a shaded monospace paragraph for SQL snippets.`, `Add a bold coloured label followed by normal text on the same paragraph.` (+51 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Person Identity`** (1 nodes): `Shashank Siddagangaiah`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Policy Classification`** (1 nodes): `Policy Classification Logic (CASE by symbol)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Workflow Context`** (1 nodes): `Development Workflow (STRICT 7-step)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `SQL Standards and Patterns` and `Issue 2 — CIF Superseded Records Not Filtered`?**
  _Edge tagged AMBIGUOUS (relation: semantically_similar_to) - confidence is low._
- **What is the exact relationship between `Dark Mode Visual Style` and `Git Portfolio Website`?**
  _Edge tagged AMBIGUOUS (relation: rationale_for) - confidence is low._
- **Why does `ROW_NUMBER Deduplication Pattern` connect `Insurance Data Engineering Standards` to `Email Chain Data Issues`?**
  _High betweenness centrality (0.012) - this node is a cross-community bridge._
- **What connects `Generate ISSUE_RESOLUTION.docx from ISSUE_RESOLUTION.md content. Run with: C:/Us`, `Set cell background colour via XML (python-docx has no native API).`, `Add a styled table with navy header row.` to the rest of the system?**
  _56 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Insurance Data Engineering Standards` be split into smaller, more focused modules?**
  _Cohesion score 0.09 - nodes in this community are weakly interconnected._
- **Should `AWM Database Schema` be split into smaller, more focused modules?**
  _Cohesion score 0.09 - nodes in this community are weakly interconnected._
- **Should `Online Accounts Tableau Dashboard` be split into smaller, more focused modules?**
  _Cohesion score 0.11 - nodes in this community are weakly interconnected._