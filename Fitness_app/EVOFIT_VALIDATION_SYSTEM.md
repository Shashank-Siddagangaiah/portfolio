# EvoFit — Input Validation & Anti-Spam System
Captured: 2026-06-26 | Status: Design spec — not yet in sprint
Cross-reference: EVOFIT_MAJOR_UPGRADES_PLAN.md §5, §12

This document is the full design spec for validating workout log entries.
The goal: make it impossible to post fake numbers while never punishing a legitimate user.

---

## 1. Why This Matters

Without validation:
- A user logs 500 kg deadlift on day one → tops the leaderboard
- A user wins every challenge by entering impossible numbers
- The entire points/challenge/leaderboard system is meaningless

With bad validation:
- Legitimate advanced users get blocked
- Frustrating UX, bad reviews

The system must be **smart, fair, and have personality** — not a cold "Entry rejected."

---

## 2. Core Philosophy — Physics First, Never Punish

**The system questions the absolute value of an entry, not the jump from the previous log.**

This is the most important design principle. People log warm-up sets, casual sessions, and test entries that don't represent their real ability. A person who logged 80 kg bench in week 1 (a warm-up) and logs 200 kg in week 2 (their actual working weight) has done nothing wrong — and the system must not treat them as suspicious.

**What the previous log IS used for:** nothing, for validation purposes. It is used only for personal PR tracking and charts.

**What IS used for validation:** the absolute value of the new entry checked against the physics of what a human at their body weight can achieve.

### Three outcomes — no more, no less

| Zone | Condition | Result |
|---|---|---|
| **Green** | Within physical range for their BW and fitness level | Silent save — zero interruption |
| **Yellow** | Physically possible but Elite/World-class for their BW | Soft confirm — saved either way, entry marked "self-reported" |
| **Red** | Exceeds world record or mathematical ceiling | Sarcastic message + appeal — not saved until reviewed |

A **Yellow entry is always saved** to the user's personal log. It counts fully toward personal stats, PR history, volume charts, and avatar evolution points. The only restriction is on the competitive layer (challenges, leaderboard) — shown as "self-reported" there until one easy verification step is done (see §8.4).

**The user should never feel policed. They should feel the app is curious, not suspicious.**

---

## 3. How the Validation System Works (Overview)

Every logged entry goes through two filters in sequence:

```
Entry submitted
      │
      ▼
[Filter 1] Format & sanity check
(negative numbers, non-numeric, >24h duration, etc.)
      │
      ▼
[Filter 2] Absolute physical plausibility check
(based on their bodyweight — NOT their previous log)
      │ GREEN → save silently
      │ YELLOW → soft confirm, save either way, mark self-reported
      │ RED → world record zone, sarcastic response + appeal
      ▼
Entry saved ✓ (Green and Yellow)
Entry held ✗ (Red — pending appeal)
```

All validation logic is **server-side** (not just client-side). Clients can be modified; the server cannot be bypassed.

**Removed from earlier versions of this spec:** rate-of-progression check based on previous log values. This was removed because it incorrectly flags legitimate warm-up→working-weight progressions (e.g., 80 kg bench in week 1 as a warm-up, 200 kg in week 2 as true working weight). The absolute physical plausibility check covers the real problem cases without this false positive.

---

## 3. User Profile Inputs Used for Validation

Collected at onboarding (required before first log):

| Input | Why needed |
|---|---|
| Body weight (kg) | Scales all weight-based caps |
| Height (cm) | BMI cross-check, injury risk flag for extreme loads |
| Age | Masters adjustment (see §7) |
| Sex (male / female / prefer not to say) | Separate strength standards (see §6) |
| Fitness level (Beginner / Intermediate / Advanced / Athlete) | Sets initial realistic cap tier |
| Any injuries / conditions | Lowers cap for affected muscle groups |

**Caps auto-update as the user logs consistently.** A user who has logged 3 months of deadlift data at increasing weights gets a progressively higher realistic cap — their history is proof.

---

## 4. Filter 1 — Format & Sanity Checks (Always Applied)

These block entries that are mathematically impossible regardless of who is doing them:

| Check | Rule |
|---|---|
| Negative values | Block any negative weight, reps, duration |
| Zero reps logged | Block — 0 reps means no workout |
| Reps > 10,000 in a single set | Block — physically impossible in one set |
| Weight entries with letters / symbols | Block — must be numeric |
| Duration > 24 hours | Block — a single session cannot exceed one day |
| Distance > 400 km in one session | Block — running/cycling absolute impossibility |
| Rest time > 60 minutes per set | Soft warn — unusual but possible in powerlifting |
| Sets > 100 in one workout | Block — not a single workout session |
| Exercises > 30 in one workout | Soft warn — unusual, prompt to confirm |

---

## 5. Filter 2 — Per-User Realistic Cap (Bodyweight-Scaled)

### 5.1 Strength Exercises (Barbell / Dumbbell)

Standards sourced from Strength Level, Legion Athletics, Barbell Medicine, and Symmetric Strength.
These are the multipliers of **body weight** that define each tier.

#### DEADLIFT — Men

| Fitness Tier | BW Multiplier | Example: 60 kg person | Example: 90 kg person |
|---|---|---|---|
| Beginner | 1.0x | 60 kg | 90 kg |
| Novice | 1.55x | 93 kg | 139 kg |
| Intermediate | 1.85x | 111 kg | 166 kg |
| Advanced | 2.25x | 135 kg | 202 kg |
| Elite | 2.75x | 165 kg | 247 kg |
| World-class | 3.5x | 210 kg | 315 kg |
| **Yellow warn zone** | **> 3.5x** | **> 210 kg** | **> 315 kg** |
| **Hard block (pre-WR)** | **> 4.5x** | **> 270 kg** | **> 405 kg** |

#### DEADLIFT — Women

| Fitness Tier | BW Multiplier | Example: 60 kg person |
|---|---|---|
| Beginner | 0.8x | 48 kg |
| Novice | 1.1x | 66 kg |
| Intermediate | 1.35x | 81 kg |
| Advanced | 1.75x | 105 kg |
| Elite | 2.1x | 126 kg |
| World-class | 2.6x | 156 kg |
| **Yellow warn zone** | **> 2.6x** | **> 156 kg** |
| **Hard block (pre-WR)** | **> 3.5x** | **> 210 kg** |

#### BENCH PRESS — Men

| Fitness Tier | BW Multiplier | Example: 60 kg | Example: 90 kg |
|---|---|---|---|
| Beginner | 0.5x | 30 kg | 45 kg |
| Novice | 0.8x | 48 kg | 72 kg |
| Intermediate | 1.0x | 60 kg | 90 kg |
| Advanced | 1.25x | 75 kg | 112 kg |
| Elite | 1.5x | 90 kg | 135 kg |
| World-class | 1.75x | 105 kg | 157 kg |
| **Yellow warn zone** | **> 1.75x** | **> 105 kg** | **> 157 kg** |
| **Hard block (pre-WR)** | **> 2.5x** | **> 150 kg** | **> 225 kg** |

#### BENCH PRESS — Women

| Fitness Tier | BW Multiplier | Example: 60 kg |
|---|---|---|
| Beginner | 0.3x | 18 kg |
| Novice | 0.45x | 27 kg |
| Intermediate | 0.65x | 39 kg |
| Advanced | 0.85x | 51 kg |
| Elite | 1.0x | 60 kg |
| World-class | 1.2x | 72 kg |
| **Yellow warn zone** | **> 1.2x** | **> 72 kg** |
| **Hard block (pre-WR)** | **> 1.8x** | **> 108 kg** |

#### SQUAT — Men

| Fitness Tier | BW Multiplier | Example: 60 kg | Example: 90 kg |
|---|---|---|---|
| Beginner | 0.75x | 45 kg | 67 kg |
| Novice | 1.1x | 66 kg | 99 kg |
| Intermediate | 1.5x | 90 kg | 135 kg |
| Advanced | 2.0x | 120 kg | 180 kg |
| Elite | 2.5x | 150 kg | 225 kg |
| World-class | 3.0x | 180 kg | 270 kg |
| **Yellow warn zone** | **> 3.0x** | **> 180 kg** | **> 270 kg** |
| **Hard block (pre-WR)** | **> 4.0x** | **> 240 kg** | **> 360 kg** |

#### SQUAT — Women

| Fitness Tier | BW Multiplier | Example: 60 kg |
|---|---|---|
| Beginner | 0.6x | 36 kg |
| Novice | 0.85x | 51 kg |
| Intermediate | 1.15x | 69 kg |
| Advanced | 1.5x | 90 kg |
| Elite | 1.9x | 114 kg |
| World-class | 2.3x | 138 kg |
| **Yellow warn zone** | **> 2.3x** | **> 138 kg** |
| **Hard block (pre-WR)** | **> 3.2x** | **> 192 kg** |

#### OVERHEAD PRESS — Men

| Fitness Tier | BW Multiplier | Example: 60 kg | Example: 90 kg |
|---|---|---|---|
| Beginner | 0.35x | 21 kg | 31 kg |
| Novice | 0.55x | 33 kg | 49 kg |
| Intermediate | 0.7x | 42 kg | 63 kg |
| Advanced | 0.85x | 51 kg | 76 kg |
| Elite | 1.0x | 60 kg | 90 kg |
| World-class | 1.2x | 72 kg | 108 kg |
| **Yellow warn zone** | **> 1.2x** | **> 72 kg** | **> 108 kg** |
| **Hard block (pre-WR)** | **> 1.6x** | **> 96 kg** | **> 144 kg** |

#### OVERHEAD PRESS — Women

| Fitness Tier | BW Multiplier | Example: 60 kg |
|---|---|---|
| Beginner | 0.2x | 12 kg |
| Novice | 0.3x | 18 kg |
| Intermediate | 0.4x | 24 kg |
| Advanced | 0.55x | 33 kg |
| Elite | 0.7x | 42 kg |
| World-class | 0.85x | 51 kg |
| **Yellow warn zone** | **> 0.85x** | **> 51 kg** |
| **Hard block (pre-WR)** | **> 1.2x** | **> 72 kg** |

---

### 5.2 Bodyweight Exercises (Reps per Set)

Single unbroken set caps. Not per-day, not per-session — per individual set entry.

| Exercise | Beginner cap | Intermediate cap | Advanced cap | Elite cap | World-class cap | Yellow zone | Hard block |
|---|---|---|---|---|---|---|---|
| Push-ups | 30 | 60 | 100 | 150 | 200 | > 200 | > 400 |
| Pull-ups / Chin-ups | 10 | 20 | 35 | 50 | 70 | > 70 | > 150 |
| Dips | 15 | 30 | 50 | 70 | 100 | > 100 | > 200 |
| Sit-ups (per set) | 30 | 60 | 100 | 140 | 175 | > 175 | > 300 |
| Burpees (per set) | 20 | 40 | 60 | 80 | 100 | > 100 | > 200 |
| Jumping jacks (per set) | 50 | 100 | 150 | 200 | 250 | > 250 | > 500 |
| Muscle-ups | 2 | 8 | 15 | 25 | 35 | > 35 | > 50 |
| Pistol squats | 5 | 15 | 25 | 40 | 60 | > 60 | > 100 |

**Note:** These are per-SET caps. A user can log multiple sets. The total reps across a session is a separate check (see §9 Edge Cases).

---

### 5.3 Cardio (Distance / Duration per Session)

| Activity | Beginner cap | Intermediate cap | Advanced cap | Elite cap | Yellow zone | Hard block |
|---|---|---|---|---|---|---|
| Running (km) | 10 km | 21 km | 42 km | 60 km | > 60 km | > 100 km |
| Cycling (km) | 30 km | 60 km | 100 km | 160 km | > 160 km | > 300 km |
| Swimming (km) | 1 km | 3 km | 5 km | 10 km | > 10 km | > 20 km |
| Walking (km) | 10 km | 20 km | 30 km | 50 km | > 50 km | > 80 km |
| Row machine (km) | 5 km | 10 km | 21 km | 42 km | > 42 km | > 80 km |
| Session duration (any cardio) | — | — | — | — | > 8 hours | > 12 hours |

**Duration note:** A user can log 8+ hours of walking (achievable) but 8+ hours of high-intensity running is not possible — add intensity as a factor when the user declares it.

---

## 6. Filter 2B — Female Strength Adjustment

Women's strength caps are set at approximately:
- **Upper body (bench, OHP, rows)**: 55–65% of men's standard at same body weight
- **Lower body (squat, deadlift)**: 75–85% of men's standard at same body weight

These are already reflected in the women's tables above (§5).

If sex is "prefer not to say" at onboarding → use the women's (lower) standards as the default. It is better to occasionally soft-warn a strong user than to let fake entries through.

---

## 7. Filter 2C — Age Adjustment

Applied on top of the base caps from §5.

| Age range | Multiplier applied to caps |
|---|---|
| Under 18 | 0.85x (growth plates, developing strength) |
| 18–39 | 1.0x (baseline) |
| 40–49 (Masters 1) | 0.95x |
| 50–59 (Masters 2) | 0.88x |
| 60–69 (Masters 3) | 0.75x |
| 70+ (Masters 4) | 0.60x |

**Important:** These are caps, not expectations. A 60-year-old athlete who has been logging for 2 years with consistent, verified data gets their historic maximum used as the cap instead — history overrides the age multiplier.

---

## 8. Filter 3 — World Record Absolute Ceiling + Sarcastic Response

### 8.1 World Record Table (Raw / Unequipped, as of 2025–2026)

These are the absolute hard ceilings. No human has done more than this.

#### Men's Raw World Records

| Lift | World Record | Record Holder | Notes |
|---|---|---|---|
| Squat | 490 kg | Ray Williams | Raw, no knee wraps |
| Bench Press | 355 kg | Julius Maddox | Raw, no shirt |
| Deadlift | 488 kg | Dan Grigsby | Raw, no suit |
| Total (SBD) | 1,155 kg | Colton Engelbrecht | 2026 |

#### Women's Raw World Records

| Lift | World Record | Record Holder | Notes |
|---|---|---|---|
| Squat | 318 kg | Sonita Muluh | March 2025 |
| Bench Press | 207.5 kg | April Mathis | Raw |
| Deadlift | 297.5 kg | Samantha Rice | December 2025 |
| Total (SBD) | 759 kg | Tamara Walcott | May 2025 |

#### Bodyweight Exercise World Records

| Exercise | World Record | Notes |
|---|---|---|
| Push-ups (1 minute) | 144 reps | Single minute, unbroken |
| Pull-ups (1 minute) | ~50 reps | Verified competitive |
| Muscle-ups (consecutive) | 45 reps | |
| Sit-ups (1 minute) | 87 reps | |
| Plank (time) | 9 hours 38 min | Gino Martino |

**Note:** These records are for equipped lifting and time-bound events. For a single logged **set** in our app, the caps in §5.2 apply (which are already lower than the all-day world records).

**Verification source:** OpenPowerlifting.org, IPF official records, Guinness World Records. Update this table annually or when new records are set. Store in DB, not code.

---

### 8.4 Yellow Zone — Verification Flow (Self-Reported Entries)

When a user confirms a Yellow-zone entry, it is saved immediately with `verification_status: 'self_reported'`. The user sees a brief note:

> "Saved! This counts toward your personal stats and PRs. To use it in challenges or show on the leaderboard, verify it with one quick step — you can do this anytime."

**Three verification paths — only ONE needed:**

| Method | What the user does | Time |
|---|---|---|
| Quick photo | Snap a photo of the barbell/weights loaded on the rack (doesn't need to show them lifting) | 5 seconds |
| Gym partner confirm | Tag another EvoFit user who was present — they tap "I was there" | 10 seconds |
| Pattern auto-verify | Log the same exercise at a similar weight 3 more times in the next 60 days — system auto-verifies based on consistency | No action needed |

On verification: `verification_status` updates to `'verified'`. Entry becomes fully eligible for challenges and leaderboard.

**What self-reported entries can and cannot do:**

| Feature | Self-reported | Verified |
|---|---|---|
| Personal PR history | ✓ Yes | ✓ Yes |
| Volume charts and stats | ✓ Yes | ✓ Yes |
| Avatar evolution points | ✓ Yes | ✓ Yes |
| Leaderboard display | Shows with "self-reported" label | Full display |
| Challenge eligibility | ✗ No | ✓ Yes |
| Challenge result used | ✗ No | ✓ Yes |

This design means no user ever loses their data or feels blocked. The only thing gated is the competitive layer.

---

### 8.2 The Sarcastic Response (UX Design)

When an entry **exceeds a world record**, do NOT show a cold error. Show this instead:

---

**Example message — deadlift exceeds world record:**

> 🏆 **Hold on — that's a world record!**
>
> You just logged **420 kg on deadlift**. The current raw world record is 488 kg (Dan Grigsby, 2026) — so if this is real, you're in elite territory.
>
> We're not saying you didn't do it. But we need to make sure.
>
> **If this is a genuine lift:** Submit a video or gym verification below — we'll review it within 48 hours. If confirmed, we'll save your entry, award bonus points, and give you a **Verified Athlete** badge for deadlift. 💪
>
> **If you made a typo:** Just hit "Fix entry" to correct it.

**Buttons:**
- `Submit for review` → opens appeal form
- `Fix entry` → returns to log input with the field highlighted

---

**Example message — push-ups exceeds world record:**

> 🏆 **That's... a lot of push-ups.**
>
> You logged **500 push-ups in one set.** The world record for push-ups in a single minute is 144 reps (and that's elite). For a single unbroken set, we've set our cap at 400.
>
> If you actually did this, first of all — please contact Guinness. Second, submit proof below and we'll verify it.
>
> Otherwise, check if there's a typo. We've all fat-fingered a zero before.

**Buttons:**
- `Submit for review` → opens appeal form
- `Fix entry` → returns to input

---

**Example message — general Yellow zone (not world record, just unusually high):**

> ⚠️ **Heads up — that's a big number**
>
> You logged **250 kg deadlift** at a body weight of **60 kg**. That's world-class territory — impressive if true!
>
> Just double-checking before we save it. Does this look right?

**Buttons:**
- `Yes, that's correct` → saves entry (Yellow zone is not blocked, just confirmed)
- `Let me fix it` → returns to input

---

### 8.3 Appeal / Review System

When a user submits for review:

**Appeal form fields:**
- Entry details (pre-filled)
- Evidence type: Video link / Screenshot from another app (Hevy, MyFitnessPal, etc.) / Gym partner User ID who witnessed it / Competition result URL
- Optional note: "I'm a competitive powerlifter at X gym"

**Review queue:**
- Manual review by admin in first phase (backlog checked weekly)
- Decision within 72 hours
- If approved: entry saved retroactively, user gets **Verified Athlete** badge for that exercise category, a one-time bonus of 200 points
- If declined: entry stays blocked, no penalty to the user — they just re-enter a corrected value

**Verified Athlete badge:**
- Shows on the user's profile and leaderboard card
- Tied to specific exercise category (e.g., "Verified — Deadlift Elite")
- Cannot be self-claimed — only granted via review

---

## 9. Edge Cases

These need to be explicitly handled. Each has a resolution.

### 9.1 "I'm a professional athlete entering on Day 1"
**Scenario:** User declares "Athlete" fitness level at onboarding and enters elite-level numbers on the first log.
**Resolution:** Athlete tier gets the highest realistic cap (Elite caps in §5). If they still exceed that, they hit the Yellow zone (confirm) or Red zone (world record alert + appeal). A genuine elite athlete will have no problem submitting proof. Benefit of the doubt is built into the Yellow zone — soft warn only, not a hard block.

### 9.2 "60 kg person enters 300 kg deadlift"
**Scenario:** 300 kg for a 60 kg person is 5.0× body weight. Hard block threshold for a 60 kg man is 270 kg (4.5×).
**Resolution:** Red zone. Sarcastic world-record response + appeal flow. Entry not saved until reviewed.
Note: the fact that they previously logged 80 kg is irrelevant to this check. The block is triggered purely by the absolute value vs bodyweight — 300 kg ÷ 60 kg = 5.0× which exceeds the physical ceiling. Same block would trigger whether their previous log was 80 kg or 250 kg.

### 9.2b "120 kg person enters 200 kg bench after logging 80 kg bench week 1"
**Scenario:** The warm-up progression case. 80 kg bench was a first-session warm-up, 200 kg is their actual working weight.
**Resolution:** Green to Yellow check only. 200 kg ÷ 120 kg = 1.67× BW = Elite tier, which sits in the Yellow zone for a 120 kg person. Soft confirmation shown: "That's an elite-level bench for your size — just confirming this is right?" User confirms → saved immediately as self-reported. NO block, NO progression-rate check, NO reference to the previous 80 kg log. The jump is irrelevant; only the absolute value matters.

### 9.3 Equipped lifting (belts, wraps, suits)
**Scenario:** A powerlifter using a deadlift suit can lift 20–40% more than raw. They enter an equipped number but we only have raw caps.
**Resolution:** Add an "Equipment used" toggle to the strength log (belt only / wraps / full equipment / raw). Caps for "full equipment" are set 35% higher than raw caps. For "belt only" (the most common): caps are 10% higher than raw. This is a data field, not just a validation bypass.

### 9.4 "I did 500 push-ups today across 20 sets"
**Scenario:** Per-set cap of 200 push-ups is fine, but 20 sets × 25 reps = 500 total. Is that valid?
**Resolution:** Per-set validation is the primary check. Total session volume is a secondary soft check. If total reps in a session exceed 500 for push-ups (or equivalent high volume for any exercise), show a soft warn: "High volume session — confirm?" This is not blocked, just flagged.

### 9.5 "My bodyweight changed — do my old logs get re-validated?"
**Scenario:** User logs 120 kg deadlift at 60 kg body weight (2.0x — Advanced, valid). They later update body weight to 40 kg. Retroactively, 120 kg at 40 kg body weight = 3.0x — World-class.
**Resolution:** Historical logs are **never retroactively invalidated.** Validation is applied at log time only, using the body weight recorded at that moment. Store `user_weight_at_time_of_log` on each logged entry for this reason.

### 9.6 "I have a medical condition that makes my numbers unusual"
**Scenario:** A user with certain conditions (e.g., connective tissue disorders like EDS) may have unusual mobility but low strength. Or a user post-surgery logs very low numbers.
**Resolution:** Medical conditions declared at onboarding only **lower** caps (to protect the user). They never raise caps. A user with a condition that genuinely allows unusual strength outputs is handled through the appeal system.

### 9.7 A user tries to game the system by updating their weight upward before logging
**Scenario:** User normally weighs 70 kg. Before a challenge log, they change their weight to 120 kg to raise their deadlift cap.
**Resolution:** Weight changes trigger a 7-day holding period before the new weight affects validation caps. During that period, the previous weight is used. Also: challenge logs use the weight at the time the challenge was accepted, not at log time.

### 9.8 Cardio — "I ran 80 km today"
**Scenario:** This is unusual but not impossible for an ultramarathon runner.
**Resolution:** Yellow zone (soft warn) at 60 km for running. If user confirms, it is saved. No hard block for cardio — duration and distance are harder to set absolute ceilings on than weight. Log the entry with a `flagged_for_review: true` field so analytics can monitor for patterns.

### 9.9 Challenge integrity — both users submit the same number
**Scenario:** Two friends both submit exactly 47 push-ups in a challenge. Coordination to split the points?
**Resolution:** Identical challenge results are flagged. Both entries saved, but the challenge result is marked "Under review." If the same two users have 3+ identical challenge results, their challenge eligibility is suspended pending manual review.

### 9.10 "Under 18" users
**Scenario:** A teenager enters elite-level numbers.
**Resolution:** Under-18 caps are set at 0.85x the base cap for their declared fitness level. This reflects growth plate safety and developing neuromuscular systems. A 16-year-old competitive powerlifter in the appeal system can still get Verified Athlete status.

### 9.11 Dumbbell vs barbell entries for the same exercise
**Scenario:** User logs "bench press" but is using dumbbells. A dumbbell bench press allows slightly different loads than a barbell.
**Resolution:** Exercise entry includes an equipment field (barbell / dumbbell / machine / cable / bodyweight). Validation caps are set per equipment type. Dumbbell bench press caps are approximately 85% of barbell bench press caps (per-hand weight, then doubled for comparison purposes).

### 9.12 "I logged it wrong but already won a challenge"
**Scenario:** User logs a correct entry that wins a challenge. Later realizes they entered kg when they meant lbs (a 2.2x difference).
**Resolution:** Challenge results are finalized after a 24-hour window closes. During the window: user can edit their own log entry (challenge result recalculated). After the window closes: result is locked. Points transferred. Edit requests after lock go to the appeal queue and are handled manually. Prevention: show the unit prominently during log entry and confirm: "You are logging in kg — is this correct?"

---

## 10. Validation System DB Schema

```sql
-- Stores the validation caps (updateable without code deploy)
CREATE TABLE exercise_validation_caps (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  exercise_id     text NOT NULL,          -- slug or FK to exercises table
  sex             text NOT NULL,          -- 'male' | 'female' | 'all'
  cap_type        text NOT NULL,          -- 'bw_multiplier' | 'absolute_reps' | 'absolute_distance'
  beginner_cap    numeric,
  novice_cap      numeric,
  intermediate_cap numeric,
  advanced_cap    numeric,
  elite_cap       numeric,
  world_class_cap numeric,
  yellow_threshold numeric,              -- triggers soft warn
  hard_block      numeric,               -- triggers world record alert
  unit            text NOT NULL,         -- 'kg' | 'reps' | 'km' | 'minutes'
  world_record    numeric,               -- current verified world record value
  world_record_holder text,
  world_record_source text,
  updated_at      timestamptz DEFAULT now()
);

-- Stores flagged entries for review
CREATE TABLE validation_flags (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             uuid REFERENCES auth.users NOT NULL,
  logged_exercise_id  uuid,              -- FK to logged entry
  flag_type           text NOT NULL,     -- 'yellow_confirmed' | 'world_record_claimed' | 'high_volume'
  entry_value         numeric NOT NULL,
  entry_unit          text NOT NULL,
  user_weight_at_log  numeric,
  status              text DEFAULT 'pending', -- 'pending' | 'approved' | 'declined'
  evidence_url        text,
  reviewer_notes      text,
  created_at          timestamptz DEFAULT now(),
  resolved_at         timestamptz
);

-- Stores per-log the bodyweight used for validation at that moment
-- (prevents retroactive invalidation when user updates weight)
ALTER TABLE logged_exercises
  ADD COLUMN user_weight_at_log numeric,
  ADD COLUMN validation_flag_id uuid REFERENCES validation_flags(id),
  ADD COLUMN equipment_type text;        -- 'raw' | 'belt' | 'wraps' | 'equipped'
```

---

## 11. Sarcastic Response Copy Bank

Pre-written sarcasm library — devs implement these as parameterized strings.

**Category: Weight exercises exceeding world record**
- "That would be a world record. We're rooting for you — please send proof."
- "The current world record is {world_record} kg. You just logged {logged_value} kg. Your move."
- "If this is real, Guinness wants a word. If not, hit Fix Entry."

**Category: Bodyweight exercises (too many reps)**
- "That's more push-ups than the world record for a single minute. Bold claim. Show us the video."
- "{logged_value} pull-ups in one set? The world record is 45 consecutive. We're impressed and skeptical."

**Category: Yellow zone (bodyweight-scaled, unusually high)**
- "That's world-class territory for someone your size. Just checking — is this right?"
- "Logging {logged_value} kg at {user_weight} kg bodyweight puts you in the top 0.01% of lifters. Confirm?"
- "We believe in you, but we also believe in checking. Does this look right?"

**Category: Speed/Distance (cardio)**
- "You ran {logged_value} km? That's further than most people drive in a week. Just confirming."
- "{logged_value} km cycling is a serious session. Confirm this is right."

**Tone rule:** Never accusatory. Always leave room for the user to be right. The sarcasm is warm, not mean.

---

## 13. Rotating Message System (Escalating on Repeat Flags)

Each user has a `flag_count` per exercise stored in the DB. Messages rotate so repeat offenders never see the same message twice — and the tone escalates slightly each time.

### Yellow Zone Rotation (unusual but not world record)

| Flag count | Message shown |
|---|---|
| 1 | "That's a big number for your stats. Just checking — does this look right?" |
| 2 | "Another big one. We're fans of ambition — just confirming this is accurate." |
| 3 | "Third time now. We either have a prodigy on our hands or a sticky zero key. Confirm?" |
| 4+ | "At this point we feel like we know each other. Big number, again. Is this the right figure?" |

### World Record Zone Rotation

| Flag count | Message shown |
|---|---|
| 1 | "That would be a world record. Submit proof and we'll verify it — and celebrate you." |
| 2 | "Back with another world record attempt? The form is still right here. We're waiting." |
| 3 | "Okay. Three times. Either you are genuinely the strongest person alive, or something's off. You know what to do." |
| 4+ | "We've saved a spot on the world record board for you. It's been empty a while. Just send proof." |

### Challenge Log Rotation (higher stakes tone)

| Flag count | Message shown |
|---|---|
| 1 | "This is a challenge log — your opponent can see this result. Make sure the number is right before confirming." |
| 2 | "Big challenge result again. We verify challenge logs more closely. Confirm this is accurate." |
| 3 | "Your opponent is watching. Third flagged challenge log. One more and your challenge eligibility goes under review." |

### Progression Spike Rotation (jumped too fast from last log)

| Flag count | Message shown |
|---|---|
| 1 | "Your last [exercise] was [X] kg ([N] days ago). You just logged [Y] kg. That's a big jump — is this right?" |
| 2 | "Another big jump from your last log. Just confirming — did something change?" |
| 3 | "We're seeing a pattern of large jumps on [exercise]. If your numbers are real, that's incredible. If there's a typo pattern, now's the time to fix it." |

**DB field needed:** `validation_flags.flag_count_by_exercise` (int, per user per exercise slug) — increment on every flag event regardless of outcome.

---

## 12. Open Questions (resolve before implementation)

| # | Question | Options |
|---|---|---|
| 1 | Where does the world record DB get maintained? | In-app admin panel vs. manual SQL update vs. external API (OpenPowerlifting has one) |
| 2 | Who reviews appeal queue initially? | Internal admin only — needs a simple review UI (not in main app) |
| 3 | How long is the challenge log edit window? | Proposed: until midnight of challenge day. Confirm. |
| 4 | Should Verified Athlete status appear on the leaderboard? | Proposed: yes, as a small badge next to the user's name. Confirm. |
| 5 | Is the 7-day bodyweight change holdoff correct? | Could be shorter (3 days) or longer (14 days). Tune after launch. |
| 6 | Do we validate dumbbell weights per hand or combined? | Proposed: per hand (as entered), with the cap set per-hand. Confirm. |
| 7 | Do cardio logs get per-user history-based cap increases? | Proposed: yes, same history-based relaxation as strength logs. Confirm. |

---

*End of validation system spec. Update when new world records are set or when testing reveals edge cases not captured here.*
