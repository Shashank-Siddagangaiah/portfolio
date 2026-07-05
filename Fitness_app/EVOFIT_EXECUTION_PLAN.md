# EvoFit — Execution Plan
Last updated: 2026-06-27
Status legend: [ ] Not started | [→] In progress | [x] Done

Cross-reference:
- PLANNING_REFERENCES.md — shipped features + original sprint queue detail
- EVOFIT_MAJOR_UPGRADES_PLAN.md — full design spec per feature
- EVOFIT_VALIDATION_SYSTEM.md — anti-cheat system spec

Hand tasks to Claude one at a time. Each task is self-contained and completable in one session.

---

## PHASE 0 — Already Shipped ✓

- [x] Plans UI full refactor (13 components)
- [x] PlanDetailView (month/week nav, auto-scroll, Jump-to-today)
- [x] LoggedWorkoutCard (expandable history, tappable exercises)
- [x] Workout complete summary screen (volume, points, rest-day cap)
- [x] DayCard double-award deduplication (DB unique index)
- [x] PlanListView filter chips (All / Active / Paused / Archived)
- [x] Interval timer (HIIT / Tabata / EMOM / AMRAP + stopwatch)
- [x] Equipment SVG icons
- [x] MuscleMapPicker (front/back body silhouette)
- [x] Points Spent display
- [x] Edit gear setup link from LogWorkoutPage
- [x] Warm-up / Cooldown tappable in LoggedWorkoutCard

---

## PHASE 1 — Current Sprint (complete these before anything else)

- [→] **T01** — Log-to-Plan Integration (data layer + hooks + UI + verify)
  See PLANNING_REFERENCES.md §2 for full spec. Large task — breaks into A/B/C/D/E sub-items.

- [ ] **T02** — DB Schema: per-set tracking
  Add target_sets/reps/weight to plan_exercises. Create workout_exercise_sets table.
  Write Supabase migration SQL. Update TypeScript types.

- [ ] **T03** — Set Logging UI (Strong app style)
  ExerciseSetRow component. Pre-filled rows from plan targets. Best today + Last session header.
  + Add set button (max 4). Real-time upsert on ✓ tap. Rollup on workout complete.

- [ ] **T04** — Plan Builder Wizard (7 steps)
  Name + duration → workout type → muscle picker → days → week count → conflict resolution → remaining days.
  Day edit scope modal. Past days read-only.

- [ ] **T05** — Yoga Database seed
  Source ~60 poses. Schema: name, duration_seconds, body_area[], instructions, image_url.
  Add yoga as valid plan_type. Duration-based logging UI.

- [ ] **T06** — Exercise Reorder (drag to reorder within a day)
  @dnd-kit/sortable. Persist sort_order on drag end.

- [ ] **T07** — Randomize Button
  Regenerates exercises for current day within selected muscle groups + gear.
  Confirmation dialog before applying.

---

## PHASE 2 — Light Builds (quick wins, do after Phase 1)

These are self-contained, low-risk, and deliver real value. Each is a single Claude session.

- [ ] **T08** — PWA manifest + offline log writes
  Add manifest.json (name, icons, theme). Register service worker via Workbox.
  IndexedDB write-first for workout_sets. Background sync to Supabase on reconnect.
  Effort: S (half day)

- [ ] **T09** — Tools / Calculators hub (/tools route)
  1RM (Epley formula), Plate calculator, TDEE (Mifflin-St Jeor), BMI, Protein target, Heart rate zones.
  All client-side math. No backend needed.
  Effort: S (1 day)

- [ ] **T10** — Body measurement tracking
  Monthly log: body weight, waist, chest, bicep, thighs. Simple form.
  Trend chart (line graph over time). Store in body_measurements table with RLS.
  Effort: S (1 day)

- [ ] **T11** — Sleep tracking
  Nightly log: hours slept (slider 3–12h) + quality (1–5 stars).
  Store in sleep_logs table. Show 7-day average on profile/stats screen.
  Effort: S (half day)

- [ ] **T12** — Pre-workout mood check
  Emoji selector (😴 Low / 😐 Normal / 💪 High) shown at start of each workout session.
  Store in mood_logs table. Show on workout summary: "You felt 💪 today."
  Effort: S (half day)

- [ ] **T13** — Injury log
  "Any pain today?" checkbox → body area picker → severity 1–5.
  Store in injury_logs table. Alert after same area flagged 3 consecutive sessions.
  Effort: S (half day)

- [ ] **T14** — Streak shields
  Earn 1 shield per 7-day consecutive streak. Bank up to 3. Use to protect streak on a missed day.
  Shield count visible on profile. Store in user_shields table.
  Effort: S (1 day)

- [ ] **T15** — Progressive overload notification trigger
  Query: if user has logged same exercise at same weight × reps for 3+ consecutive sessions
  → create a notification record. Display as an in-app banner next time they open that exercise.
  Effort: S (half day)

- [ ] **T16** — Protein target daily checkbox
  Daily prompt: "Hit your protein target today? [Yes] [No]"
  Target = user body weight (kg) × 1.6 g. Shown on daily summary. +5 pts for Yes.
  Effort: S (half day)

- [ ] **T17** — Posthog analytics integration
  Add Posthog SDK. Track: onboarding_completed, first_workout_logged, plan_created,
  challenge_accepted, avatar_generated, tools_used. Free tier covers first 1M events.
  Effort: S (half day)

---

## PHASE 3 — Medium Builds

Each needs focused design before coding. Reference EVOFIT_MAJOR_UPGRADES_PLAN.md for spec.

- [ ] **T18** — Onboarding flow redesign
  7-step assessment: welcome → height/weight/age/sex → fitness level + goal → equipment →
  sport preference → photo upload (optional) → first plan suggestion.
  Critical: everything downstream depends on this data.
  Effort: M (3–4 days)

- [ ] **T19** — User profile page
  Display and edit: height, weight, age, sex, fitness level, goal, sport.
  Show: current level, points, streak, shields, pet, avatar thumbnail.
  Effort: M (2–3 days)

- [ ] **T20** — Validation system (anti-cheat)
  exercise_validation_caps table seeded with world record ceilings + bodyweight multipliers.
  Server-side check in set logging Edge Function. Sarcastic response copy on Red zone.
  Self-reported flag on Yellow zone. appeal form and validation_flags table.
  Spec: EVOFIT_VALIDATION_SYSTEM.md
  Effort: M (3–4 days)

- [ ] **T21** — Push notifications (OneSignal)
  OneSignal React SDK integration. 6 notification types: challenge result, streak reminder,
  overload suggestion, avatar ready, incoming challenge, friend joined.
  User opt-in/out per type in settings.
  Effort: M (2 days)

- [ ] **T22** — Pet mascot system
  Selection UI at onboarding: cat or dog, 3–4 breed/color variants.
  Evolution per level tier (visual upgrade at each tier). Emotional reactions
  (win/lose challenge, streak milestone, missed workout). CSS/sprite animations.
  Effort: M (3–4 days)

- [ ] **T23** — Yoga pose seed database (extended)
  80–100 poses with: Sanskrit name, English name, difficulty, hold_seconds,
  body_areas[], primary_muscles[], contraindications[], alignment_cue_short, image_url.
  Validated against Iyengar standards. Seeded via SQL migration.
  Effort: M (2–3 days — mostly data curation)

- [ ] **T24** — Famous workout templates (importable)
  Seed 4–6 templates: Bruce Lee Foundation, 5×5 Stronglift, PPL, 30-Day Bodyweight.
  Templates stored as routine rows with is_template=true.
  Import = clone rows into user's account with auto-scaling to user's body weight.
  Effort: M (2 days)

- [ ] **T25** — Sport × weakness exercise matrix (seeded)
  8 sports × common weak areas × targeted exercises. Stored as structured seed data.
  UI: select sport → weak area chips → generate prehab routine.
  Muscle groups auto-selected in workout builder.
  Effort: M (2–3 days — mostly data + UI)

- [ ] **T26** — dbt staging + intermediate models
  stg_workout_sets, stg_body_measurements, stg_sleep_logs.
  int_personal_records, int_muscle_recovery_state, int_consistency_score.
  dbt tests on all staging models. GitHub Actions schedule.
  Effort: M (3–4 days)

---

## PHASE 4 — Heavy Builds (architect before starting each)

These need a design session before a build session. Do not start without a plan.

- [ ] **T27** — Friends system
  User ID generation (EvoFit#XXXX). Friend request via User ID or email.
  friendships table with RLS. Private leaderboard view (friends only).
  Search by User ID (rate-limited). Block/report mechanism.
  Effort: L (1–2 weeks)

- [ ] **T28** — Challenge system
  Challenge creation, acceptance, scope (1 set), wager (25/50/100 pts).
  Daily log window. Midnight result lock. Atomic point transfer (SECURITY DEFINER function).
  Challenge eligibility gate (1-month log history). Rotating sarcastic messages on flags.
  Spec: EVOFIT_VALIDATION_SYSTEM.md + EVOFIT_MAJOR_UPGRADES_PLAN.md §4
  Effort: L (2 weeks)

- [ ] **T29** — dbt mart layer
  mart_ai_recommendation_inputs (one row/user, feeds agents).
  mart_leaderboard. mart_validation_pattern_flags. mart_avatar_progression_triggers.
  On-demand refresh for individual user on stats screen open.
  Effort: L (1 week)

- [ ] **T30** — Gym Workout Agent (AI)
  Supabase Edge Function. Claude Haiku tool use. Tools: get_fitness_context (reads T29 mart),
  search_exercises, check_muscle_recovery, save_workout_plan.
  Groq free tier for development. Rate limiting (5 calls/min/user).
  Effort: L (1 week)

- [ ] **T31** — RAG ingestion pipeline
  LlamaIndex + sentence-transformers (local, no API cost). Chunk PDFs by asana/section.
  Store embeddings in Supabase pgvector. One-time script, re-run when new content added.
  Effort: L (1 week — mostly setup + tuning)

- [ ] **T32** — Yoga Sequence Agent (AI + RAG)
  Edge Function. Tools: search_yoga_poses (pgvector), get_pose_details, get_user_injuries,
  save_yoga_plan. Generates sequenced 20–60 min sessions respecting contraindications.
  Depends on: T31 (RAG pipeline), T23 (seed DB).
  Effort: L (1 week)

- [ ] **T33** — Sports Conditioning Agent
  RAG on NSCA / PT literature (same pipeline as T31, different corpus).
  Sport + weak area → targeted prehab routine generation.
  Depends on: T25 (seed matrix), T31 (RAG pipeline).
  Effort: L (1 week)

- [ ] **T34** — Avatar generation system (premium)
  Photo upload (private Supabase Storage). Content moderation (AWS Rekognition).
  Batch job via Edge Function: 30 variants (5 level tiers × 6 activity types).
  Replicate API (InstantID + FLUX.1). avatar_variants table. User notification on complete.
  Gate behind premium tier.
  Effort: L (2 weeks)

- [ ] **T35** — Shareable challenge cards
  Server-side image render (Satori or Cloudinary template).
  Card: user avatar + exercise + result + EvoFit level + pet.
  One-tap share to WhatsApp / Instagram Stories.
  Depends on: T28 (challenges), T34 (avatar) or illustrated fallback.
  Effort: L (1 week)

---

## PHASE 5 — Security Hardening (runs in parallel, not after)

These should be done alongside each phase, not saved for the end.

- [ ] **S01** — RLS policies on all tables
  Enable RLS on every table. Write policies per the matrix in EVOFIT_MAJOR_UPGRADES_PLAN.md §27.2.
  Do this before any Phase 3+ table is created.

- [ ] **S02** — Secrets audit
  Verify no API keys in frontend bundle. Supabase service role key in Edge Function env only.
  All AI API keys (Claude, Groq, Replicate) in Edge Function env only.

- [ ] **S03** — Input sanitization
  Sanitize all user-supplied text fields (display names, notes). MIME type + size check on uploads.

- [ ] **S04** — Rate limiting on Edge Functions
  Add per-user rate limit check before every external AI API call.

- [ ] **S05** — GDPR / privacy
  Consent checkbox at photo upload. One-tap full account deletion (data + storage).
  Privacy policy linked from onboarding.

---

## Task Handoff Protocol

When handing a task to Claude:
1. Say "Start T[number]"
2. Claude reads the relevant spec sections, implements fully, and reports done
3. Mark it [x] here
4. Move to next task

Do not start a new task until the previous one is marked done and tested.
Security tasks (S01–S05) should be applied to each new table/endpoint as it is built,
not saved for a separate security sprint.
