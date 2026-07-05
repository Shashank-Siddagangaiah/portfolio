# EvoFit — Development Status & Feature Roadmap
Last updated: 2026-06-29

> **SCOPE: Gym / Workout module only.**
> For the Sport Tracking module (SportLogPage, cricket animations, racket sports, social tagging, squad system) →
> read `EVOFIT_SPORT_PLAN.md` instead. Do NOT duplicate that context here.

---

## SHIPPED ✓

These are done and live in the codebase.

- [x] **Plans UI full refactor** — split 1736-line file into 13 components; month-bar + week-strip + DayCard layout
- [x] **PlanDetailView** — month/week navigation, auto-scroll-to-today, Jump-to-today button, copy-week selector
- [x] **LoggedWorkoutCard** — expandable workout history on PlanDetailView; main exercises tappable → ExerciseInfoPanel
- [x] **Workout complete summary screen** — total volume, exercise count, points earned, rest-day cap display
- [x] **DayCard double-award deduplication** — DB unique index prevents double points on page refresh
- [x] **PlanListView filter chips** — All / Active / Paused filter + collapsible Archived section at bottom
- [x] **Interval timer** — HIIT / Tabata / EMOM / AMRAP presets, circular SVG progress, stopwatch mode
- [x] **Equipment SVG icons** — real SVG files per equipment type in gear setup
- [x] **MuscleMapPicker** — interactive muscle group selector component (front/back body silhouette)
- [x] **Points Spent display** — stat tile on ProfilePage
- [x] **"Edit gear setup →" link** — in LogWorkoutPage Step 4, links to `/gear`

---

## LOG PAGE REDESIGN — Confirmed Decisions (2026-06-29)

### Compressed Single-Screen Setup (replaces 6-step wizard)

The 6-step wizard (type → muscles → duration → equipment → plan → link) is replaced with:
- **Screen 1: Setup card** (single screen, all inputs visible at once)
- **Screen 2: Generated plan** (existing plan step, unchanged)

Setup card layout:
1. Workout type — icon tabs: Strength / Cardio / Yoga / Other (horizontal row)
2. Target area chips + muscle map (dual-sync, see below)
3. Duration — 3 chips pre-selected to 45 min: [30] [● 45] [60+]
4. Equipment — "Using your saved gear ⚙" row (inline override, not a step)
5. "Generate Workout →" button

**Area chips ↔ Muscle map (confirmed 2026-06-29):**
- Area chips at top: Full Body / Upper / Lower / Push / Pull / Legs / Core
- Selecting an area chip → auto-highlights the corresponding muscles on the map below
- Tapping muscles on the map → updates the corresponding area chip selection
- Both stay in sync. User can use either input method — whichever they prefer.
- The full anatomical muscle map is always visible below the chips (not behind an "Advanced" toggle)

**Equipment (confirmed 2026-06-29):**
- NOT a separate step. Auto-uses saved gear profile silently.
- "Using your saved gear ⚙" row on setup card. Tap ⚙ → inline equipment toggle expands
- Most sessions: user never touches it. Zero friction.
- Edge case (different gym, forgot equipment): one tap to expand and deselect items

**Duration (confirmed 2026-06-29):**
- NOT a separate step. Three chips on setup card, pre-selected to 45 min.
- One tap to change. Visible but not a blocker.

### UX Improvements — Confirmed for Implementation

| Decision | Confirmed |
|---|---|
| "Repeat last workout" shortcut on home tile and log entry | ✓ |
| Auto rest timer starts after each set ✓ tap | ✓ |
| Exercise images (free-exercise-db two-frame) on plan step and set rows | ✓ |
| PR detection on set completion — live, on the row | ✓ |
| "Start Today's Workout" CTA directly on TodaysPlanDayTile | ✓ |
| Back-navigation confirmation dialog on plan/setup step | ✓ |
| Structured cardio fields (not text concatenation into notes) | ✓ |
| Per-plan clone pending state (not shared across all cards) | ✓ |
| AI regenerate rate limit: max 3 per session | ✓ |
| Move Themes tab out of Plans page top nav | ✓ |
| PR callout on success screen ("NEW PR: Bench Press 82.5 kg") | ✓ |

### All Remaining Decisions — Confirmed (2026-06-29)

| Decision | Answer |
|---|---|
| Plan linking flow | After the workout is done. Success screen has "Add to a plan →" button. Not in the setup card or plan screen. Main flow stays clean. |
| Set logging mode | Inline — same screen. Set rows expand under each exercise on the plan/generated screen. Scroll to navigate exercises. No separate focus screen. |
| Plans page 3rd tab (replacing Themes) | Progress — exercise weight over time, monthly volume, muscle group frequency. Themes moves to Settings. |
| Supplement edit location | "Manage →" link next to the supplements section header on the dashboard. Opens a dedicated supplement management view (add / edit / delete / reminders). Discoverable because it's adjacent to where users see supplements daily. |
| Two-path generated plan screen | After the setup card generates a plan, the plan screen shows two CTAs at the bottom: **"Save to Plan →"** and **"Work Out Now →"**. Save to Plan creates a plan_day record (pending, not complete). Work Out Now goes directly into the per-set logging flow without saving. Both paths are available on the same screen; user chooses based on intent. |
| Per-set logging approach | **Pre-fill + one-tap ✓**. Each exercise shows set rows pre-filled with target reps + weight from the plan (or last session if available). Tap ✓ on a row to log that set. Weight/reps are editable inline. Auto rest timer starts after each ✓. No input required — just confirm. For new exercises with no history: sensible defaults (e.g., 3 × 10 × bodyweight or a light starter weight). |

---

## CURRENT SPRINT QUEUE (ordered — do these next, one at a time)

### 1. Warm-up / Cooldown tappable [DONE ✓]
- [x] In `PlanDetailView.tsx` `LoggedWorkoutCard`, change `tappable: false` → `tappable: true` for warmup and cooldown sections
- [x] Verify ExerciseInfoPanel shows correctly for stretch/warmup exercise names

### 2. Log-to-Plan Integration — connect workout logging to plan day engine [NEXT UP — start here]
Goal: logging a workout can either stay a quick one-off (unchanged) or create a real,
independently-editable plan day that flows through the existing `useMarkDayComplete`
engine — no parallel pending/complete/points system.

**A. Data layer**
- [ ] Add `is_late_grace` (bool) + `completed_late_for_date` (date, nullable) to the completions table — flags a grace completion so points are skipped and the monthly cap can be queried
- [ ] Plan extension just updates `plans.end_date` — no new table; extended months get empty (or no) `plan_days` rows until filled
- [ ] No new "status" column for pending/missed — both stay derived client-side from `(plan_day.date, exercises present, completion row exists)`

**B. Hooks**
- [ ] Extend `useMarkDayComplete` to accept `isLateGrace?: boolean` — when true: skip the 50/5/25-point awards, still update streak, reject (no-op + UI message) if monthly grace count is already at cap (2–3/month)
- [ ] New `useReplicatePlanDay` hook — given source exercises + target plan + days-of-week + week/month count, bulk-writes `plan_days`/`plan_exercises` rows capped at the plan's `end_date`; supports conflict mode `replace_one` / `replace_future` / `add`; always a one-time bulk write (no live template link)
- [ ] New `useExtendPlan` hook — bumps `end_date`, optionally bulk-creates empty `plan_days` for the new range, exposes a "copy current weekly pattern into new months" one-tap action that calls `useReplicatePlanDay` internally
- [ ] New `getPlanDayStatus(day)` helper — pure function returning `empty | pending | missed | complete`; `missed` = has exercises + date < today + no completion row

**C. Log Wizard UI (`LogWorkoutPage.tsx`)**
- [ ] After existing `link_plan` step, branch: attach to **existing plan** or **create new plan** (reuse `CreatePlanForm` type/duration step for "new")
- [ ] Add scope step: **just this day** vs **recurring** (days-of-week picker + weeks/months count)
- [ ] If recurrence would exceed the plan's `end_date`: prompt to extend (via `useExtendPlan`) or auto-cap silently at the end date
- [ ] If target day(s) already have exercises: show conflict chooser — Replace (this occurrence / this + every future matching day) vs Add
- [ ] On submit for this path: write via `useReplicatePlanDay`, do **not** auto-complete — resulting day(s) land as PENDING
- [ ] Success screen for this path: "Added to plan — mark complete when done" (no points-earned display, since nothing is completed yet)

**D. Plan View UI (`PlanDetailView` / `DayCard`)**
- [ ] Render MISSED visual state for pending days whose date has passed (via `getPlanDayStatus`)
- [ ] Missed day, within 1 day: tapping complete shows grace confirmation ("No points, counts toward streak, X/3 used this month") → calls `useMarkDayComplete({ isLateGrace: true })`
- [ ] Missed day, past 1-day window OR monthly cap hit: complete checkbox locked/disabled with explanatory tooltip
- [ ] Surface "Extend plan" entry point on `PlanDetailView` as the plan's `end_date` approaches/passes

**E. Verify**
- [ ] Manual pass: new-plan link, existing-plan link, single day, recurring within range, recurring exceeding range + extend, replace-one, replace-future, add, miss + grace complete, exceed grace cap (locked), edit one replicated day and confirm siblings untouched
- [ ] Confirm points/streak/Pokemon logic is byte-for-byte unchanged for normal completions, and correctly skipped for grace completions

### 3. DB Schema — per-set tracking
- [ ] Add to `plan_exercises`: `target_sets`, `target_reps`, `target_weight_kg`, `rest_seconds`, `is_weight_optional` (bool)
- [ ] Add to `plan_exercises`: `duration_minutes`, `distance_km` (nullable, for cardio/yoga)
- [ ] Create `plan_exercise_sets` table: `(plan_exercise_id, set_index, target_reps, target_weight_kg)` — max 4 rows per exercise
- [ ] Add to `logged_exercises`: `sets`, `reps`, `weight_kg` (aggregate for backward compat)
- [ ] Create `workout_exercise_sets` table: `(logged_exercise_id, set_index, reps, weight_kg, completed_at, rpe)`
- [ ] Write Supabase migration SQL
- [ ] Update TypeScript types in `useLogWorkout.ts` and `useWorkoutPlan.ts`

### 4. Set Logging UI — Strong app style
UX pattern: pre-filled set rows from plan target, inline reps + weight per row, tap ✓ to log in real time, "Best today" + "Last session" header.

- [ ] `ExerciseSetRow` component: `reps` input + `weight_kg` input + ✓ checkmark button (tap to complete)
- [ ] Header bar per exercise: "Best today: Xkg × Y reps" (updates live as sets complete) + "Last session: Xkg × Y reps"
- [ ] Pre-fill rows from `plan_exercise_sets` targets (or fallback: `target_sets` × `target_reps` from plan)
- [ ] `+ Add set` button (max 4 sets per exercise)
- [ ] Weight validation: warn (yellow) at 90% of per-category cap; do not hard-block
- [ ] Real-time mutation: each ✓ tap fires `upsert` to `workout_exercise_sets`
- [ ] Rollup: on workout complete, sum sets into `logged_exercises.sets / reps / weight_kg` for backward compat

### 5. Plan Builder Wizard — multi-step
Entry points: "New Plan" button + secondary "Add to existing plan."

- [ ] **Step 1** — Plan name + duration (1–4 months max, extension prompt on expiry)
- [ ] **Step 2** — Workout type selector: Strength / Cardio / Flexibility / Yoga / Sport / Custom
- [ ] **Step 3** — Muscle group / body area / sport picker (reuse MuscleMapPicker)
- [ ] **Step 4** — 7-day picker: choose which days to assign this workout
- [ ] **Step 5** — Week count: how many weeks to repeat this workout day assignment
- [ ] **Step 6** — Conflict resolution per day: Replace / Merge / Skip (shown only if day already has a workout)
- [ ] **Step 7** — Remaining days: prompt for each unassigned day — assign rest / yoga / sport / skip
- [ ] Day edit scope modal: "Only this week" vs "This + all future weeks"
- [ ] Past days: read-only locked (no edit, no log)
- [ ] Deleted day: becomes empty/unassigned (not "Rest" — rest is explicit)

### 6. Yoga Database + Plan Type
- [ ] Source yoga pose list (check free-yoga-db or build a seed list of ~60 common poses)
- [ ] Schema: pose has `name`, `duration_seconds` (hold time: 30s / 60s / 90s), `body_area[]`, `instructions`, `image_url`
- [ ] Yoga exercises: duration-based only (no sets/reps/weight fields shown)
- [ ] Add `yoga` as a valid `plan_type` in DB enum and TypeScript types
- [ ] Yoga plan: body area targeting flow in Plan Builder (Step 3 shows body-area checkboxes instead of muscle map)
- [ ] LogWorkoutPage: detect `yoga` workout type → show duration-based logging UI instead of set/rep rows

### 7. Exercise Reorder — drag to reorder within a day
- [ ] Implement hold + drag reorder for exercises within a plan day
- [ ] Use `@dnd-kit/sortable` (already in React ecosystem, works on mobile touch)
- [ ] Persist new `sort_order` on drag end via upsert mutation

### 8. Randomize Button
- [ ] Button on plan day view: "Randomize exercises"
- [ ] Regenerates exercises for current day using only the selected muscle groups + equipment from gear setup
- [ ] Shows confirmation: "Replace X exercises for today?" — confirm before applying
- [ ] Scope: only replaces the current day's exercises, does not affect other days

---

## FUTURE ROADMAP (not in current sprint — capture for later)

- [ ] **User profile** — height, weight, age, medical conditions (affects weight cap per category, exercise recommendations)
- [ ] **Weight category caps** — per exercise category, derived from user profile (needed for 90% warning in set logging)
- [ ] **Supplement / tablet tracker** — log daily supplements with reminders
- [ ] **General life planner** — walks, activities, steps, non-gym movement
- [ ] **Individual sport tracking** — e.g., swimming laps, cycling distance, tennis sessions
- [ ] **Auto-progression engine** — Liftoscript-style: bump weight when all sets hit for N sessions
- [ ] **Muscle recovery model** — Fitbod-style: track last-trained per muscle, suggest fresh muscles for today
- [ ] **1RM calculator + PR detection** — auto-detect personal records on set completion
- [ ] **Plate calculator** — given target weight + available plates → show exact plate combo
- [ ] **Shareable routines** — publish plan template with a link
- [ ] **Bundle code-splitting** — main JS bundle is 926 kB, needs route-level lazy loading

---

## OPEN DESIGN DECISIONS (clarified in session 2026-06-10)

| Question | Resolved Answer |
|---|---|
| Set logging UX | Strong app style — pre-filled rows, tap ✓ per set in real time |
| Plan builder conflict | Per-day popup: Replace / Merge / Skip |
| Yoga handling | Duration-based, body-area targeting, separate plan type `yoga` |
| Weight validation | Warning at 90% of cap, NOT a hard block |
| Past days | Read-only locked — no edit, no log |
| Deleted plan day | Becomes empty/unassigned (not "Rest") |
| Plan duration max | 4 months; extension prompt when plan expires |
| Max sets per exercise | 4 |
| Warm-up / cooldown logging | Same per-set flow as main; tappable in LoggedWorkoutCard |
| Reorder mechanism | Hold + drag (dnd-kit/sortable) |
| Randomize scope | Current day only, within selected muscle groups + gear |

---

## OPEN DESIGN DECISIONS — Log-to-Plan Integration (clarified in session 2026-06-16)

| Question | Resolved Answer |
|---|---|
| Quick log (no plan) | Unchanged — stays exactly as it is today |
| Plan target | User picks an existing plan, or creates a new one (reuses `CreatePlanForm`) |
| Scope | Single day, or recurring (days-of-week + weeks/months count) |
| Recurrence vs plan end date | Capped at the plan's end date; offers to extend rather than silently exceeding it |
| Extended months default | Empty, with a one-tap "copy current weekly pattern?" prompt |
| Conflict on a populated day | Replace (this occurrence / this + every future matching day) or Add |
| Replication mechanism | One-time bulk write per day — never a live/shared template link (edit independence) |
| Resulting day state | Always PENDING — never auto-marked complete |
| Missed-day computation | Client-side at render time (no cron) — date has passed + no completion row |
| Grace window | Up to 1 day late — streak credit only, no points |
| Grace cap | 2–3 uses per calendar month; once hit, further late check-ins are locked (no record/points/streak) |
| Completion engine | Always routes through the existing `useMarkDayComplete` — no parallel pending/complete system |

---

# Fitness App — External Reference Notes

Reference research from two existing fitness sites used as inspiration for planning.
Captured: 2026-05-30.

Sources:
- darebee.com — non-profit free workout library (massive content, light UX)
- workout.cool — open-source builder + tracker + program library (richer product)

---

## 1. darebee.com

### Site structure / navigation
Top-level sections:
- Workouts (2,700+ items, paginated, ~15 per page)
- Training Plans
- Programs (95+ multi-week plans, new every 2 months)
- Challenges (monthly)
- Guides
- Collections (curated bundles)
- Community
- Bookmarks
- Dashboard (suggests per-user tracking)
- Donation CTA persistent

### Content types
| Type | Format | Scope |
|---|---|---|
| Workout | Single session | One-off, do anytime |
| Program | Multi-week structured plan | New every 2 months |
| Challenge | Monthly themed push | Time-bound |
| Collection | Curated grouping | Editorial |
| Guide | How-to / education | Static reference |

### Workout page content model (from a sample workout)
Fields actually shown on a workout page:
- Title
- Hero image / illustration
- 3 badges: **muscle focus**, **type** (strength/cardio/etc.), **difficulty level** (1–N)
- Built-in **timer** widget (presets 30s / 60s / 2min + custom, start/pause/reset)
- **Sets selector** dropdown (1–7)
- Prose description (technique, form cues, progression)
- "Done" button (completion tracking)
- Bookmark button
- "Extra Credit" — optional harder variation

Notably **missing** on the sample page: per-exercise sets/reps table, equipment list, rest times, GIFs. Many darebee workouts are described narratively, not as structured tables.

### UI / design tone
- Minimalist, content-first, almost wiki-like
- Functional over flashy
- GIFs / static illustrations for exercise demos
- Non-profit feel — donation appeals visible

### Useful patterns to borrow
- The **timer + sets selector** widget built right into the workout page (great pattern for execution UX)
- Separate **Workouts vs Programs vs Challenges** as distinct content types (not one homogeneous "plans" list)
- **Bookmarks** and **Dashboard** as user-account features
- "Extra Credit" / progression suggestion at end of each workout

---

## 2. workout.cool

### Product positioning
A **hybrid builder + library + tracker**, not just a content site. Open source.

### Top-level navigation
- Workouts — custom builder
- Programs — pre-built plans
- Statistics — performance tracking
- Tools — calculators
- Leaderboard — community ranking
- Premium — paid tier

### 3-step workout builder (key pattern)
1. **Equipment** — checkbox grid: bodyweight, dumbbells, barbells, kettlebells, bands, plates, pull-up bar, bench
2. **Muscle groups** — select target areas
3. **Exercises** — system filters the library to only what matches steps 1–2; user picks specific exercises

This is the **single most reusable pattern** for an MVP — it converts an exercise library into a personalized workout in 3 progressive-disclosure steps.

### Program content model (from listing page)
Each program card shows:
- Title
- Difficulty badge (Beginner / Intermediate)
- Duration in weeks (e.g., 4-week, 6-week)
- Frequency + session length (e.g., "4x/week, 50 min")
- Equipment list (Bodyweight, Dumbbell, Barbell, Machine, Band, Medicine ball)
- Short motivational tagline
- Premium flag (some)
- Mascot / hero image

Example programs observed:
| Name | Level | Weeks | Freq | Duration | Equipment |
|---|---|---|---|---|---|
| Full Body Novice Bodybuilding | Beginner | 4 | 4x/wk | — | Gym |
| Summer HIIT & Abs | Intermediate | 4 | 4x/wk | 45 min | — |
| Booty Pump (Premium) | — | 6 | 5x/wk | 50 min | — |
| Titan Core | Intermediate | 4 | — | 20 min | Bodyweight + medicine ball |

Categorization: by level today, with upcoming category axes — **Force & Muscle**, **Cardio HIIT**, **Yoga & Mobility**.

### Tools section
Live calculators:
- TDEE / Calorie calculator (inputs: activity, goal → daily calories)
- BMI calculator
- Heart-rate zones

Coming soon:
- Macro calculator
- 1RM calculator

Easy add-ons for any fitness app — low effort, high perceived value.

### UI / design tone
- Clean illustrated aesthetic with custom equipment icons
- Step-by-step progressive disclosure
- Mascot branding (cute, friendly)
- Multilingual (6 languages)
- Active community channels: Discord, GitHub, X

### Useful patterns to borrow
- 3-step Equipment → Muscle → Exercise builder
- Rich program card metadata (level, weeks, freq, session length, equipment)
- Tools / calculators as a separate hub
- Statistics + Leaderboard for retention / gamification
- Premium tier as a monetization path
- Open-source community signal (Discord + GitHub)

---

## 3. Side-by-side comparison

| Dimension | darebee.com | workout.cool |
|---|---|---|
| Primary value | Huge free content library | Personalized builder + tracker |
| Content depth | 2,700+ workouts, 95+ programs | Smaller curated library + builder |
| Workout structure | Narrative + badges + timer | Generated from equipment/muscle filters |
| Program metadata | Sparse on listing | Rich (weeks/freq/duration/equipment) |
| Tracking | Done button, Bookmarks, Dashboard | Statistics, Leaderboard |
| Tools / calculators | Mostly guides | Dedicated Tools hub |
| Monetization | Donations | Premium subscription |
| Community | Forum / Community section | Discord + GitHub + X |
| Visual style | Minimal, wiki-like | Illustrated, mascot, polished |
| i18n | English-first | 6 languages |

---

## 4. Implications for our `evofit` plan

Patterns worth adopting in the current app (`Fitness_app/evofit`):

1. **Distinct content types** — keep Workouts, Programs, and Challenges as separate concepts in the data model, not one unified "plan" table. (darebee shows this scales editorially; workout.cool shows it scales for builder UX.)

2. **Rich program metadata** — every program/plan should carry: `level`, `weeks`, `sessions_per_week`, `session_duration_min`, `equipment[]`, `focus_tags[]`, `goal`. Useful for filtering, cards, recommendations.

3. **3-step builder** — when generating a custom workout (e.g., today's plan AI generator), follow Equipment → Muscle → Exercise progressive disclosure. Aligns with what users already understand.

4. **In-workout execution widgets** — bake **timer + sets selector + Done button** into the workout/plan-day view, like darebee does. Reduces context-switching to a stopwatch app.

5. **Bookmarks + Dashboard** — user-facing personalization layer separate from the catalog. Already partially present (`useTodaysPlanDay`, `TodaysPlanDayTile`).

6. **Tools hub** — calorie/BMI/HR-zones/1RM calculators are cheap to ship and add perceived breadth. Could be a standalone `/tools` route.

7. **Stats + light gamification** — daily point cap and reward system already exist (per memory: obs 674, 676). Layering a leaderboard or streak view is a natural next step.

8. **Honest content scoping** — darebee's narrative workouts are sometimes "lighter" than they look; workout.cool's per-exercise structure is more verifiable. For our app, prefer **structured exercise objects** (name, sets, reps, rest, equipment, target muscles, demo image) over prose, so the data is trackable and reusable.

### Things to NOT copy
- darebee's missing per-exercise breakdown on many workout pages — opaque for tracking.
- workout.cool's Premium gating on basic programs — friction for an MVP audience.
- Either site's heavy reliance on category-only filtering — add free-text search and multi-axis filters from day one.

---

## 5. Open questions to resolve before planning

- Do we want a **builder** (workout.cool model) or just a **curated library** (darebee model) or both?
- Source of exercise data: build our own list, or wrap a public dataset (e.g., wger, exercemus)?
- Will Programs be authored (editorial) or AI-generated (per existing slice work on AI plan generator)?
- Is community / leaderboard in scope for v1, or post-MVP?
- Do we want a Tools / calculators hub in v1?

---

# Round 2 — Additional reference apps (added 2026-05-30)

Six more apps researched to widen the lens, focused on muscle-group selectors, image/video handling, data schemas, and folder structures.

| App | Strength | Type |
|---|---|---|
| MuscleWiki | Anatomical muscle-click selector + male/female video demos | Free site |
| wger | Open REST API, full self-hostable workout + nutrition platform | Open source (AGPL) |
| free-exercise-db | Public-domain JSON exercise dataset with images | Open data |
| Hevy | Best-in-class set/rep/weight logging UX | Mobile app |
| Liftosaur | Programmable workouts via DSL (Liftoscript) | Open source |
| Fitbod | AI-generated workouts with muscle-recovery model | Mobile app |

Fetch status: MuscleWiki and ExRx.net returned **HTTP 403** (bot blocked). The MuscleWiki notes below are from publicly known product behavior, not a fresh fetch — flagged for verification before relying on specifics.

---

## 6. MuscleWiki — anatomical muscle selector (the pattern you want)

> ⚠ Live page blocked WebFetch (403). The pattern is documented here from publicly known behavior. **Verify by visiting the site manually before copying specifics.**

### Selector UI pattern
- Two anatomical body silhouettes side-by-side on the landing page: **front view** and **back view**
- Each muscle region (chest, abs, biceps, forearms, quads, calves, traps, lats, glutes, hamstrings, etc.) is a **clickable hotspot** with hover highlight
- Optional toggle for **male/female anatomy** (changes both the diagram and the demo videos shown)
- Clicking a region → routes to that muscle's exercise list

### Exercise list page
- Filters: equipment (barbell, dumbbell, bodyweight, machine, kettlebell, cable), difficulty (beginner/intermediate/advanced)
- Each exercise card: name, short video demo (looping MP4 or animated WebP), target muscle tags, difficulty badge
- Detail page: 2 looping demo videos (male + female versions), bullet-point step-by-step, common mistakes section, sometimes a YouTube embed

### Why this matters for evofit
This is the **single best UX pattern for "I want to work my chest today"** — far more intuitive than a dropdown. Should be considered for the workout builder UI.

Implementation options:
- SVG body silhouette with `<path>` elements per muscle group, click handlers + CSS hover fills
- Existing libraries: `react-body-highlighter` (npm) wraps this pattern; renders front/back SVG with muscle props
- Or hand-roll an SVG using a sourced anatomical illustration

---

## 7. wger — open REST API + self-hostable

Live, mature open-source project. AGPLv3 licensed.

### Data scope
- 845+ exercises (multi-language)
- 3M+ food items for nutrition module
- Modules: Training, Body Weight, Nutrition, Body Measurements, Calendar/Progress

### Workout structure
- A **Workout** = weekly plan
- Each day = a **Day** with multiple **Sets**
- Each set has: exercise, reps (or distance/duration), weight, RPE optional
- Step-by-step guided execution mode

### REST API
- Open and CORS-enabled — can be consumed directly from a frontend
- Endpoints for exercises, exercise categories, muscles, equipment, workouts, sets, nutrition, weight entries, body measurements
- This is a **drop-in backend candidate** if we don't want to build our own exercise + nutrition CRUD

### Why this matters
- If our evofit roadmap includes nutrition or body measurements, wger could either inspire the schema or be embedded directly via API.
- The exercise + muscle + equipment taxonomy is already normalized and translated.

---

## 8. free-exercise-db — public-domain JSON dataset (RECOMMENDED seed)

This is probably the **fastest path to a real exercise library** for evofit. 800+ exercises, Unlicense (public domain), JSON + images on GitHub.

### Exact schema (confirmed via raw JSON fetch)

```json
{
  "id": "Alternate_Incline_Dumbbell_Curl",
  "name": "Alternate Incline Dumbbell Curl",
  "force": "pull",                              // "push" | "pull" | "static" | null
  "level": "beginner",                          // "beginner" | "intermediate" | "expert"
  "mechanic": "isolation",                      // "isolation" | "compound" | null
  "equipment": "dumbbell",                      // dumbbell | barbell | cable | machine | body only | ...
  "primaryMuscles": ["biceps"],                 // array of muscle slugs
  "secondaryMuscles": ["forearms"],
  "instructions": [                             // ordered array of step strings
    "Sit down on an incline bench with a dumbbell in each hand...",
    "While holding the upper arm stationary, curl the right weight forward..."
  ],
  "category": "strength",                       // strength | cardio | stretching | plyometrics | powerlifting | ...
  "images": [
    "Alternate_Incline_Dumbbell_Curl/0.jpg",    // start position
    "Alternate_Incline_Dumbbell_Curl/1.jpg"     // end position (two-frame "animation")
  ]
}
```

### Repository folder structure
```
free-exercise-db/
├── .github/workflows/        # CI
├── dist/
│   ├── exercises.json        # combined array of all exercises
│   └── exercises.nd.json     # newline-delimited (Postgres COPY-friendly)
├── exercises/
│   ├── <Exercise_ID>.json    # individual exercise file
│   └── <Exercise_ID>/
│       ├── 0.jpg             # start frame
│       └── 1.jpg             # end frame
├── site/                     # Vue.js demo frontend
├── schema.json               # JSON Schema validator
├── Makefile                  # build/lint/combine targets
└── LICENSE                   # Unlicense (public domain)
```

### How to consume
- **Static CDN**: `https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json` — fetch once at build time
- **Per-exercise**: `.../exercises/<ID>.json`
- **Images**: `.../exercises/<ID>/0.jpg` and `.../1.jpg`
- **Postgres import**: pipe `exercises.nd.json` through `\copy` or use a small loader
- **Image proxy**: pipe through ImageKit / Cloudinary / Vercel image optimizer for resizing

### Why this matters for evofit
- **Skip building an exercise library from scratch.** Seed our Supabase `exercises` table from `dist/exercises.json` once. Mirror images to Supabase Storage or just hot-link via raw GitHub.
- The schema is already close to what a workout app needs — `primaryMuscles[]` + `equipment` directly powers the workout.cool-style 3-step builder *and* a MuscleWiki-style selector.
- Public domain → no licensing risk.

---

## 9. Hevy — set/rep/weight logging pipeline

### Per-set data captured
| Field | Type | Notes |
|---|---|---|
| weight | number | kg or lb |
| reps | number | actual reps performed |
| set_type | enum | `normal` \| `warmup` \| `drop` \| `failure` |
| rpe | number (optional) | rate of perceived exertion |
| notes | string (optional) | per-set notes |

### Workout / routine model
- **Routine template** = ordered list of exercises with target sets/reps (no weights — those are entered live)
- **Workout** = an instance of a routine being executed (or freestyle), with actual sets logged
- **Exercise history** rolls up per-exercise across all workouts → drives PR detection and charts

### Notable features to consider stealing
- **Auto rest timer** per exercise (configurable default)
- **Personal records** auto-detected: heaviest weight, best 1RM, most reps at weight, best volume
- **1RM calculator** (Epley / Brzycki formula on the heaviest set)
- **Custom exercises** users can add to their library
- **Shareable routines** — users can publish their template
- **Social feed** — like/comment on others' workouts (out of scope for v1, but easy retention layer)

---

## 10. Liftosaur — programmable workouts (Liftoscript DSL)

Open-source, mobile + web. Niche but the technical model is impressive.

### Liftoscript pattern
Workouts are defined as **plain text scripts**:
```
# example
Bicep Curl / 3x10 / 12lb
Squat / 5x5 / 80%1RM
   progress: lp 5lb / 8 attempts
```

### Variables manipulable per set
- `weight` (absolute or `%1RM`)
- `reps`
- `RPE` (effort-based weight calculation)
- `sets`
- `rest`

### Progression engines built-in
| Scheme | Behavior |
|---|---|
| Linear progression | Add fixed weight when all sets hit |
| Double progression | Climb reps within a range, then bump weight |
| Rep-sum / volume-based | Advance when total volume threshold cleared |
| Custom script | Arbitrary JS-like rules per exercise |

### State machine
After every workout, the engine:
1. Reads logged sets
2. Evaluates whether prescribed targets were met
3. Applies the exercise's progression rule
4. Rewrites the next session's prescription

### Plates calculator
Given a prescribed weight + available plates + bar weight → returns the exact plate combo per side. Small feature, surprising user delight.

### Why this matters
For evofit's **AI plan generator** (Slice 1–4, obs 698), a Liftoscript-like internal representation makes the AI's output trackable, modifiable, and progressable. Even if we don't expose a DSL to users, storing programs as structured rules (not just static prescriptions) opens auto-progression as a v2 feature.

---

## 11. Fitbod — AI-generated workouts with recovery model

### Inputs the algorithm consumes
- Goal (strength, hypertrophy, endurance, weight loss)
- Fitness level
- Available equipment (per-session, can change daily)
- **Training history** — every logged set feeds back into the model
- **Muscle recovery state** — per muscle group, time since last trained + estimated fatigue

### Recovery model (the differentiator)
Each muscle group has an estimated **recovery state** (fresh ⇆ fatigued). Today's session preferentially targets recovered muscles. Heavily-trained muscles get rest until recovery completes (typically 48–72h).

### Output adjustments
- Suggested weight per set based on recent performance + estimated 1RM
- Exercise variety — rotates similar movements to prevent monotony
- Automatic warm-up sets
- Optional supersets to compress time
- Cardio / stretching / low-impact filler movements when conditioning is selected

### Why this matters
- Our existing AI plan generator (obs 693, 698) could borrow this **muscle-recovery scoring model** as part of the prompt context. "Don't pick chest today — user trained chest 24h ago" is a real personalization win.
- Easy to model in Supabase: a materialized view per user × muscle showing `last_trained_at` and a decay function.

---

## 12. Consolidated data model for evofit (recommendation)

Combining the strongest patterns from all sources:

### Core tables
```
exercises
├── id (slug)
├── name
├── category          # strength | cardio | stretching | plyometric
├── force             # push | pull | static
├── mechanic          # isolation | compound
├── level             # beginner | intermediate | expert
├── equipment         # dumbbell | barbell | bodyweight | ...
├── primary_muscles   # text[]
├── secondary_muscles # text[]
├── instructions      # text[]
├── images            # text[]  (paths or URLs)
├── video_url         # nullable
└── source            # free-exercise-db | manual | wger

routines (templates)
├── id, user_id, name, level, weeks, sessions_per_week
└── created_by_ai (bool)

routine_days
├── routine_id, day_index, name (e.g., "Push Day"), focus_tags

routine_day_exercises
├── routine_day_id, exercise_id, order
├── target_sets, target_reps, target_weight_pct_1rm
└── progression_rule (jsonb) — Liftoscript-style

workouts (logged instances)
├── id, user_id, routine_day_id (nullable), started_at, ended_at, notes

workout_sets
├── workout_id, exercise_id, set_index
├── weight, reps, set_type (normal|warmup|drop|failure)
├── rpe, rest_seconds_actual, completed_at

personal_records
├── user_id, exercise_id, type (1rm|max_weight|max_reps|max_volume), value, achieved_at

muscle_recovery (materialized view)
└── user_id, muscle, last_trained_at, est_fatigue_score
```

### Why this shape
- Mirrors free-exercise-db so seeding is one SQL `\copy`
- Separates **template (routine)** from **instance (workout)** like Hevy
- `progression_rule` jsonb leaves room for Liftosaur-style auto-progression later
- `muscle_recovery` view powers Fitbod-style "what should I train today" hints
- `primary_muscles[]` + `equipment` powers both muscle-selector and equipment-filter UIs

---

## 13. Updated implications for evofit (revised from §4)

Highest-leverage adds, in priority order:

1. **Seed exercises from free-exercise-db on day one.** 800+ public-domain exercises with images. One-shot ingest into Supabase. (§8)
2. **MuscleWiki-style anatomical selector** on the workout builder page. Use `react-body-highlighter` or a custom SVG. (§6)
3. **Adopt the Hevy set logging shape** (`weight`, `reps`, `set_type`, `rpe`). It's the de-facto standard. (§9)
4. **Persist routines as structured progression rules**, not just static sets/reps. Even if v1 doesn't auto-progress, the data shape leaves the door open. (§10)
5. **Track per-muscle recovery state** as a materialized view. Feed it into the AI plan generator's prompt for better day-of recommendations. (§11)
6. **Two-image "animation" pattern from free-exercise-db** (start + end frame) is a cheap demo format that works without video infra. Upgrade to looping MP4 / WebP later. (§8)
7. **Auto rest timer + 1RM detection** as quick-win execution features. (§9)
8. **Calculators hub** (TDEE, BMI, HR zones, 1RM, plate math) — low effort, high perceived breadth. (§10 plates, original §4)

### Pitfalls to avoid
- Storing `primary_muscles` as a single string instead of array — kills filtering immediately.
- Hard-coding equipment list as an enum without an "other / custom" escape hatch.
- Building a "workouts" table that mixes template and instance fields — splits cleanly into routines vs workouts.
- Hot-linking GitHub raw image URLs in production without a CDN/cache — works for prototypes, fragile at scale.

---

## 15. Multi-Perspective Critique — Log Page & Plan Page (2026-06-29)

Based on reading actual code: LogWorkoutPage.tsx, LogWorkoutSteps.tsx, PlansPage.tsx,
PlanListView.tsx, PlanDetailView.tsx, DashboardPage.tsx.

---

### New User — First 10 Minutes

Log workout flow has 6 steps before doing anything:
type → muscles → duration → equipment → AI generates → link to plan.

Step 2 (muscle map): confusing for beginners who don't know anatomy. "Skip for full-body" exists
but why show the screen at all if you'll skip it? Needs a "Not sure — just go" primary button.

Step 4 (equipment): pre-filled from gear profile they never set up. Shows wrong/blank state first time.

Step 6 (AI generation): 1-2 second wait staring at a spinner. No preview of what's coming.

Step 7 (link to plan): they don't know what a plan is yet. Confusing concept at the wrong moment.

Result: most first-time users abandon before logging a single set. 6 steps before doing anything.
What they expected: tap Log → see a workout → start it. Max 2 steps.

---

### Casual User (2-3x per week, 1 month in)

- No "repeat last workout" shortcut. Every session restarts the full 6-step wizard. Groundhog day.
- Duration step: they always pick 45 min. Why is this a step every time?
- Equipment step: same equipment every session. Why is this a step every time?
- No live workout mode. The generated plan shows exercise names only — no guided mode, no
  exercise-by-exercise flow, no auto rest timer.
- Timer is a floating FAB requiring 5 manual taps between every set. (open FAB → set time →
  start → wait → cancel → log next set). Should auto-start after each set ✓ is tapped.
- SET LOGGING UI IS NOT YET BUILT. Plan shows "Bench Press 3x8" but cannot log actual
  weight or reps per set. Users are tracking on paper. This is the #1 critical gap.
- No memory of previous weights. Was it 60kg or 70kg last week? No reference shown.
- No way to add an exercise not in the AI suggestion (only swap one at a time, not add new).
- Plan page: 3 levels deep to find today (plan card → plan detail → week → day card).

---

### Serious Lifter (Progressive Overload / Programs)

- No per-set logging: weight + reps + set type per row (non-starter vs Strong/Hevy).
- No PR detection: hitting a new personal best → silence. Strong shows "NEW PR" live on the set.
- No progressive overload: AI generates same difficulty plan each time. No memory of last session.
- No 1RM calculation: formula is trivial (Epley: weight × (1 + reps/30)). Missing.
- No custom exercises: cannot add a favourite variation not in the exercise DB.
- 4-month plan max: serious lifters run 6-12 month programs. Forces manual plan stitching.
- No superset support: push/pull splits rely on supersets. No pairing concept exists.
- No set type differentiation: warmup | normal | drop | failure (Hevy standard). EvoFit has one type.
- Phases in plan detail (Adaptation/Progression/Peak): cosmetic labels only. Don't actually
  change prescribed exercises or weights. A serious lifter notices immediately.

---

### Critic (has used Strong, Hevy, Fitbod, Strava)

STEP COUNT: EvoFit = 6 steps before doing anything. Strong = 2 steps. That's the whole review.

"Generate My Plan →" is vague: no preview, no confidence, no "here's what you'll get." Commits
user to a spinner. Fitbod shows a preview before committing.

`link_plan` step is backwards: "do you want to add this to a plan?" comes AFTER you build the
workout. The question of "which plan is this for?" should come FIRST, before muscle selection.

Themes as a top-level tab: `Plan | Records | Themes` — Themes is a visual customization
feature. It should be in Settings. Its placement signals the team ran out of core features.

Muscle heatmap on dashboard: beautiful idea, but no interpretation. "Red = trained recently" —
is that bad? Do I need more recovery? Data without insight is noise.

Success screen: points earned, done. No PR callout. No "longest session this month." No
comparison to last session. Hevy shows: new PRs highlighted, volume vs last session, exercise
breakdown. EvoFit shows a number.

Plan card grid: 2-column cards show cover image + name + type badge. Does NOT show what
today's workout is. The only question that matters when tapping a plan card is "What do I do
today?" The card doesn't answer it.

No "Start Today's Workout" shortcut: TodaysPlanDayTile on dashboard exists but tapping it
navigates to plan detail → right week → right day → expand card. Three more taps. Should be
a direct "Start Workout →" CTA on the tile.

No confirmation before losing work: on plan step (step 5 of 7), two back taps lose all
muscle selection, duration, equipment, and the generated plan. No "are you sure?" dialog.

clonePlan.isPending shared across ALL plan cards (PlanListView.tsx:163): clone Plan A and
every card shows spinner. A clear visual bug that signals polish gaps.

No offline mode: gyms have poor signal. A fitness app must work offline with local-first
logging that syncs when connection returns.

Font and typography: default Tailwind sans-serif. Numbers during workout (weight × reps) should
be large, high-contrast, readable at arm's length with sweaty hands. Needs a strong type decision.

---

### Developer / Security Gaps

| Issue | File | Risk |
|---|---|---|
| eslint-disable on generateWorkout useEffect | LogWorkoutPage.tsx:58 | Stale plan if muscles/duration change after reaching plan step |
| clonePlan.isPending shared across all cards | PlanListView.tsx:163 | Visual bug — all cards show spinner when one is cloning |
| No optimistic update on plan delete | PlanListView.tsx | Delete feels slow; should remove immediately, revert on error |
| logWorkout.error only shown on link_plan step | LogWorkoutPage.tsx:254 | Error invisible if user is on scope/extend steps |
| Cardio pace stored as free text in notes | LogWorkoutPage.tsx:65 | "5 km · pace: 5:30/km" is unstructured — cannot query/sort/compare |
| No rate limit on AI plan regeneration | generateWorkout call | User can spam "Regenerate" button with no throttle |
| plan.pdf_url used for HTML detection via isHtmlPath() | PlanDetailView.tsx:113 | URL-based file type detection breaks on renamed files |
| No back-navigation confirmation guard | LogWorkoutPage.tsx | Two back taps from plan step loses all user work silently |

---

### Visual / Feel — What Would Attract More Users

GOOD:
- Yellow accent on dark = energetic, consistent, identifiable brand
- Equipment SVG icons = polished, distinctive
- Framer Motion step transitions = smooth, modern feel
- Muscle map picker = interactive, tactile
- Pokemon catch mechanic = unique, viral potential, real retention hook

NEEDS WORK:

Number typography: during a workout, weight and reps are the hero. They need to be dominant,
high-contrast, readable at arm's length. Current sizing is fine for navigation but not for
active logging. Consider a strong geometric typeface for numbers.

No exercise images: plan step shows exercise names as plain text. free-exercise-db has two-frame
start/end images for every exercise (public domain). Adding them to the plan step and set rows
would make the app feel 10× more professional with one integration.

Success screen lacks celebration: Hevy/Strong show PR announcements with animation.
EvoFit's Pokemon catch is the celebration — but only when a Pokemon is caught. Non-catch
sessions end with a stat card. Even a simple "volume up vs last session" bar would help.

Plan calendar is 4 levels deep: months → weeks → days → exercises. For most users the
plan is "Push / Pull / Legs / Rest" repeating. A 7-day weekly schedule strip (like a
calendar row) would communicate this instantly without the multi-level hierarchy.

No progress chart: after 4 weeks of logging, there's no "bench press over time" chart or
"monthly volume vs last month." This is the primary retention hook for serious lifters.
Dashboard has weekly points bar chart — needs exercise-specific progress charts.

---

### Prioritised Fix List

CRITICAL (blocking serious users):
1. Per-set logging UI (reps + weight + ✓ per row, Strong-style) — in sprint queue
2. "Last session weights" visible when logging — from workout history
3. PR detection on set completion — live, on the row

HIGH FRICTION (losing casual users):
4. "Repeat last workout" shortcut — on home tile and log entry point
5. Remove equipment as a mandatory step — pre-fill silently, "edit" link on plan step
6. Remove duration as a mandatory step — pre-fill 45 min, adjustable on plan screen
7. Live workout mode — "Start Workout" → guided per-exercise with auto rest timer
8. Confirmation dialog when navigating back from plan step
9. "Start Today's Workout" CTA directly on TodaysPlanDayTile and plan cards

VISUAL / FEEL:
10. Exercise images (free-exercise-db two-frame) on plan step and set rows
11. PR callout on success screen — "NEW PR: Bench Press 82.5 kg"
12. Move Themes tab to Settings — replace with Progress or Today tab
13. Strong number typography for set logging rows

DEVELOPER FIXES:
14. Per-plan clone pending state (not shared across all cards)
15. Structured cardio fields (not text concatenation into notes)
16. AI regenerate rate limit (max 3 per session)
17. Back-navigation guard on plan step

---

## 14. Sources & verification status

| Source | Fetched | Confidence |
|---|---|---|
| darebee.com (homepage, workouts, programs, individual workout) | ✅ | High |
| workout.cool (homepage, programs, tools) | ✅ | High |
| workout.cool/exercises | ❌ 404 | — |
| MuscleWiki | ❌ 403 (bot blocked) | Medium — patterns from public knowledge, verify manually |
| wger.de/en/software/features | ✅ | High |
| free-exercise-db (README + repo + sample exercise JSON) | ✅ | Very High (raw JSON confirmed) |
| hevyapp.com | ✅ | High |
| liftosaur.com | ✅ | High |
| fitbod.me | ✅ | High |
| exrx.net | ❌ 403 (bot blocked) | — not used |
