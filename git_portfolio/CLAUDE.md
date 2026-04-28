# git_portfolio

**What:** Static personal portfolio website for Shashank Siddagangaiah — Principal AI & Data Engineer.
**Live at:** `shashank-siddagangaiah.github.io/portfolio/`
**Deploy:** Push to `main` → GitHub Pages auto-publishes. No CI, no build step.

---

## File Map

| File | Purpose |
|---|---|
| `index.html` | Main portfolio page — single-page, all sections inline |
| `style.css` | All styling — CSS custom properties, Grid, Flexbox |
| `script.js` | All interactivity — Canvas particle network, counters, typed text, scroll animations |
| `ai-at-work-presentation.html` | Standalone slide deck: "AI in My Daily Workflow" — independent from portfolio |
| `favicon.svg` | Monogram 'SS' favicon — cyan-to-purple gradient, dark background |
| `profile_github.jpg` | Professional headshot — used in portfolio and GitHub profile |
| `profile-README.md` | GitHub profile README (shown on github.com/Shashank-Siddagangaiah) |
| `README.md` | Repo documentation |

---

## Tech Constraints

- **No framework, no build tool, no package.json.** Pure HTML5 / CSS3 / Vanilla JS.
- **No external CSS frameworks** (no Bootstrap, no Tailwind).
- To preview: open `index.html` directly in a browser — no server required.
- All fonts load from Google Fonts CDN (`Inter`, `Fira Code`).
- All JS is in `script.js` — no modules, no bundler.

---

## Design System

**Color palette (CSS custom properties in `style.css`):**

| Variable | Value | Usage |
|---|---|---|
| `--bg-primary` | `#0a0e17` | Page background |
| `--bg-secondary` | `#0d1421` | Card/section backgrounds |
| `--bg-card` | `#111827` | Card fill |
| `--accent-cyan` | `#00d4ff` | Primary accent, links, highlights |
| `--accent-purple` | `#7c3aed` | Secondary accent, gradient end |
| `--text-primary` | `#f1f5f9` | Body text |
| `--text-secondary` | `#94a3b8` | Muted text |

**Gradient pattern:** `linear-gradient(135deg, #00d4ff, #7c3aed)` — used on headings, buttons, favicon.

**Font stack:** `Inter` for UI text, `Fira Code` for code/tech tags.

---

## Section Map (`index.html`)

Sections in order, each with an `id` for nav anchoring:

| id | Content |
|---|---|
| `#hero` | Animated particle canvas, typed role text, animated counters (9yr, 50+ pipelines, etc.) |
| `#about` | Profile summary, contact chips (email, GitHub, LinkedIn) |
| `#skills` | 6 skill category cards with tech tags |
| `#experience` | Career timeline — PEMCO, Kemper, Select Rehab, Amazon |
| `#projects` | Featured project cards |
| `#education` | MS Business Analytics + AWS + Tableau certifications |
| `#contact` | Contact form / links |

Nav bar links map directly to these ids.

---

## JavaScript Architecture (`script.js`)

Key components — each is a self-contained function block:

| Component | What it does |
|---|---|
| Particle network | Canvas API — draws animated nodes and connecting edges in hero section |
| Typed text effect | Cycles through role strings with typewriter animation |
| Animated counters | IntersectionObserver triggers count-up on scroll into view |
| Scroll animations | IntersectionObserver adds `visible` class to fade-in elements |
| Nav scroll behavior | Adds `scrolled` class to navbar after threshold |

---

## ai-at-work-presentation.html

Standalone HTML slide deck — self-contained, no external dependencies. Topics covered:
- AI adoption statistics (McKinsey 2025)
- Claude Code CLI usage in data engineering
- Obsidian vault as persistent knowledge base
- Structured AI skills workflow

**Not linked from `index.html`** — exists as a separate shareable asset. Can be opened directly in a browser.

---

## How to Make Changes

- **Text/content changes:** Edit directly in `index.html` — find the section by `id`.
- **Style changes:** Edit `style.css` — use existing CSS custom properties, don't hardcode colors.
- **Animation/interactivity:** Edit `script.js` — each component is a labeled function block.
- **Adding a section:** Add the HTML block to `index.html`, add a nav link, add any CSS to `style.css`.
- **Never** add a framework or build tool — this is intentionally dependency-free.
