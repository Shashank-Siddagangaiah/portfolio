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
| `script.js` | Interactivity — Canvas particle network, counters, typed text, scroll animations |
| `ai-at-work-presentation.html` | Standalone slide deck — independent, open directly in browser |
| `favicon.svg` | Monogram 'SS' favicon |
| `profile_github.jpg` | Professional headshot |
| `profile-README.md` | GitHub profile README |

---

## Tech Constraints

- **No framework, no build tool, no package.json.** Pure HTML5 / CSS3 / Vanilla JS.
- No external CSS frameworks. Fonts: Google Fonts CDN (`Inter`, `Fira Code`).
- Preview: open `index.html` directly in browser — no server needed.
- All JS in `script.js` — no modules, no bundler.

---

## Section Map (`index.html`)

| id | Content |
|---|---|
| `#hero` | Particle canvas, typed role text, animated counters (9yr, 50+ pipelines, etc.) |
| `#about` | Profile summary, contact chips (email, GitHub, LinkedIn) |
| `#skills` | 6 skill category cards with tech tags |
| `#experience` | Career timeline — PEMCO, Kemper, Select Rehab, Amazon |
| `#projects` | Featured project cards |
| `#education` | MS Business Analytics + AWS + Tableau certs |
| `#contact` | Contact form / links |
