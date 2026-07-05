# EvoFit — Major Upgrade Ideas
Captured: 2026-06-26 | Status: Planning / Not yet scheduled for implementation

This document captures the next generation of feature ideas discussed in session.
None of these are in the current sprint queue — this is a forward-looking design capture.
Cross-reference with `PLANNING_REFERENCES.md` for existing shipped features and current sprint.

---

## 1. Personalized 3D Avatar System (replaces Pokémon)

### What changes
The Pokémon evolution mechanic is **removed**. In its place, the user's own avatar becomes the face of their progression. The avatar is generated from the user's real photo.

### How it works
1. **Onboarding photo step** — user uploads a photo or takes a live camera shot during profile setup.
2. **AI generation** — the photo is processed into a cartoonistic / stylized "3D-look" illustration of the person. Think animated-movie style: same face, recognizable likeness, but rendered as a game character.
3. **Batch pre-generation** — at the moment the user confirms their photo, ALL avatar variants are generated in one backend job. No per-level or per-activity regeneration after that.
4. **Level-based evolution** — as the user's EvoFit level increases, the avatar's physique visibly progresses: lean base → visible muscle definition → pronounced biceps / chest / shoulders. Same face throughout; only the body changes.
5. **Activity-type variants** — different avatar renders for each major section:
   - Gym / Strength: gym attire, barbell or dumbbell in hand
   - Cardio / Running: runner pose, activewear
   - Cycling: cycling kit, bike
   - Yoga: yoga pose, mat
   - Sports: sport-specific kit (racket, ball, etc.)

### Batch generation job design
- Triggered once: on photo confirmation
- Inputs: user photo + user's current stats (height, weight, fitness level for physique baseline)
- Outputs: a grid of pre-rendered images indexed by `(activity_type, level_tier)`
- Stored in Supabase Storage per user
- No real-time AI calls after the initial batch

### Level tiers that trigger a visual change
*TBD — suggested breakpoints:* Level 1–9 (starter), 10–24 (lean), 25–49 (defined), 50–74 (athletic), 75–99 (peak), 100+ (legendary). Exact numbers to confirm.

### Open questions
- Which AI image generation service? (Replicate / Stable Diffusion / fal.ai / DALL-E) — cost and quality trade-off.
- Is the "3D look" a stylistic render or a true 3D model? Current assumption: stylistic 2.5D illustration (like a cartoon render), NOT a Three.js rotatable model — simpler to generate and display.
- What is the fallback if the user declines to upload a photo? (Default illustrated avatar with generic face — same level-up physique system still applies.)
- How many distinct activity-type variants? Lock to the 8 existing environment/section types or a smaller set?

---

## 2. Pet Mascot System (alongside user avatar)

### What it is
A companion pet (cat or dog) that the user adopts during onboarding. The pet is purely cosmetic / gamification — it evolves alongside the user but doesn't affect workout logic.

### Selection
- Choose: cat or dog
- ~3–4 breed/color variants per animal (not an overwhelming list — e.g., tabby / black cat / orange cat; golden / husky / dalmatian)
- Chosen once at onboarding; can be changed as a reward at certain milestones

### Evolution
- Pet levels up in sync with the user's EvoFit level (or on its own XP track — TBD)
- Visual evolution per tier: small/young → medium/adolescent → fully grown, with cosmetic upgrades (accessories, glow effects, etc.)
- Pet can unlock titles / skills at milestones (e.g., "Speed Demon", "Iron Paws", "Zen Master") — these are cosmetic labels, not gameplay mechanics

### Environment backgrounds (8 sections)
Already planned in existing roadmap. Pet appears in the user's chosen environment background. The background unlocks correspond to sections (gym, cardio, yoga, sports, etc.).

### Open questions
- Does the pet evolve on the same level track as the user avatar, or does it have its own XP system?
- Are "pet skills" visible on the profile card / leaderboard, or only on the user's own screen?

---

## 3. Friends & Social Challenge System

### Friend connection (privacy-first design)
- Users are assigned a **randomly generated User ID** at signup (like a gaming handle — e.g., `EvoFit#4821`). They choose a display nickname.
- Friend requests sent via: **User ID** OR **email address**. Phone number is explicitly NOT used.
- Real name is never shown outside of the user's own profile. The leaderboard and challenges display only the chosen nickname + User ID.
- Sports section: optional — users can voluntarily share their User ID with a sports opponent to link a match result. This is opt-in per match, not a global setting.

### Leaderboard
- Default view: **friends-only leaderboard** (not a global public board)
- Ranking metric: total EvoFit points, level, or streak — TBD on display priority
- Visible fields: nickname, User ID, avatar thumbnail, rank, points

### Challenge eligibility gate
Before a user can challenge a friend on an exercise, they must:
1. Have logged that exercise for **at least 1 continuous month** in the relevant section
2. Have logged it in the **same section type** as the challenge (e.g., gym strength challenges only from gym section logs)

This gate exists to prevent users from entering challenges on exercises they have no history on and posting inflated numbers.

---

## 4. Challenge Mechanics

### How a challenge works
1. User A challenges User B on a specific exercise (e.g., "max push-ups in one set")
2. Both agree to the challenge terms
3. A **point wager** is set (e.g., 50 points each) — winner gains both (net +50), loser loses their stake
4. Both users log their attempt at **any time during the challenge day** — no live head-to-head required
5. Result is **announced the next day** (after the log window closes)
6. Only exercises with 1+ month of history are in the challenge-eligible pool — no "anything goes" exercise picker

### Challenge scope
- **One session / one set** — the logged value must be from a single set entry, not summed across a day
- This prevents gaming (e.g., logging 200 push-ups spread across 10 sets and counting it as one challenge attempt)

### Sports match result logging
- When two users play a sport together, either can initiate a "log this match" request
- **Both users must confirm the result** before it is recorded (mutual agreement)
- Match result contributes to sports section stats and leaderboard
- User ID sharing for sports is optional and per-match

---

## 5. Input Validation / Anti-Cheat

### Why this matters
Without validation, a user could log 1,000 push-ups on day one and immediately top the leaderboard or win any challenge. The validation layer must be server-side (not just client-side) since clients can be modified.

### What to validate against
At onboarding, the user provides: **height, weight, age, fitness level**. These become the calibration inputs.

| Input | Used to derive |
|---|---|
| Body weight | Max realistic bodyweight exercise reps (push-ups, pull-ups, dips) |
| Weight + fitness level | Max realistic barbell / dumbbell weights per exercise category |
| Age | Adjusts cap slightly (younger = slightly higher ceiling) |

### Validation rules (examples — exact numbers need sports science sourcing)
| Exercise type | Soft warning threshold | Hard reject threshold |
|---|---|---|
| Push-ups (one set) | > 150 reps | > 300 reps |
| Pull-ups (one set) | > 50 reps | > 100 reps |
| Bench press weight | > 2× bodyweight | > 3× bodyweight |
| Squat weight | > 2.5× bodyweight | > 4× bodyweight |

- **Soft warning**: "That's an elite-level number — confirm?" with a prompt before saving
- **Hard reject**: entry refused with an explanation — user must re-enter

### Challenge-specific validation
- Challenge logs checked against the same per-user cap
- If both challenge entries exceed their respective user caps → both entries flagged, challenge result voided, no points transferred
- Repeated violations → challenge eligibility suspended

### What NOT to block
- High but plausible numbers (an advanced user with documented history)
- Cardio metrics (distance, duration) — harder to cap, use softer anomaly detection instead

---

## 6. Gym Section Reorganization & Template Workouts

### Restructured gym categories
Current state is a flat list. Proposed hierarchy:

```
Gym
├── Strength
│   ├── Beginner (compound movements, low weight, high rest)
│   ├── Intermediate
│   └── Advanced (progressive overload, periodization)
├── Cardio
│   ├── HIIT
│   ├── Steady State
│   └── Interval
├── Flexibility / Mobility
└── Bodyweight / Calisthenics
```

Each category surface: difficulty badge, estimated duration, equipment needed, target muscle groups.

### Pre-built famous workout templates (importable)
Users can browse and one-tap import a template. The template auto-scales to the user's body stats on import.

Examples to seed:
| Template | Description | Auto-scales? |
|---|---|---|
| Bruce Lee Foundation | ~80% bodyweight exercises, bench press capped at 8 reps, compound-focused | Yes — reps/weight to user BW |
| 5×5 Stronglift | 5 sets × 5 reps on 5 barbell lifts, linear progression | Yes — starting weight from user BW |
| Push / Pull / Legs (PPL) | 6-day split | No — fixed structure, user sets own weights |
| 30-Day Beginner Bodyweight | No equipment | No scaling needed |

More templates can be added by the team without app updates (if stored in DB).

### AI-generated personal template
- After 1+ month of logging, the app can generate a **custom template** from the user's actual logged exercises, preferred equipment, and muscle group history
- This is distinct from the daily AI plan generator — it outputs a **saved routine template**, not just today's workout

---

## 7. Yoga Section Enhancement

### Current state
Yoga is already planned as a `plan_type` (see `PLANNING_REFERENCES.md` §6). This upgrade adds difficulty tiering and curated asana sequences per level.

### Upgrade
- Difficulty tiers: **Beginner → Medium → Intermediate → Advanced**
- Per tier: a curated sequence of yoga asanas (poses) with hold times
- AI-generated option: given the user's body area focus (e.g., lower back, hips), generate a personalized asana flow for that session
- Each asana: name, illustration/image, hold duration, benefits, contraindications

### Tie-in to avatar
- Yoga-specific avatar variant (calm pose, yoga mat) shown at yoga section level milestones

---

## 8. Sports Section — Sport-Specific Workouts

### What this adds
Currently, sports logging is session-based (you log that you played badminton for 45 min). The upgrade adds **sport-specific conditioning workout programs** inside each sport's section.

### How it works
1. User selects their sport (e.g., Badminton)
2. The relevant muscle groups are **automatically pre-selected** based on that sport's primary movers:
   - Badminton → shoulders, forearms, quads, calves, core
   - Swimming → lats, shoulders, triceps, core
   - Basketball → quads, glutes, calves, core, vertical jump
3. A set of sport-specific conditioning workouts is shown — drilled down to Intermediate / Advanced player level
4. These are logged the same way as gym workouts (sets, reps, weight or duration)

### Sport-specific workout examples
| Sport | Sample workout |
|---|---|
| Badminton | Lateral agility ladder, shoulder internal rotation, wrist strengthening, calf raises |
| Cycling | Hip flexor stretch, quad strength, core stability, glute bridges |
| Running | Calf raises, hip adductors, IT band work, plyometric jumps |

### Tie-in to challenges
- Sport-section logs (conditioning workouts) also count toward the 1-month challenge eligibility gate — meaning a badminton player can challenge a friend on "max lateral shuffles" if both have logged badminton conditioning for a month

---

## 9. Summary of What This Upgrade Changes

| Area | Current state | After upgrade |
|---|---|---|
| Level-up visual | Pokémon evolves | User's own AI avatar evolves |
| Mascot | Pokémon | Chosen pet (cat/dog, breed/color variants) |
| Social | No friends/social | Friends via User ID / email, private leaderboard |
| Challenges | None | Exercise challenges with point wagers, next-day results |
| Input validation | None | Per-user physics-based caps, soft + hard validation |
| Gym structure | Flat list | Hierarchical: Strength / Cardio / Flexibility / BW |
| Workout templates | None | Importable famous routines, AI-generated personal routine |
| Yoga | Planned (duration-based) | Difficulty tiers, curated asana sequences |
| Sports | Session logging only | Sport-specific conditioning workouts + auto muscle selection |

---

## 10. Open Design Decisions (unresolved — need input before planning)

| # | Question | Options / Notes |
|---|---|---|
| 1 | Avatar "3D look" vs actual 3D model? | Assumed: stylistic illustration (not rotatable). Confirm. |
| 2 | AI image generation service? | Replicate, fal.ai, DALL-E, Stable Diffusion — cost + quality comparison needed |
| 3 | Fallback if user skips photo? | Default illustrated avatar (no likeness) — still gets level-up body progression |
| 4 | How many avatar level tiers? | Suggested 5–6 breakpoints. Confirm exact level numbers. |
| 5 | Pet XP: same track as user or separate? | Simplest = same track. Separate = richer but more complex. |
| 6 | Challenge wager: fixed or user-chosen amount? | Suggested: fixed tiers (25 / 50 / 100 pts). Confirm. |
| 7 | Challenge result window: 24h or midnight cutoff? | Midnight of challenge day is cleaner. Confirm. |
| 8 | Anti-cheat: soft warn only, or also hard reject? | Current plan: both. Confirm hard-reject threshold source (sports science values). |
| 9 | Famous templates: how many to launch with? | Suggested: 4–6. More can be added via DB without app update. |
| 10 | Sports conditioning workouts: seeded or AI-generated? | Suggested: seeded (curated per sport) for accuracy. AI-generated as a stretch. |

---

## 11. Implementation Notes (for when this enters sprint planning)

- **Avatar system** will require a backend worker (not a frontend API call) for the batch generation job. Plan for a job queue (e.g., Supabase Edge Functions + a queue, or a separate worker service).
- **Friends system** needs a new DB surface: `friendships` table (user_a, user_b, status: pending/accepted), `challenges` table, `challenge_logs` table. This is a significant schema addition.
- **Validation caps** should be stored in DB as a configurable table (not hardcoded in app code), so values can be tuned without a deploy.
- **Sports workout content** can be seeded from the existing `free-exercise-db` dataset filtered by muscle group — no need to build from scratch.
- **Templates** stored in DB as `routine` rows with a `is_template: true` flag + `template_source` name field. Import = clone the routine rows into the user's own account.

---

---

## 12. World Record Caps — Absolute Validation Ceiling

World records are publicly verified and serve as the mathematical hard block for any logged entry. No user can physically exceed these. Store in a DB table (not hardcoded) so values can be updated without a deploy.

| Exercise | Raw / Unequipped World Record | Source / Notes |
|---|---|---|
| Deadlift | 355 kg | Julius Maddox (raw); equipped ~501 kg (Eddie Hall) |
| Bench Press | 203 kg | Julius Maddox (raw); equipped ~335 kg |
| Squat | ~300 kg | Raw, varies by federation |
| Push-ups (1 unbroken set) | Cap at 400 reps | 24h record is ~10,507 but single-set realistic ceiling |
| Pull-ups (1 session) | Cap at 612 | William Faucon's 1-hour record |
| Plank (duration) | 9h 38min | Gino Martino |
| Running (daily distance) | ~100 km | Ultramarathon day cap |

### Three-tier system
- **Green** — plausible for user's body weight + fitness level → saved normally
- **Yellow** — unusually high but not physically impossible → soft warn, user must confirm
- **Red** — exceeds world record OR exceeds the mathematical ceiling for their body weight (e.g., bench press > 3× body weight) → hard block with explanation

Caps table schema:
```
exercise_caps
├── exercise_id (FK or category slug)
├── world_record_value     -- absolute hard ceiling
├── world_record_unit      -- kg | reps | seconds | km
├── yellow_threshold_pct   -- % of world record that triggers soft warn (e.g., 0.4 = 40%)
├── bodyweight_multiplier  -- for weight exercises: hard block at N× user BW
└── updated_at
```

---

## 13. Expert Recommendations (added 2026-06-26)

These are product, technical, and business recommendations from a holistic review of what is built, what is planned, and what the upgrade ideas require.

### 13.1 Onboarding — the most important undesigned screen

Everything downstream — avatar generation, validation caps, AI plan quality, challenge eligibility — depends on accurate user profile data. If the user rushes or guesses here, everything is wrong.

Required onboarding data:
- Height, weight, age
- Fitness level (Beginner / Intermediate / Advanced / Athlete)
- Primary goal (Build muscle / Lose fat / Improve endurance / Sport performance / General health)
- Available equipment (reuse existing gear setup)
- Sport preference (optional — surfaces sports section)
- Photo upload (for avatar — optional but prompted here)

Design principle: make it feel like a **fitness assessment**, not a signup form. Use progress steps, show what each data point unlocks ("Your weight helps us set safe training limits"). Expected completion: 3–4 minutes.

### 13.2 Body Measurement Tracking (biggest missing piece)

Avatar evolution is driven by logged workout data — but there is no way to verify or reflect real physical change without measurement data. Add:
- Monthly log: body weight, waist, chest, arms (bicep), thighs
- Optional: progress photo (stored privately, never shared or used in challenges)
- Chart: measurement trend over time, overlaid with workout volume
- Avatar tie-in: avatar physique tier can also factor in body composition change, not just workout points

This closes the loop between "I'm logging workouts" and "I can see I'm changing."

### 13.3 Progressive Overload Notifications (cheap, high-impact)

The auto-progression engine is in the future roadmap. Before building it fully, surface it as push notifications — low engineering cost, immediate training value.

Logic: if user has logged the same exercise at the same weight × reps for 3+ consecutive sessions → send notification: "You've done 60 kg × 10 reps on bench press 3 sessions in a row. Consider increasing to 62.5 kg next session."

This one notification type is worth more retention-wise than most UI features because it arrives at exactly the right moment.

### 13.4 Streak Shield (borrow from Duolingo)

The existing grace mechanic (1-day late, no points, streak preserved) is correct. Add one layer: a **streak shield** item the user can bank and use.

- Earn 1 shield by completing 7 consecutive workout days
- Shields bank up to a max of 3
- Using a shield on a missed day: streak stays intact, no points, shield consumed
- Shields visible on profile (show how many in reserve)
- Losing a long streak is the #1 drop-off event in fitness apps. This directly addresses it.

### 13.5 Shareable Challenge Cards (virality engine)

When a user wins a challenge, the app generates a shareable image card:
- User's avatar at their current level
- The exercise + their result (e.g., "47 push-ups")
- Their EvoFit level + pet mascot
- EvoFit branding

One tap → share to WhatsApp / Instagram Stories / X.

Implementation: server-side image render (Satori / html-to-image / Cloudinary template) or client-side canvas. Cost is near zero. Value: every card shared is organic marketing. This is how apps grow without a paid ad budget.

### 13.6 Protein Target Only (not full calorie tracking)

Do not build a calorie tracker — that is a different app (Cronometer, MyFitnessPal). But add one nutrition number:

**Daily protein target = body weight (kg) × 1.6 g**

Displayed as a daily checkbox: "Hit my protein target today?" Yes / No.
- Contributes a small point bonus (+5 pts) to stay in the gamification system
- Shown on the daily summary screen alongside workout completion
- No macro tracking, no food database — just the binary question

This delivers 80% of the nutritional value at 5% of the complexity.

### 13.7 Pet Emotional Reactions (make the pet feel alive)

Current plan: pet evolves passively as user levels up. Add event-driven reactions:

| Event | Pet reaction |
|---|---|
| Challenge win | Celebration animation, happy sound |
| Challenge loss | Encouragement animation ("We'll get them next time") |
| Streak milestone (7, 30, 100 days) | Special dance animation |
| Missed workout (streak broken) | Sad animation, brief |
| First workout of the day | Excited greeting |
| New level reached | Evolve animation (same as current plan) |

These are CSS/sprite animations — low engineering cost. The emotional attachment to a responsive digital companion is well-documented for retention (Tamagotchi effect).

### 13.8 Phased Rollout (recommended order)

| Phase | What | Why this order |
|---|---|---|
| Current sprint | Log-to-plan, set logging, plan builder | Foundation — nothing else works without this |
| Phase 2 | Onboarding redesign + user profile (height/weight/age/goal) + world record validation caps | Required input for avatar, challenges, AI quality |
| Phase 3 | Avatar system MVP: 1 activity type, 3 level tiers, batch generation job | Biggest differentiator — ship early to test AI service costs |
| Phase 4 | Pet mascot + emotional reactions + environment backgrounds | Low complexity, high emotional retention |
| Phase 5 | Body measurement tracking + streak shields | Closes the real-progress loop; protects retention |
| Phase 6 | Friends system (User ID / email, private leaderboard) | Needs avatar to exist first for profile cards |
| Phase 7 | Challenge system + wager | Needs friends + 1-month log history gate |
| Phase 8 | Shareable challenge cards + protein target tracker | Growth and virality layer |
| Phase 9 | Sports section + sport-specific workouts | Narrowest audience, most content work — ship last |
| Phase 10 | Workout templates (Bruce Lee etc.) + AI personal template | Best when app has 2–3 months of real user log data |

### 13.9 Business / Monetization Model

**Free tier:** Logging, basic plans, social (friends + leaderboard), basic avatar (no photo — generic illustrated avatar with level-up physique)

**Premium tier:** AI photo avatar (costs real money per user for batch generation), full workout template library, advanced analytics (volume charts, muscle balance, PR history), shareable cards with custom branding, unlimited streak shields

Do NOT gate social behind premium — social features require mass to work, and a paywalled leaderboard has nobody on it.

**Data moat:** Every set logged at this level of granularity (exercise × weight × reps × time) is a training dataset. Over 12+ months of users, this becomes proprietary data no competitor can replicate. It enables: better AI recommendations, aggregate insights ("users who add 5 kg/week to squat see X% injury rate"), and potential B2B plays (gym chains, health insurers, corporate wellness).

---

## 14. Contextual Validation — History + Measurements + Progression Rate

The validation system in `EVOFIT_VALIDATION_SYSTEM.md` covers per-entry checks. This section covers cross-entry, history-aware validation — a smarter second layer.

### 14.1 Training Age Gate (sessions logged)

A person with 20 sessions logged cannot have Advanced-tier numbers. Caps unlock progressively regardless of declared fitness level.

| Sessions logged | Max cap tier |
|---|---|
| 0–20 | Beginner / Novice |
| 20–60 | Intermediate |
| 60–150 | Advanced |
| 150+ with consistent progression | Elite |
| Verified Athlete badge | Elite from day one |

### 14.2 ~~Rate of Progression Check~~ — REMOVED

~~This check was removed from the spec.~~ The rate-of-progression check based on previous log values was an incorrect approach. It flags legitimate scenarios: a user who logs a warm-up weight in session 1 (e.g., 80 kg bench) and their actual working weight in session 2 (e.g., 200 kg) would be wrongly penalised.

**The previous log value is not a reliable indicator of a person's true maximum.** People log warm-up sets, casual sessions, and partial workouts that don't reflect real ability.

**What replaced it:** the absolute bodyweight-plausibility check in `EVOFIT_VALIDATION_SYSTEM.md §5` — this correctly catches entries that are physically impossible for that person's body weight, without generating false positives for warm-up→working-weight progressions.

### 14.3 Body Measurement Correlation (soft signal only)

If a user tracks body measurements (see §15) and measurements show zero change over 3 months while logged weights are jumping significantly → internal analytics flag. Never used as a hard block. Used as a pattern signal for the review queue.

### 14.4 Sudden Return Spike

If user was active, went inactive for 30+ days, and comes back with a logged value significantly higher than their last logged value for that exercise:
- Soft warn: "Welcome back! Your last deadlift was X kg (Y days ago). You just logged Z kg — confirm?"
- Muscle memory allows faster re-gain but not 4× improvements from inactivity.

---

## 15. Sleep Tracking

Sleep is the single highest-impact recovery factor. Add a nightly 2-tap log.

**Log fields:** Hours slept (slider 3–12h) + Sleep quality (1–5 stars)

**What it unlocks:**
- Next-day AI plan adjusts based on sleep: < 6 hours → suggest lighter/recovery session
- Stats insight: "Your PRs tend to happen after 7+ hours of sleep" (visible in progress tab)
- Avatar tie-in: avatar appears visibly tired or energized based on recent 3-day sleep average (cosmetic — toggle-able)
- Validation signal: logging low energy + sleep but a personal record is unusual — soft flag in review analytics

---

## 16. Pre-Workout Energy Check (Mood Log)

2-second emoji selector before each workout session begins.

Options: 😴 Low energy / 😐 Normal / 💪 Feeling strong

**What it unlocks:**
- Pattern analytics ("You always train best on Tuesday evenings at normal+ energy")
- AI recommendation: consistently low-energy logs → suggest deload week
- Validation cross-reference: low energy declared, but personal record logged = soft analytics flag (not a hard block)
- Shown on the workout summary screen: "You felt 💪 today — and it showed."

---

## 17. Injury Log

Voluntary injury reporting. Never mandatory.

**Log flow:** "Any pain or discomfort this session?" → Yes → body area picker → severity 1–5

**What it unlocks:**
- Auto-lowers validation caps for logged muscle groups during flagged period
- If same area reported 3 consecutive sessions: alert "You've reported [area] discomfort 3 sessions in a row — consider a rest day or lighter load"
- Injury history visible on profile (private — not shown on leaderboard)
- Avatar tie-in (optional, toggle): small visual indicator on affected muscle area of avatar

---

## 18. Expanded Streak Types

Current system: one streak (logged a workout). Upgrade to multiple streak tracks running in parallel.

| Streak type | Definition | Reward |
|---|---|---|
| Workout streak | Logged any workout (existing) | Existing points system |
| Consistency streak | Same workout category 3×/week for 4 consecutive weeks | Pet evolution stage + 500 bonus points |
| Improvement streak | Set a PR in 3 consecutive sessions on same exercise | Avatar glow effect cosmetic |
| Challenge streak | Completed 5 challenges this month | Leaderboard badge |
| Clean log streak | No validation flags for 30 days | "Honest Athlete" badge on profile |
| Sleep streak | Logged 7+ hours for 7 consecutive nights | Pet happy animation + 100 pts |

The **Clean Log Streak** is strategically important: it actively rewards honest data, which improves data quality for everyone and creates a positive culture around truthful logging.

---

## 19. Tools / Calculators Hub

Separate `/tools` route. All calculations are client-side math — no backend needed. Build time ~1–2 days for all.

| Tool | Inputs | Formula / Output |
|---|---|---|
| 1RM Calculator | Weight lifted × reps | Epley: weight × (1 + reps/30). Shows estimated 1RM. |
| Plate Calculator | Target weight + bar weight + available plates | Returns exact plate combo per side |
| TDEE Calculator | Height, weight, age, activity level | Mifflin-St Jeor × activity multiplier → daily calories |
| BMI | Height, weight | weight(kg) / height(m)² — with context ("for adults only, doesn't reflect muscle") |
| Protein Target | Body weight | BW (kg) × 1.6g = daily protein target in grams |
| Wilks / DOTS Score | Body weight + total lifted | For powerlifters comparing across weight classes |
| Heart Rate Zones | Age (+ resting HR optional) | 220 − age × zone percentages |

---

## 20. Market Analysis & Download Projections

### 20.1 Competitive Landscape

| App | What they do | Rating | Downloads | EvoFit advantage |
|---|---|---|---|---|
| Hevy | Set/rep logging, social feed | 4.8★ | 1M+ | Avatar, gamification, challenge wagers |
| Strong | Clean set logging | 4.8★ | 5M+ | Social, avatar, gamification |
| Fitbod | AI workout generation | 4.7★ | 5M+ | Social, avatar, challenge system |
| Strava | Running/cycling social | 4.6★ | 100M+ | Weight training depth, gamification |
| MyFitnessPal | Nutrition + basic workout | 4.7★ | 200M+ | Workout depth, gamification, avatar |
| Nike Training Club | Free classes | 4.6★ | 50M+ | Personalization, social challenges |
| Zombies Run! | Running gamification | 4.4★ | 5M+ | Weight training, social, avatar |

**White space EvoFit uniquely owns:**
1. AI-generated personalized avatar that evolves with the user's physique — no competitor
2. Point-wager challenge system between friends — no competitor
3. Full RPG-style progression (levels, pet, avatar, skills, challenges) on weight training — no competitor
4. Per-bodyweight anti-cheat with personality/sarcasm — no competitor

Closest global parallel: Ring Fit Adventure (Nintendo Switch). Sold 17 million copies. Proof that fitness gamification at depth has massive demand.

### 20.2 App Store Rating Prediction

| Timeline | Predicted rating | Driver |
|---|---|---|
| Launch (0–3 months) | 3.8–4.2★ | Early bugs, vocal early adopters, small base |
| 6 months | 4.4–4.6★ | Polished, avatar viral moments drive 5★ reviews |
| 12 months | 4.6–4.8★ | Active challenge community, consistent updates |

The single moment most likely to drive 5★ reviews: the first time a user sees their AI-generated avatar. If the quality is high enough to be recognizably them in cartoon form, that is a shareable, review-worthy moment.

### 20.3 Download Projections (Year 1 / Year 2)

| Scenario | Year 1 | Year 2 | What makes it happen |
|---|---|---|---|
| Quiet launch, organic only | 5,000–20,000 | 15,000–60,000 | Word of mouth alone |
| One viral moment (avatar card on TikTok/Instagram) | 50,000–200,000 | 200,000–500,000 | Single post from one influential user |
| Active social content + ASO optimised | 200,000–500,000 | 500,000–2,000,000 | Consistent content, App Store optimization |
| App Store "New App We Love" feature | 1,000,000+ | 2,000,000–5,000,000 | Apple/Google editorial pick |

**Honest baseline without marketing effort:** 20,000–50,000 year-one downloads is realistic and strong for an indie fitness app. This alone validates the product.

**The organic viral engine:** Shareable challenge cards (user wins a challenge → one-tap to Instagram/WhatsApp with their avatar) is the primary growth loop. Every card shared is a free ad. No paid spend needed if the card is good enough to share.

### 20.4 App Store Optimization (ASO)

| Field | Recommended content |
|---|---|
| App name | EvoFit — Evolve Your Body |
| Subtitle (iOS) | AI Avatar Fitness Tracker |
| First screenshot | Avatar evolution sequence (starter → advanced → elite) |
| Second screenshot | Challenge system with point wager |
| Third screenshot | Private leaderboard with pet mascot |
| Fourth screenshot | Workout logging + validation example |
| Description first line | "The only fitness app where YOU are the character." |
| Keywords to target | fitness gamification, workout avatar, gym tracker RPG, fitness challenge app, AI fitness |

**To get App Store featuring:** Strong UX polish (no crashes, smooth animations), full Privacy Label filled, accessibility basics (Dynamic Type, minimum contrast ratios). The avatar concept is genuinely novel — Apple's editorial team features "delightful" apps.

### 20.5 Positioning Statement

EvoFit sits at the intersection of four markets that have never been combined at this depth:
- **Fitness tracker** (Hevy / Strong territory)
- **Social fitness** (Strava territory)
- **Fitness gamification** (no clear leader — white space)
- **AI personalization** (Fitbod territory)

The gamification angle is the defensible position. Data (workout logs) builds the moat. Avatar and social features drive retention and virality. The validation system builds trust. These compound over time into a product that gets harder to replicate as the user base grows.

---

## 21. Yoga Data Architecture — RAG on Authoritative Sources

### Why generic internet data is wrong for yoga
Yoga alignment is precise and consequential — bad cues can cause injury. Generic sites, Wikipedia, and YouTube descriptions are inconsistent and unvalidated. The app must use authoritative sources.

### Authoritative sources to ingest

| Source | What it covers | Format |
|---|---|---|
| B.K.S. Iyengar — "Light on Yoga" | 200+ asanas, alignment, Sanskrit names, difficulty, therapeutic use, contraindications | PDF / physical book |
| Ray Long — "The Key Muscles of Yoga" | Anatomical breakdown, which muscles work in each pose | PDF |
| Leslie Kaminoff — "Yoga Anatomy" | Similar anatomical depth to Ray Long | PDF |
| Ashtanga Yoga manuals | Strict sequencing rules, Primary / Intermediate / Advanced series | PDF |

Do NOT use: Wikipedia, generic yoga sites, YouTube descriptions — quality is inconsistent and unvalidated.

### Architecture: RAG + curated seed database

Two complementary layers:

**Layer 1 — Seed database (structured, manually validated)**
A `yoga_poses` table of ~80–100 most common asanas, reviewed by a yoga instructor. Handles structured fields the app UI needs:

```sql
yoga_poses
├── id                   -- slug e.g. "warrior-ii"
├── sanskrit_name        -- "Virabhadrasana II"
├── english_name         -- "Warrior II"
├── difficulty           -- beginner | intermediate | advanced
├── hold_seconds         -- 30 | 45 | 60 | 90
├── body_areas[]         -- hips, legs, shoulders, core, etc.
├── primary_muscles[]    -- FK to muscles table
├── therapeutic_uses[]   -- lower back, hip flexors, anxiety, etc.
├── contraindications[]  -- knee injury, high blood pressure, pregnancy, etc.
├── image_url
├── alignment_cue_short  -- one sentence shown in UI during pose
└── source               -- "iyengar" | "ashtanga" | "manual"
```

**Layer 2 — RAG pipeline (flexible, deep knowledge)**
Ingested from authoritative PDFs. Handles: detailed alignment cues, pose-to-pose transitions, sequencing logic, why a specific pose follows another, injury-specific modifications.

```
PDF ingestion pipeline:
PDF (Iyengar, Ray Long, etc.)
  → LlamaParse (handles complex book layouts)
  → Chunk by asana (each pose = one chunk + metadata tags)
  → Embed (Voyage AI or OpenAI text-embedding-3-small)
  → Store in Supabase pgvector (already in stack)

At query time:
User profile (Level + Body focus + Injury flags)
  → Vector search → top 15 relevant pose chunks
  → Claude Haiku assembles: 45-min sequence, alignment cues,
    hold times, transitions, contraindication notes
  → Output saved as plan_day in user's yoga plan
```

**Cost:** One-time PDF processing cost ~$2–5 for entire corpus. Per-sequence generation: Claude Haiku call, negligible cost. No ongoing retraining needed — update by re-ingesting if new sources are added.

### Why not fine-tuning?
Fine-tuning would require thousands of labeled sequence examples, is expensive, and is harder to update. RAG is the correct tool for knowledge retrieval — it pulls from source material at query time rather than baking knowledge into model weights. For a structured domain like yoga instruction, RAG with authoritative sources beats fine-tuning on generic data every time.

---

## 22. Sports Weakness / Injury Prevention Targeting

### The concept
When a user selects a sport, common weak areas for that sport are pre-populated. The user selects which area concerns them → app generates a targeted prehab / strengthening routine.

Example: Football player selects "Ankles" → app generates 3×/week, 20-min ankle stability protocol with exercises, sets, reps, progression.

### Sport × weakness × exercise matrix (seed data)

| Sport | Common weak areas | Priority exercises |
|---|---|---|
| Football / Soccer | Ankles, ACL/knees, hip flexors, hamstrings | Nordic curls, single-leg balance, resistance band ankle work, hip flexor stretch |
| Basketball | Ankles, calves, knees | Ankle stability drills, eccentric calf raises, lateral bounds |
| Swimming | Rotator cuff, shoulder impingement | Band pull-aparts, external rotation, YTW raises |
| Badminton | Wrist, lateral ankle, shoulder | Wrist curls/extensions, balance board, rotator cuff stability |
| Running | IT band, calves, achilles | Hip abductor work, eccentric calf raises, foam roll |
| Tennis | Forearm / elbow, shoulder | Forearm pronation/supination, wrist strengthening, rotator cuff |
| Cycling | Knee (patellofemoral), hip flexors | VMO strengthening, hip flexor stretch, glute activation |
| Cricket | Shoulder, lower back | Rotator cuff stability, thoracic mobility, core anti-rotation |
| Yoga (injury prevention) | Wrists, lower back, hips | Wrist prep, cat-cow, hip openers |

### Data source for deeper accuracy
Physical therapy and sport conditioning literature ingested via the same RAG pipeline as yoga:
- NSCA Sport-Specific Training manuals
- "Functional Rehabilitation in Sports and Musculoskeletal Medicine"
- Sport federation conditioning guides (many publicly available)

For edge cases ("my rotator cuff aches after cricket") the RAG layer handles natural language matching to find the right exercises.

### User flow
1. User selects sport (e.g., Football)
2. Common weak areas shown as chips: Ankles / Knees / Hip flexors / Hamstrings
3. User selects one or more areas
4. Targeted routine generated — exercise, sets, reps, progression, frequency
5. Muscle groups auto-selected in the workout builder (no manual selection needed)
6. Routine can be added to existing plan as a supplementary day

### Muscle groups auto-selection
When a sport + body area is selected, the muscle group picker in the plan builder is pre-populated. The user can adjust but doesn't have to start from scratch. This is a major UX win — sport selection does the configuration work for them.

---

## 23. Analytics, Stats, and dbt Pipeline

### Why dbt
Raw Supabase tables contain transaction-level data. The app needs aggregated, semantic views — weekly volume, recovery state, PR trends, consistency scores. dbt transforms raw tables into these analytics-ready models, making the AI plan generator, avatar progression system, and leaderboard all consume pre-computed, tested, documented mart tables rather than writing complex queries inline.

### Model structure

```
models/
├── staging/               (clean raw tables — rename, cast types, nullability)
│   ├── stg_workout_sets.sql
│   ├── stg_body_measurements.sql
│   ├── stg_sleep_logs.sql
│   ├── stg_mood_logs.sql
│   ├── stg_challenges.sql
│   └── stg_yoga_sessions.sql
│
├── intermediate/          (business logic, joins, derived metrics)
│   ├── int_weekly_volume_by_muscle.sql
│   ├── int_personal_records.sql          -- PR per exercise, auto-detected
│   ├── int_muscle_recovery_state.sql     -- days since last trained per muscle
│   ├── int_consistency_score.sql         -- sessions/week over rolling 4 weeks
│   ├── int_body_composition_trend.sql    -- measurement delta over time
│   └── int_sleep_performance_correlation.sql
│
└── marts/                 (final tables consumed by app + AI agent)
    ├── mart_user_fitness_profile.sql      -- single source of truth per user
    ├── mart_ai_recommendation_inputs.sql  -- feeds the plan generator
    ├── mart_avatar_progression_triggers.sql
    ├── mart_leaderboard.sql
    ├── mart_validation_pattern_flags.sql  -- anti-cheat analytics
    └── mart_sport_readiness_score.sql     -- sport-specific fitness assessment
```

### mart_ai_recommendation_inputs — the "second brain"

This is the most important mart. The AI plan generator reads this instead of raw tables, giving it a cleaned, pre-calculated context window:

```
-- Example output row per user (computed by dbt, refreshed daily or on-demand)
user_id:                     abc123
last_trained_chest:          2 days ago
chest_weekly_volume_kg:      3,200
bench_pr_trend:              improving (+2.5 kg/week, 4 consecutive weeks)
sleep_avg_7d:                6.2 hours         ← low
mood_avg_7d:                 3.1 / 5           ← moderate
consistency_score:           78 / 100
overtraining_flag:           false
deload_recommended:          true              ← high volume + low sleep
muscle_recovery_state:       {chest: fatigued, back: fresh, legs: fresh}
sport_focus:                 football
ankle_conditioning_streak:   3 weeks
```

The AI reads this mart → recommendations are grounded in actual user state, not generic templates.

### Prediction features (rule-based, no ML model needed)

All predictions are deterministic calculations on dbt mart outputs. No machine learning required.

| Prediction | Rule logic |
|---|---|
| "You could hit 100 kg bench in ~6 weeks" | Linear extrapolation of PR trajectory over last 8 sessions |
| "Signs of overtraining — consider a deload" | Volume in top 20% + sleep < 6h for 5+ days + mood < 2.5 for 3+ days |
| "Push/pull ratio is imbalanced" | Pushing volume > 2× pulling volume in last 4 weeks |
| "Ready for next avatar tier in ~12 days" | (Points to next level) ÷ (avg daily points, 14-day rolling) |
| "Ankle conditioning improved 18% this month" | Progressive overload metric on ankle exercises, 30-day delta |
| "Your best performance days are Tuesday evenings" | Correlation of mood=high + time-of-day + PR rate |
| "Chest hasn't recovered — skip pressing today" | last_trained_chest < 48h + volume > threshold |

The AI agent is used only for **natural language framing** of these predictions ("Here's why we're suggesting a lighter week..."). The prediction itself is the dbt calculation.

### dbt tests to add from day one

Every mart table should have:
- `not_null` tests on key columns
- `unique` tests on grain (user_id + date)
- `accepted_values` on enums
- Custom test: `consistency_score` must be between 0 and 100
- Custom test: `overtraining_flag` cannot be true for more than 14 consecutive days without a deload recommendation

Tests run on every dbt build, blocking bad data from reaching the app.

### Refresh cadence

| Model tier | Refresh trigger |
|---|---|
| Staging | On every new row insert (near real-time via Supabase triggers) |
| Intermediate | Daily (scheduled dbt run) |
| Marts | Daily + on-demand when user opens their stats screen |
| mart_leaderboard | Every 6 hours (or on challenge result submission) |

---

## 24. Multi-Agent Architecture

EvoFit's AI layer is a system of specialized agents, each with a narrow domain, coordinated by a lightweight orchestrator. This is the correct architecture for a portfolio piece that showcases full-stack AI engineering — not a single chatbot, but a properly designed agent system.

### 24.1 The Four Agents

**Agent 1 — Yoga Sequence Agent**
- Domain: generates personalized yoga sequences from authoritative RAG sources
- Reads: pgvector RAG (Iyengar / Ray Long PDFs) + yoga_poses seed table + user injury profile
- Writes: plan_days (yoga sessions) in Supabase
- Optional async trigger: Image Agent for pose illustrations
- Key capability: sequences poses with correct warm-up → peak → cooldown structure, respects injury contraindications, matches hold times to session duration

**Agent 2 — Gym Workout Agent**
- Domain: generates personalized gym sessions based on actual recovery state
- Reads: `mart_ai_recommendation_inputs` (dbt) + exercises table (free-exercise-db) + muscle recovery mart
- Writes: plan_days (gym sessions) in Supabase
- Key capability: knows chest is still fatigued from 2 days ago, doesn't programme chest again — this is what separates it from a generic template

**Agent 3 — Avatar Generation Agent**
- Domain: one-time batch image generation triggered by photo upload
- Reads: user photo from Supabase Storage + user stats
- Calls: Replicate / fal.ai API (InstantID + FLUX.1)
- Writes: avatar_variants table (30 pre-rendered images: 5 level tiers × 6 activity types)
- Runs: as a background job — not synchronous with the UI. Notifies user on completion.

**Agent 4 — Sports Conditioning Agent**
- Domain: sport-specific prehab / weakness targeting
- Reads: pgvector RAG (NSCA / PT literature) + sport_weakness seed table + user sport profile
- Writes: supplementary conditioning plan_days
- Key capability: "I play football and my ankles feel weak" → generates targeted ankle stability protocol

### 24.2 Orchestrator

A lightweight routing function — not a smart agent itself. Classifies intent and dispatches to the correct specialist:

```
User action / system trigger
        ↓
Orchestrator (Supabase Edge Function)
  intent: "request yoga plan"       → Yoga Agent
  intent: "request gym workout"     → Gym Agent
  intent: "photo uploaded"          → Avatar Agent (async, background)
  intent: "sport weakness report"   → Sports Agent
  intent: "general question"        → Direct LLM (no agent)
```

### 24.3 Image Model Stack for Avatar Agent

| Model | Role | Why |
|---|---|---|
| InstantID (via Replicate) | Face identity preservation across all variants | Best consistency — same face whether in gym kit or yoga pose |
| FLUX.1 | Base image quality | Current best open-source generation quality |
| ControlNet (optional) | Pose control for physique evolution variants | Useful for controlling body shape changes per level tier |

**Prompt pattern per variant:**
```
"cartoon character, [activity_type], athletic build, [physique_descriptor_for_level],
 [activity-specific clothing and setting], consistent face from reference image,
 stylized illustration, fitness app character"
```

Physique descriptors by level tier:
- Starter: "lean athletic build, natural proportions"
- Lean: "visibly fit, slight muscle definition"
- Defined: "clear muscle definition, athletic shoulders"
- Athletic: "pronounced biceps and chest, strong legs"
- Elite: "highly muscular, peak athletic physique"

**Cost:** ~$0.05–0.15 per image on Replicate. Full batch of 30 images = $2–5 per user. This is the direct cost that justifies the premium tier.

### 24.4 Technology Stack

| Technology | Used for | CV label |
|---|---|---|
| Claude API + tool use | Yoga and Gym agents | "Multi-agent system using Anthropic Claude API with structured tool use" |
| LlamaIndex | RAG ingestion pipeline (yoga + PT PDFs) | "RAG pipeline on domain-specific literature — LlamaIndex + Supabase pgvector" |
| Supabase pgvector | Vector store, no new infrastructure | "Vector search integrated in existing Supabase stack" |
| Replicate API | Avatar image generation calls | "Image generation pipeline — InstantID + FLUX.1 via Replicate" |
| dbt Core | Transformation models (staging → intermediate → marts) | "dbt data modeling — semantic layer on Supabase Postgres" |
| Supabase Edge Functions | Agent backends (serverless, no separate infra) | "Serverless AI agent backends on Supabase Edge Functions" |
| GitHub Actions | dbt scheduling + CI/CD | "dbt scheduling and CI/CD via GitHub Actions" |
| LangGraph (optional) | Orchestrator with explicit state graph | "Multi-agent orchestration with LangGraph" |

### 24.5 Recommended Learning Order

Build in this order — each step teaches a new layer without overloading:

1. **Gym Agent first** — only needs Claude tool use + dbt mart. No RAG, no images. Get comfortable with structured tool use in a real product context.
2. **dbt models in parallel** — build staging → intermediate → mart_ai_recommendation_inputs alongside step 1. The Gym Agent consumes this immediately.
3. **RAG pipeline + Yoga Agent** — you'll set up pgvector for the yoga seed DB anyway. Add the LlamaIndex ingestion on top of that.
4. **Avatar Agent last** — image generation APIs are straightforward once the agent pattern is familiar. The batch job pattern (trigger → queue → process → notify) is a clean isolated skill to add.

### 24.6 Portfolio Positioning Statement

This project demonstrates:
- **Multi-agent system design** — specialized agents with clear domain boundaries, a routing orchestrator, tool use pattern
- **RAG on domain-specific knowledge** — authoritative PDFs (not generic internet data), chunked by entity, stored in pgvector, retrieved at query time
- **Data engineering driving AI quality** — agents read from dbt semantic marts, not raw tables; the AI is only as good as the data layer behind it
- **Image generation pipeline** — practical application of generative image AI in a product context (not a demo, a shipped feature)
- **Full-stack delivery** — React frontend → Supabase Edge Function agents → dbt + Postgres analytics layer → external AI APIs (Claude, Replicate)

One-sentence version: *"I designed a multi-agent fitness AI where specialized agents for yoga, workouts, and avatar generation each read from a dbt semantic layer and a RAG knowledge base, making recommendations grounded in both authoritative domain knowledge and the user's actual training history."*

---

## 25. Cost-Conscious Architecture — Options Per Decision

Every AI/infra decision has multiple paths. This section documents the options, costs, and recommendation for each so the build can scale from zero-cost development to paid production without a rewrite.

### 25.1 Agent LLM

| Option | Cost | Quality | Use when |
|---|---|---|---|
| Claude Haiku | ~$0.002/call | Best for structured tool use | Production, premium users |
| Groq + Llama 3.1 70B | Free (14,400 req/day free tier) | Very good | Development + free-tier users |
| **Hybrid (Groq free, Claude premium)** | Near zero until scale | Best of both | **Recommended** |
| OpenAI GPT-4o-mini | ~$0.002/call | Good | Alternative for portfolio breadth |

Hybrid approach: Groq handles all development and free-tier agent calls. Claude Haiku handles premium users. Shows multi-provider architecture on CV — stronger than being locked to one vendor.

### 25.2 RAG Embeddings (one-time ingestion cost)

| Option | Cost | Quality | Notes |
|---|---|---|---|
| **Local sentence-transformers** | $0 | Good | Run Python script once, store in pgvector, never pay again |
| OpenAI text-embedding-3-small | ~$2 total for full corpus | Excellent | Cheap, but creates API dependency |
| Voyage AI | ~$2 total | Best for technical/instructional content | Best quality for yoga/PT literature |

**Recommendation: local sentence-transformers.** Runs once as a Python ingestion script, stores permanently in pgvector, no ongoing cost or API dependency. For a yoga + PT corpus (a few hundred pages), the quality difference from OpenAI is negligible. Stronger portfolio signal — shows you can build RAG without full API dependency.

### 25.3 Avatar Image Generation

| Option | Cost | Quality | Notes |
|---|---|---|---|
| Replicate (InstantID + FLUX.1) | $2–5/user one-time | Best | Gate behind premium |
| fal.ai | Similar to Replicate | Very good | Slightly faster |
| Hugging Face Inference Endpoints | $0.06/hr only when active | Good | Spin up for batch, shut down after |
| **Skip for MVP — illustrated placeholder** | $0 | N/A | **Recommended for v1** |

**Recommendation: skip avatar photo generation for MVP.** The placeholder illustrated avatar still evolves with level and activity type. When paying users exist, add photo avatar as a premium feature. Cost ($2–5/user) is then covered by subscription revenue. Prevents cost risk before revenue.

### 25.4 Push Notifications

| Option | Cost | Platform | Notes |
|---|---|---|---|
| **OneSignal** | Free up to 10,000 subscribers | Web + mobile | **Recommended** — easiest React integration |
| Web Push API | $0 always | Web/PWA | Native browser, no third party |
| Firebase FCM | Free tier generous | Web + mobile | More setup, Google dependency |

### 25.5 Mobile Distribution

| Option | Effort | Cost | App Store presence |
|---|---|---|---|
| **PWA (Progressive Web App)** | Low — manifest + service worker | $0 | Installable from browser, not App Store |
| Capacitor | Medium — wraps existing React app | Apple: $99/yr, Google: $25 one-time | Full App Store + Play Store |
| React Native rewrite | High — different codebase | Same store fees | Best native experience |

**Recommendation: PWA first, Capacitor later.** Add PWA manifest today — existing React app becomes installable from browser with almost no work. When ready for App Store (Phase 6–8), Capacitor wraps existing React/TypeScript code with no rewrite. React Native only if deep native hardware access is needed later.

---

## 26. Missing Pieces (gaps in current plan)

Five areas with no coverage in previous sections:

### 26.1 Offline Support (critical)

Gyms have poor signal. If logging requires internet, expect 1-star reviews. Users need to log sets in a metal building basement.

**Solution:** Service worker + IndexedDB via Workbox.
- Write operations (log workout, complete set) go to IndexedDB first
- Sync to Supabase when connection restores
- Conflict resolution: last-write-wins for log entries (simple, correct for this use case)
- Read operations: recent plans and exercises cached in IndexedDB on last successful load

This is a PWA feature — fits naturally with the PWA distribution recommendation above.

### 26.2 Push Notification Design

Concept is mentioned in §13.3 (progressive overload notifications) but never fully specified.

Key notification events and copy:

| Trigger | Message |
|---|---|
| Challenge result (next day after close) | "Result's in — you won! +100 pts 🏆" or "Tough one. Rematch?" |
| Streak reminder (8pm if no log yet) | "You haven't logged today — [pet name] is waiting" |
| Progressive overload ready | "3 sessions at 60kg × 10 bench — try 62.5kg next?" |
| Avatar generation complete | "Your EvoFit avatar is ready — check it out 🎉" |
| Incoming challenge | "[Username] challenged you to max pull-ups. Accept?" |
| Friend joined app | "[Username] joined EvoFit. Challenge them?" |

**Implementation:** OneSignal React SDK. Notification preferences user-configurable (opt in/out per type).

### 26.3 Onboarding Flow (still undesigned)

Mentioned multiple times as the most important screen in the app. Still has no screen-by-screen design.

Everything downstream depends on onboarding data: avatar quality, validation caps, AI recommendation quality, challenge eligibility. Bad data here = bad experience everywhere.

Needs to be a dedicated sprint item before any AI feature ships. Minimum screens:
1. Welcome + value proposition (avatar evolution shown)
2. Basic stats: height, weight, age, sex
3. Fitness level + primary goal
4. Equipment available (reuse existing gear setup)
5. Sport preference (optional)
6. Photo upload (optional — for avatar; can be done later)
7. First plan suggestion based on inputs

### 26.4 Product Analytics

The dbt pipeline covers fitness data analytics. Product analytics (which features are used, where users drop off, funnel analysis) is a separate need.

**Tool: Posthog** — free up to 1M events/month.
- Track: onboarding completion rate, which agent features are used, challenge acceptance rate, avatar generation trigger rate
- Funnel: does the user who completes onboarding → log first workout → return day 7?
- Retention cohorts: do challenge users retain better than solo users?

This data tells you whether the yoga RAG feature is worth building before you build it.

### 26.5 Photo Privacy + Content Moderation

User-uploaded photos for avatar generation are sensitive data. Two requirements:

**Privacy (GDPR-relevant):**
- Explicit consent checkbox at photo upload: "I agree my photo will be processed by an AI image service to generate an avatar"
- Right to deletion: one-tap delete removes the original photo + all generated avatar images from Supabase Storage
- Data residency: Supabase storage region should match user's region if EU users are expected

**Content moderation:**
- Reject non-face photos before sending to Replicate (saves cost + prevents misuse)
- Tool: AWS Rekognition free tier (5,000 images/month) — checks for face presence and content safety
- If no face detected: "We need a clear face photo to generate your avatar — try again"
- If content flagged: silent reject, log for review

---

## 27. Security Architecture

Security is designed in from the start, not added after. These are the non-negotiable requirements before any feature ships publicly.

### 27.1 Anti-Fragmentation Principle

The plan has 26 sections. The three things that drive installs and retention are:
1. **Avatar evolution** — unique differentiator, the reason to download
2. **Challenge system** — virality engine, the reason to share
3. **Clean workout logging** — retention foundation, the reason to return

Everything else deepens the app after someone is retained. Build these three first, securely.

### 27.2 Row Level Security (RLS) — most critical

Every Supabase table must have RLS enabled before any user data is stored. Without it, any authenticated user can read or write any other user's data.

Policy checklist:

| Table | Read policy | Write policy |
|---|---|---|
| `logged_exercises` | `auth.uid() = user_id` | `auth.uid() = user_id` |
| `workout_sets` | `auth.uid() = user_id` | `auth.uid() = user_id` |
| `body_measurements` | `auth.uid() = user_id` | `auth.uid() = user_id` |
| `challenges` | `auth.uid() IN (challenger_id, challenged_id)` | Challenger only (create) |
| `challenge_logs` | Both participants | Log owner only |
| `friends` | Both parties | Either (on create) |
| `avatar_variants` | Owner only | Edge Function service role only |
| `validation_flags` | Owner only | Edge Function service role only |
| `yoga_poses` (seed) | All authenticated | Admin only |
| `exercises` (seed) | All authenticated | Admin only |
| `leaderboard` (view) | All authenticated | Read-only view |

### 27.3 Secrets Management

| Secret | Stored in | Never in |
|---|---|---|
| Supabase service role key | Edge Function env (`supabase secrets set`) | Frontend, git |
| Claude API key | Edge Function env | Frontend, git |
| Replicate / fal.ai key | Edge Function env | Frontend, git |
| Groq API key | Edge Function env | Frontend, git |
| dbt DB connection string | GitHub Actions encrypted secret | `dbt_project.yml`, git |
| Supabase anon key | Frontend only (safe — RLS protects it) | Git (use `.env.local`) |

Rule: if a secret would allow writing data or calling a paid API, it lives in Edge Functions only, never in the React bundle.

### 27.4 Challenge Point Transfers — Atomic Transactions

Points must transfer in a single database transaction. Two separate API calls with a network failure between them = free points exploit.

```sql
CREATE OR REPLACE FUNCTION resolve_challenge(
  p_challenge_id uuid,
  p_winner_id uuid,
  p_loser_id uuid,
  p_wager_points int
) RETURNS void AS $$
BEGIN
  -- Verify loser has sufficient points
  IF (SELECT points FROM profiles WHERE id = p_loser_id) < p_wager_points THEN
    RAISE EXCEPTION 'Insufficient points';
  END IF;
  UPDATE profiles SET points = points - p_wager_points WHERE id = p_loser_id;
  UPDATE profiles SET points = points + p_wager_points WHERE id = p_winner_id;
  UPDATE challenges SET status = 'resolved', winner_id = p_winner_id WHERE id = p_challenge_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

`SECURITY DEFINER` ensures this runs with admin privileges — cannot be tampered with from the client.

### 27.5 AI Agent Rate Limiting

Unthrottled agent calls = cost attack risk. Every Edge Function calling an external AI API must rate-limit per user:

```typescript
// Check calls in last 60 seconds before calling AI
const { count } = await supabase
  .from('agent_call_log')
  .select('*', { count: 'exact' })
  .eq('user_id', userId)
  .eq('agent_type', agentType)
  .gte('created_at', new Date(Date.now() - 60000).toISOString());

if (count >= RATE_LIMIT) {
  return new Response('Rate limit exceeded', { status: 429 });
}
```

Per-user rate limits:
- Workout generation: 5 calls/minute
- Yoga sequence: 5 calls/minute
- Avatar generation: 1 per user ever (idempotent — re-trigger only if previous job failed)

### 27.6 File Upload Security

Photo uploads before any processing:
- Max size: 5 MB
- Allowed MIME types: `image/jpeg`, `image/png`, `image/webp` only — reject all others
- Supabase Storage bucket: **private** (not public) — access via signed URLs only, time-limited
- One photo per user — new upload replaces previous (storage doesn't accumulate)
- Content moderation check (AWS Rekognition free tier: 5,000 images/month) before sending to Replicate

### 27.7 Input Sanitization — Social Fields

All user-supplied text:
- Display names: strip HTML, max 30 chars, alphanumeric + spaces only
- User tag: enforced format `EvoFit#[0-9]{4,8}` — regex validate at insert, reject anything else
- Challenge notes: max 200 chars, strip HTML, no markdown rendered
- Supabase PostgREST uses parameterized queries natively — SQL injection handled at the DB layer, but validate at application layer too

### 27.8 Leaderboard Privacy

Leaderboard view must never expose email, real name, or original photo:

```sql
CREATE VIEW public_leaderboard AS
SELECT
  nickname,                    -- user-chosen display name only
  user_tag,                    -- EvoFit#1234
  total_points,
  current_level,
  avatar_thumbnail_url         -- generated avatar only, never original photo URL
FROM profiles
WHERE leaderboard_opt_in = true
ORDER BY total_points DESC;
```

### 27.9 GDPR / Privacy Minimums

Required before any EU users:
- Explicit consent checkbox at photo upload (text: "This photo will be processed by an AI image service")
- One-tap account deletion: removes all user data, workout logs, body measurements, original photo, generated avatars from Supabase Storage
- Privacy policy linked from onboarding and settings
- Data export on request (Supabase makes this straightforward via a single user_id query)

---

## 28. dbt Pipeline — Data Engineering Layer

This is the layer that separates EvoFit from every other fitness app. Agents read pre-computed semantic marts, not raw tables.

### 28.1 Priority Build Order

Build in this sequence — each model feeds the next:

**1. `stg_workout_sets`** — foundation of everything
Clean, typed staging of `workout_exercise_sets`. Add `is_valid` flag from the validation system. This is the single source of truth for all downstream analytics.

**2. `int_personal_records`** — drives in-app notifications and avatar triggers
```sql
SELECT
  user_id,
  exercise_id,
  MAX(weight_kg)                              AS pr_weight,
  MAX(reps)                                   AS pr_reps,
  MAX(weight_kg * (1 + reps / 30.0))         AS pr_estimated_1rm  -- Epley formula
FROM stg_workout_sets
WHERE is_valid = true
GROUP BY user_id, exercise_id
```

**3. `int_muscle_recovery_state`** — the Gym Agent reads this before every recommendation
```sql
SELECT
  user_id,
  muscle,
  MAX(logged_at)                                          AS last_trained_at,
  CURRENT_DATE - MAX(logged_at::date)                    AS days_since_trained,
  CASE
    WHEN CURRENT_DATE - MAX(logged_at::date) < 2 THEN 'fatigued'
    WHEN CURRENT_DATE - MAX(logged_at::date) < 4 THEN 'recovering'
    ELSE 'fresh'
  END                                                     AS recovery_state
FROM stg_workout_sets
JOIN exercise_muscles USING (exercise_id)
GROUP BY user_id, muscle
```

**4. `mart_ai_recommendation_inputs`** — one row per user, everything the AI agent needs
Pre-aggregates recovery state, volume history, PR trajectory, sleep average, mood average, overtraining flag. Agent reads this single row instead of joining 6 tables — shorter prompt, faster, cheaper.

**5. `mart_validation_pattern_flags`** — anti-cheat analytics
Identifies users with repeated validation flags across a rolling window. Not for real-time blocking (Edge Function handles that) — for pattern analysis and manual review queue prioritization.

### 28.2 dbt Tests as Data Quality Layer

dbt tests applied to fitness data = data engineering mindset in a product context:

```yaml
# models/staging/stg_workout_sets.yml
models:
  - name: stg_workout_sets
    columns:
      - name: weight_kg
        tests:
          - not_null
          - dbt_utils.accepted_range:
              min_value: 0
              max_value: 500         # world record absolute ceiling
      - name: reps
        tests:
          - dbt_utils.accepted_range:
              min_value: 1
              max_value: 500
      - name: user_id
        tests:
          - not_null
          - relationships:
              to: ref('stg_profiles')
              field: id
      - name: is_valid
        tests:
          - not_null
          - accepted_values:
              values: [true, false]
```

Tests run on every dbt build. Bad data caught at pipeline level — two independent layers of validation (Edge Function at write time, dbt test at pipeline time).

### 28.3 Scheduling — GitHub Actions (free)

```yaml
# .github/workflows/dbt_run.yml
name: dbt daily run
on:
  schedule:
    - cron: '0 2 * * *'      # 2am daily, after overnight user activity
  workflow_dispatch:           # manual trigger for testing
jobs:
  dbt:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: pip install dbt-postgres
      - run: dbt run --target prod
      - run: dbt test --target prod
        env:
          SUPABASE_DB_URL: ${{ secrets.SUPABASE_DB_URL }}
```

No dbt Cloud subscription needed. GitHub Actions free tier (2,000 min/month) is more than sufficient for a daily dbt run.

### 28.4 Portfolio Signal

The dbt layer is the data engineering contribution that distinguishes this from a standard React + Supabase app. The narrative: *"I designed a semantic transformation layer where AI agents read pre-computed, tested mart tables rather than raw transactional data — the same pattern used in enterprise data platforms, applied to a consumer product."*

*End of document. Continue adding ideas in new sections below as they come up.*
