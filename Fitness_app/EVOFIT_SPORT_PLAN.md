# EvoFit — Sport Module: Complete Context & Roadmap
Last updated: 2026-06-29

SINGLE SOURCE OF TRUTH for the sport-tracking side of EvoFit.
Start here every session. Do NOT re-read PLANNING_REFERENCES.md for sport questions —
that file covers the gym/workout module only.

---

## 1. Product Vision

EvoFit Sport is a social competitive tracking layer on top of the fitness app.
Core promise: log every sport session (practice or match), track stats over time,
and optionally tag opponents/teammates so both parties share a verified record.

**Three phases:**
- Phase 1 (current): Solo sport logging — session, result, sport-specific stats, points
- Phase 2: Social tagging — opponent/partner/squad tagging, verification badges, disputes
- Phase 3: ELO rating per sport, leaderboards, squad rankings

**Differentiator vs other fitness apps:**
The Green/Yellow verification badge system. A match result with Green badge = both parties
confirmed it. This is the core hook that makes EvoFit sport different from just a diary.
This feature must be front-and-centre, not buried — it should be visible on session cards,
profile, and stats from day one (even when Yellow/unverified).

---

## 2. Tech Stack

- React 19 + TypeScript + Vite
- Tailwind CSS v4
- Framer Motion v12 (`AnimatePresence`, `motion.div`, keyframe arrays)
- TanStack React Query v5 (`useMutation`, `useQuery`)
- Supabase — PostgrestError is a PLAIN OBJECT (not instanceof Error; always check `.error` field)
- react-router-dom v6

---

## 3. Key Files

| File | Role |
|---|---|
| `src/components/sport/SportLogPage.tsx` | Main logging form + success screen |
| `src/components/sport/CricketAnimation.tsx` | Framer Motion cricket win/loss animations |
| `src/hooks/useLogSport.ts` | Supabase INSERT hook for sport sessions |
| `src/hooks/useAnalytics.ts` | `useStatsData` + `useRangeSummary` hooks |
| `src/components/stats/StatsPage.tsx` | Stats/analytics display page |
| `supabase/migrations/0013_sport_extra_stats.sql` | Adds `extra_stats JSONB` + GIN index |

---

## 4. Database Schema — `sport_sessions`

```
id                uuid PK
user_id           uuid FK → auth.users
session_date      date
sport_type        text NOT NULL  (cricket, football, badminton, etc.)
session_type      text  (match | training | warmup | recovery | rest)
duration_minutes  int
result            text  (win | loss | draw | incomplete | null for non-match)
my_score          int   (racket: games won; team: goals/runs/points scored)
opp_score         int
venue_type        text  (home | away | neutral)
rpe               int   (1–10, shown as "Effort level 1–10" in UI)
mood_before       int   (1–5, emoji picker)
mood_after        int   (1–5, emoji picker)
warmup_done       bool
cooldown_done     bool
injury_flag       bool
performance_rating int  (1–5)
notes             text
points_earned     int
extra_stats       JSONB  ← migration 0013, GIN index
```

**CRITICAL:** If migration 0013 is not applied, `useStatsData` errors on `extra_stats` column
and StatsPage shows an infinite spinner. The StatsPage MUST have an error state (not just a
spinner) that shows "Sport stats unavailable — please run database migrations." As of
2026-06-29 migration 0013 IS applied and StatsPage is working.

**Session types changed (2026-06-29 file update):**
Old: `practice | match | friendly | tournament`
New: `match | training | warmup | recovery | rest`
If DB has old values (practice/friendly/tournament) they will still display but new logs
use the new set. No migration needed (text column).

---

## 5. Sports List — Final Curated 32 (population-weighted, confirmed 2026-06-29)

Criteria: large participation base, people would actually log sessions, trackable metrics.
Removed: gymnastics, athletics (→ use Running/Track sub-type), water polo, rowing,
archery, lacrosse, darts, kho kho, ultimate frisbee, judo, fencing.

### Group 1 — Fitness & Endurance (6)
```
running 🏃    cycling 🚴    swimming 🏊    golf ⛳    climbing 🧗    triathlon 🏊
```

### Group 2 — Racket Sports (6)
```
badminton 🏸    tennis 🎾    table_tennis 🏓    squash 🟡    pickleball 🏓    padel 🏸
```

### Group 3 — Team Sports (11)
```
cricket 🏏    football ⚽    basketball 🏀    volleyball 🏐    hockey 🏒
kabaddi 🤼    rugby 🏉       baseball ⚾       am_football 🏈   handball 🤾   netball 🏐
```

### Group 4 — Combat Sports (5)
```
boxing 🥊    mma 🥋    wrestling 🤼    taekwondo 🥋    kickboxing 🥊
```

### Group 5 — Indoor & Leisure (4)
```
snooker 🎱    bowling 🎳    carrom 🎯    kabaddi (already in team)
```

**Total: 32 sports across 5 groups.**

Notes:
- Squash = 🟡 (yellow squash ball, differentiated by label from other 🟡 uses)
- Pickleball = 🏓 (shares emoji with table_tennis, differentiated by label). Was 🥒 — fixed.
- Padel = 🏸 (shares with badminton, differentiated by label)
- Taekwondo / Kickboxing share 🥋/🥊 with MMA/Boxing — label differentiates
- Badminton + pickleball have `img` fields → `SportIcon` component uses image, falls back to emoji
- Climbing 🧗 + Triathlon + Padel + Kabaddi + Netball + Kickboxing + Snooker + Bowling + Carrom
  are all NEW additions (2026-06-29)
- Hockey covers both field hockey (India) and ice hockey (West) — same tile, format picker inside
- Kabaddi is in Team Sports (not Indoor) — the 🤼 emoji is shared with Wrestling (Combat),
  differentiated by label

### Running Sub-types (Track & Field support)

Running has a sub-type toggle that changes which stat fields appear:

**Long Distance** (default)
- Distance (km) — required if no duration
- Sub-type: Road / Trail / Treadmill / Track
- Auto-computed: Pace (min/km)
- Optional: Elevation gain, Splits, Personal best flag

**Track & Field / Sprint**
- Event picker: 100m | 200m | 400m | 800m | 1500m | Hurdles | Relay | Long Jump |
  High Jump | Shot Put | Javelin | Discus | Pole Vault
- Required: Event + Finish time (or distance for field events)
- Optional: Wind speed, Heat/Final/Semi-final, Personal best flag

sub_type stored in `extra_stats.run_subtype` = `'long_distance' | 'track_field'`
event stored in `extra_stats.track_event`

---

## 6. Points System — Fully Confirmed Rules

| Rule | Decision |
|---|---|
| Duration scaling | NO — flat points per session regardless of length |
| Past-date (retroactive, max 3 days back) | ZERO points |
| Daily cap | YES — same cap as gym module (no farming) |
| Points timing | Awarded immediately at log time |
| Dispute resolution | If result changes, points are adjusted retroactively |
| Session delete | Only allowed on the SAME DAY as logging. After midnight, sessions cannot be deleted — only edited. Max 5 deletes per month (anti-abuse). Points are KEPT when a session is deleted (not deducted). |
| Match with no result set | BLOCKED — form validation error: "Set a result for this match" |
| Session_type = match | result field is REQUIRED before save |

---

## 7. Sport Picker — Grouped Two-Step UI (confirmed 2026-06-29)

Showing all 32 sports at once = cluttered. Confirmed design: two-step grouped picker.

**Step 1 — Category grid (5 cards, shown on sport picker open):**
- Fitness & Endurance · Racket Sports · Team Sports · Combat Sports · Indoor & Leisure
- Each card shows category name + sport count

**Pinned favourites (fast lane):**
- Row above the category grid showing up to 5 pinned sports
- Tapping a pinned sport skips Step 2 entirely → form loads immediately

**Step 2 — Sport tiles within chosen category (max 11 tiles):**
- Tap a category → shows only that group's sports
- Back arrow to return to categories

**After sport selected:**
- Picker collapses to a yellow chip showing the selected sport
- "Change" link re-opens the picker at Step 1

---

## 8. Required vs Optional Fields — Per Sport (confirmed 2026-06-29)

The form shows ONLY required ★ fields by default. Optional extras are behind "Add details +".
This prevents clutter for casual users without blocking power users.

**Universal required (every sport, every session):**
- ★ Session type (match / training / warmup / recovery / rest)
- ★ Date
- ★ Duration OR distance (whichever is primary for that sport)

**Required IF session_type = match:**
- ★ Result (win / loss / draw) — cannot save without this
- ★ My score (minimum)

**Sport-specific required minimums:**

| Sport | Required ★ |
|---|---|
| Running (long distance) | Distance OR duration |
| Running (track & field) | Event + finish time |
| Swimming / Cycling | Distance OR duration |
| Golf | Total strokes + course par |
| Cricket (match) | Match format + innings |
| Racket sports (match) | Match format (Bo3/Bo5) + game scores |
| Football/Basketball/Team sports | Final score + match format |
| Boxing/MMA | Result method (KO / decision / submission / TKO / DQ) |
| Snooker/Carrom | Result only (match or casual) |
| Kabaddi | Final score + match format |

**Everything else is optional** (RPE, mood before/after, venue, weather, warmup/cooldown,
injury flag, performance rating, notes, detailed extra stats).

---

## 9. Current State — What Is Shipped (Phase 1)

### SportLogPage.tsx accordion flow

1. **Sport picker** → collapses to yellow chip after selection; "Change" to re-expand
2. **Session type + duration** → collapses after duration selected (quick chips or custom input)
3. **Match details card** (conditional — only when session_type = 'match')
4. **Sport-specific extra stats** (conditional — "Add detailed stats +" expander, COLLAPSED by default)
5. **Collapsible panels**: Performance (OPEN by default), Recovery (closed), Conditions (closed)
6. All collapse toggles use `<ChevronDown>` from lucide-react (NOT raw text `⌄`)
7. All collapse headers: `cursor-pointer hover:opacity-80 transition-opacity`

### Racket sports per-game scoring

`RACKET_SPORTS = new Set(['badminton','tennis','table_tennis','squash','pickleball'])`

`RacketMatchContent` component: match type (singles/doubles/mixed) + format (Bo1/Bo3/Bo5/Bo7)

Score caps per sport per game:
- badminton: max 30 (29-29 deuce enforced in validation)
- tennis: max 7 (tiebreak at 6-6)
- table_tennis: max 21
- squash: max 20
- pickleball: max 21 (win by 2)

Table tennis supports Bo7; all others cap at Bo5.
`MAX_GAMES = { bo1:1, bo3:3, bo5:5, bo7:7 }`

Result is AUTO-DERIVED from game scores — user never manually picks result for racket sports.
`handleSubmit` computes `computedMyScore` (games won), `computedOppScore` (games lost), `computedResult`.

### Extra stats — collapsed by default

ALL sport-specific extra stats fields are behind a "Add detailed stats +" expander that is
COLLAPSED BY DEFAULT. Casual users see nothing extra. Competitive users expand and fill.
This applies to all sports including cricket (batting/bowling/fielding all behind the expander).

### Success screen

- Cricket + win → `CricketWinAnimation`
- Cricket + loss → `CricketLossAnimation`
- All other sports/results → sport emoji
- Shows: result pill (colour-coded), points earned, Done / View stats / Log another

---

## 8. CricketAnimation.tsx — Current State & Redesign Brief

File: `src/components/sport/CricketAnimation.tsx`
Exports: `CricketWinAnimation`, `CricketLossAnimation`
Tech: Pure Framer Motion — NO Lottie, no external JSON files. Keep it this way.

### Current problems (user feedback 2026-06-29):

- Bat renders as multiple layered divs → looks like "four lines"
- Pitch has no depth/perspective
- Stumps not visible against dark background in loss scene
- No boundary rope in win scene
- Ball goes vertically up — should arc forward like a SIX, not straight up

### Win animation redesign brief (SIX — ball clears boundary):

- **Ground**: green outfield strip + brown pitch in centre
- **Boundary rope**: white dashed line or rope near bottom of scene
- **Bat**: single clean div — wider amber blade at bottom, thin dark handle at top. No layering.
- **Ball trajectory**: comes from top-right at waist height → bat connects → arcs HIGH + FORWARD
  in a parabola → clears the boundary rope → exits scene top-right
- **Text**: "SIX!" (yellow glow, large) — appears after ball clears boundary
- **Flash**: brief yellow full-scene flash at moment of contact
- **Sparkles**: 4 yellow dots burst from contact point

### Loss animation redesign brief (BOWLED — ball hits stumps):

- **Stumps**: 3 tall thin cream/white rectangles, clearly visible BEFORE impact
  (use `bg-amber-100` or `bg-white` — must contrast against the dark bg)
- **Bails**: 2 short horizontal cream rectangles bridging the stump tops
- **Ball trajectory**: FLAT horizontal path from right → hits middle stump (not curved)
- **Impact**: all 3 stumps scatter in different directions + bails pop upward → brief red flash
- **Text**: "BOWLED!" (red glow) — appears after stumps scatter
- Both animations loop every 3s with 0.6s pause between loops

---

## 9. Sport History Page — New Feature (Batch 3)

### What it is

A dedicated page: `/log/sport/history`
Accessible from:
- "View all →" link on StatsPage
- Bell notification inbox (tapping a dispute/tag notification routes here)

### Layout

- Filter chips at top: sport pills (All / Cricket / Badminton / etc.) + time (Week / Month / 3M)
- Sessions grouped by week with a week-header row
- Month summary header: "June 2026 — 8 sessions · 5W 2L 1D"
- Each session card shows: sport emoji/image + sport name, date, result pill, score, duration
- Tap card → edit sheet slides up (all fields editable EXCEPT sport type)
- Disputed sessions show an inline yellow banner with "Respond →" action button

### Edit rules

| Field | Editable? |
|---|---|
| Sport type | LOCKED after save |
| Result / scores | Editable while Yellow badge; resets badge to Yellow on save |
| Result / scores | LOCKED if Green badge — "Verified — cannot edit. Raise a dispute instead." |
| Duration, notes, performance | Always editable |
| Extra stats | Always editable |
| Session date | NOT editable (prevents backdating manipulation) |

---

## 10. "My Sports" Favourites

- **Max 5 pinned sports** (free), unlimited (Pro — future)
- **How to pin**: long-press a sport tile → pin/unpin context menu appears
- **Placement**: pinned sports appear as a dedicated top row above the full grid
- **Visual**: pinned tiles have a subtle yellow glow/border to distinguish

---

## 11. Batch 2 — Per-Sport Metric Fields

All stored in `extra_stats` JSONB. ALL fields are inside the "Add detailed stats +" expander
(collapsed by default). Only show the expander for sports that have extra fields.

| Sport | Fields |
|---|---|
| Running | `distance_km` (float), `pace_min_per_km` (auto-computed = duration/distance, display-only), `run_type` (road/trail/treadmill/track) |
| Cycling | `distance_km`, `avg_speed_kmh` (auto = distance/(duration/60)), `elevation_m`, `ride_type` (road/mtb/indoor) |
| Swimming | `distance_m`, `stroke` (freestyle/backstroke/breaststroke/butterfly/IM), `pool_type` (25m/50m/open_water) |
| Tennis | `court_surface` (hard/clay/grass/indoor), `aces` (int), `double_faults` (int) |
| Football | `match_format` (11v11/7v7/5v5/futsal), `minutes_played`, `goals`, `assists`, `yellow_cards`, `red_cards` |
| Basketball | `format` (5v5/3v3), `points`, `rebounds`, `assists`, `steals`, `blocks`, `turnovers` |
| Golf | `total_strokes` (int), `par_for_course` (int), `score_vs_par` (auto = strokes - par, display-only), `putts`, `fairways_hit` |
| Boxing/MMA | `stopped_in_round` (int), `result_method` (KO/TKO/submission/decision/DQ), `weight_class` (text picker) |
| Volleyball | `format` (indoor_6v6/beach_2v2), `kills`, `blocks`, `digs`, `aces`, `errors` |
| Cricket (full CricHeroes-level) | See section below |

### Cricket Extra Stats — Full Breakdown

**Match context:**
- `match_format`: T20 / ODI / Test / T10 / Club / Tape-ball / Other
- `innings`: 1st / 2nd
- `batting_position`: 1–11 (number picker)

**Batting section** (all optional):
- `runs_scored`: int
- `balls_faced`: int
- `fours`: int
- `sixes`: int
- `strike_rate`: auto-computed (runs/balls × 100) — display only
- `how_out`: bowled / caught / run out / lbw / stumped / hit wicket / retired / not out

**Bowling section** (all optional):
- `overs_bowled`: float (e.g., 3.4)
- `maidens`: int
- `runs_given`: int
- `wickets`: int
- `economy`: auto-computed (runs_given/overs_bowled) — display only

**Fielding section** (all optional):
- `catches`: int
- `run_outs`: int
- `stumpings`: int

---

## 12. Phase 2 — Social Tagging System

Two completely separate systems. Do not merge them.

---

### System A — Individual Tagging (1v1 / 2v2)

**Used for**: racket sports, boxing, MMA, wrestling, combat sports — individual vs individual

**Match type → tag slots:**
- Singles: 1 opponent slot
- Doubles: 1 partner slot + 2 opponent slots
- Mixed: same as doubles

### Tagging — 3 Tiers (confirmed 2026-06-29)

**Tier 1 — Username/name search (primary path)**
- Type a name or @username → live search against existing EvoFit users
- Found → one-tap select → immediately hard-linked by user_id
- No email needed. Cleanest path.

**Tier 2 — Email (they're not on EvoFit yet)**
- Search returns no match → enter their email
- System sends a magic link email (not a generic sign-up email):
  "Shashank tagged you in a Cricket match · 28 Jun · Won 2–1. [View & Confirm Match]"
- Magic link: creates EvoFit account (pre-filled email, just name + password = 10s)
  then drops them DIRECTLY on the match confirmation screen
- No manual search needed — one click from email to confirm/dispute
- Rate limit: max 3 magic link emails per session, max 10/day per logger
- Link expiry: 7 days. Logger can resend once after 24h (old link auto-invalidates)
- Logger can update tagged email once within 30 days

**Tier 3 — Name-only placeholder (no email available)**
- Enter just "Raul" as a name → stored as placeholder string
- Badge stays Yellow. No invite sent.
- Logger can return later (within 30 days) to add email → triggers magic link at that point
- OR Raul joins EvoFit later → sees "Claim matches" in onboarding → searches by
  sport + approximate date + opponent name → confirms → linked

**Duplicate email resolution:**
| Scenario | Resolution |
|---|---|
| Tagged email = email they sign up with | Auto-linked. No conflict. |
| Tagged raul@gmail.com but Raul already has raul@work.com | Raul's profile shows "Unlinked matches." Settings → Add email alias → matches link. |
| Name-only placeholder, Raul joins later | "Claim matches" onboarding step → search by sport/date/name → confirm |

**Data stored in extra_stats:**
```json
"tagged_players": [
  { "role": "opponent", "name": "Rahul", "email": "rahul@x.com", "user_id": null },
  { "role": "partner",  "name": "Priya", "email": "priya@x.com", "user_id": "uuid-if-linked" }
]
```

**Security:** If tagged_email === logged_in_user.email → reject. Cannot tag yourself.

**Once linked:** tagged person can VIEW the match, confirm or dispute the score.

**Recent opponents:** After tagging, save to recents. One-tap select next time — no re-typing.

---

### System B — Squad Tagging (Team Sports)

**Used for**: cricket, football, basketball, volleyball, hockey, rugby — large group matches

**Concept:**
- **Squad template** = permanent list of your regular teammates (`squads` + `squad_members` tables)
- **Match roster** = per-match COPY of the squad at time of match (`match_roster` table)
  - This copy is editable: add/remove players for this specific match without touching the template
  - Editing one match's roster never changes the template or other matches

**Squad limits:**
- Free: up to 5 squads per sport
- Pro: up to 10 squads per sport
- 1 of the 5 free slots is a **"Quick Match" squad** — always editable, acts as a scratch/throwaway
  roster for one-off games with people outside your regular teams. No permanent template logic.

**Squad tagging is always OPTIONAL.** You can log any team match without selecting a squad.

**DB tables needed (Batch 4):**
```sql
squads (
  id uuid PK, user_id uuid FK, sport text, name text,
  is_quick_match bool DEFAULT false, created_at timestamptz
)
squad_members (
  id uuid PK, squad_id uuid FK, member_name text, member_email text,
  member_user_id uuid nullable, joined_at timestamptz
)
match_roster (
  id uuid PK, session_id uuid FK → sport_sessions, squad_id uuid FK,
  roster_snapshot JSONB,  -- copy of squad_members at time of match
  created_at timestamptz
)
```

**Stat filling rules:**
- Anyone on the match roster fills/edits THEIR OWN stat row
- NOT captain-only — any registered squad member can fill their own row
- Creator can pre-fill placeholder rows for unregistered players (shows as "Pending claim")
- When unregistered player joins EvoFit and links email → placeholder becomes their owned row
  → they can edit it, captain is notified

**Retroactive late-joiner stats:**
- Auto-approved (shows immediately, no captain approval needed)
- Shown in the match view with "Retroactive — not counted in your personal stats" label
- NOT included in the late-joiner's personal stats calculations

**"Remind teammates" feature:**
- Button inside the match roster view after logging
- Sends email nudge to all squad members who haven't filled their stats yet

**Squad stats view (future):**
- Team-level leaderboard within a squad: wins, top scorer, most active member
- This is separate from personal stats

---

## 13. Phase 2 — Verification Badges

**Yellow badge 🟡** = self-reported only (no opponent tagged, or tagged but not yet confirmed)
**Green badge 🟢** = both parties have confirmed the match score

**Badge rules:**
- All sessions start Yellow
- Green requires: opponent is tagged AND has an EvoFit account AND has confirmed the score
- Editing while Yellow: allowed; resets nothing (still Yellow, opponent re-confirms fresh)
- Editing while Green: BLOCKED on score/result fields — shows "Verified — cannot edit. Raise a dispute instead."
- Duration, notes, performance fields: always editable regardless of badge

**Badge visibility:**
- Shown on session cards in history
- Shown on StatsPage (ratio of verified vs unverified matches)
- Shown on profile

---

## 14. Phase 2 — Dispute Flow

**Rules:**
- Score/result fields only — NO chat, no back-and-forth messaging
- Max 3 rounds per match (one dispute per match total)
- 72h expiry per round — if no response, previous value stands
- After 3 rounds or expiry, dispute is closed permanently

**3-round flow:**
1. **Round 1 (Opponent raises):** Opponent sees the logged match, disagrees → taps "Dispute score"
   → enters what they believe the correct score was → submits
2. **Round 2 (Logger responds):** Logger gets bell notification + email → sees disputed score
   → options: Accept (score updates to opponent's version) OR Counter-propose (enter own corrected score)
3. **Round 3 (Final):** Opponent sees counter-proposal → Accept or Reject
   - Accepted → score locks at counter-proposal; Green badge if both accounts are verified
   - Rejected at Round 3 → dispute expires, ORIGINAL score stands, badge stays Yellow

**Points on dispute resolution:**
- If result changes (e.g., win → loss), points are recalculated for the new result
- Difference added/deducted to `point_log` table; user notified

**Dispute abuse prevention:**
- Max 1 dispute per match (cannot re-raise after resolution)
- Report/block feature for persistent harassment (future)
- Disputes can only be raised by tagged participants (not random users)

---

## 15. Notifications

**In-app:** Bell icon in top nav — all notifications including:
- "You were tagged in a match by [Name]"
- "Your score was disputed by [Name]"
- "Dispute response received"
- "Teammate hasn't filled their squad stats — remind them?"

**Email:** Supabase email for:
- Tagged users who are NOT yet on EvoFit (invite email)
- Dispute notifications for existing users as backup
- "Claim unlinked match" prompt when a new user signs up and has pending tags

**Dispute inbox:** Sessions with active disputes show an inline yellow banner in the
Sport History page ("Respond to dispute →"). No separate "Disputes" tab needed.

---

## 16. Phase 3 — ELO & Ratings (full design confirmed 2026-06-29)

### What ELO Is

ELO = a skill rating number per sport, per user. Everyone starts at 1200.
Win vs stronger opponent → gain more. Lose vs weaker opponent → lose more.
Named after chess inventor Arpad Elo. Used by chess.com, FIFA, Valorant, League of Legends.

### When ELO Applies

- ONLY on Green badge matches (both parties confirmed via the app)
- Yellow badge (self-reported) = points only, ELO unchanged
- Unverified sessions never affect ELO

### The Math

```
Expected win prob:   E_A = 1 / (1 + 10^((R_B - R_A) / 400))
New rating:          R_A = R_A + K x (Actual - Expected)
Actual = 1 (win), 0.5 (draw), 0 (loss)
```

K-factor tiers (confirmed):
- Provisional (< 20 ELO matches): K = 40 — large swings to establish rating fast
- Established (20–100 matches): K = 20
- High-rated (rating > 2000): K = 10

### Anti-Cheat — Full Design (confirmed 2026-06-29)

The attack: create Account B, beat it 30 days straight → inflate Account A ELO.

Why the math already limits this: after Account B loses 30 games it drops to ~850.
At that point: E_A = 0.94, so gain per win = 20 x 0.06 = +1.2 pts only.
Account A caps ~1400–1450 even after 30 alt wins. Not dramatically useful.

Additional guards:

| Guard | Rule |
|---|---|
| Account age gate | Opponent must be 30+ days old. New accounts cannot be farmed immediately. |
| Same-opponent weekly cap | Max 3 ELO matches/week vs the SAME opponent. 4th+ = 0 ELO. Kills win-trading. |
| Opponent gap penalty | Opponent >400 pts below you → K halves again. Beating an 800-rated alt when at 1400 gives ~1 pt max. |
| ELO floor | Minimum rating: 800. Alts cannot tank to become worthless loss-machines. |
| Device fingerprint | Both accounts on same device playing each other → soft flag → ELO frozen pending review. |
| IP clustering | Same IP + accounts playing each other repeatedly → flag. Combined with device = strong signal. |
| Match anomaly | Two accounts play each other >10x/month with 100% W/L split → auto-flag. |
| Leaderboard gate | Only accounts with 20+ ELO matches shown on leaderboard. New alts never appear. |
| Green badge friction | Both parties must open app and tap confirm — 30 manual actions needed for alt farming. |

Even if someone bypasses all guards: they show up high on leaderboard, get challenged by
real strong players, lose, ELO drops back. ELO is self-correcting. Inflation is temporary.

### DB Tables

```sql
sport_elo (
  user_id uuid FK, sport_type text,
  rating int DEFAULT 1200, matches_played int DEFAULT 0,
  updated_at timestamptz,
  PRIMARY KEY (user_id, sport_type)
)
-- elo_change stored per match in match_participants.elo_change
```

Phase 3 also delivers: per-sport leaderboards, squad rankings, H2H records.

---

## 17. Pro Tier ($5 — one-time or subscription TBD)

**Free tier includes:**
- All logging features
- 90 days of sport session history
- Basic stats (session count, win rate, top sport)
- All social features (tagging, squad, disputes, verification badges)
- Up to 5 squads per sport
- Pinned sports (up to 5)

**Pro tier unlocks:**
- Full history (unlimited, no 90-day cut-off)
- Advanced analytics: trend charts, form guide, export to CSV/PDF
- ELO / ratings access
- Up to 10 squads per sport (free = 5)

**NOT behind Pro:**
- Squad tagging (free)
- Dispute flow (free)
- Verification badges (free)

---

## 18. Security Edge Cases & Resolutions

| Threat | Resolution |
|---|---|
| Self-tagging (user tags own email as opponent) | Frontend + backend: if tagged_email === user.email → reject |
| Multi-account Green badge fraud | ELO only counts Green where opponent account >30 days old |
| Points farming via delete-relog | Delete allowed SAME DAY only, max 5 deletes/month, points kept |
| Race condition on daily point cap | Enforce via DB-level constraint, not just frontend check |
| Points not deducted on dispute win→loss change | point_log adjustment entry created on dispute resolution |
| Dispute abuse / harassment | Max 1 dispute per match; report/block feature (future) |
| Late-joiner retroactive stat inflation | Stats flagged "not counted"; captain can reject within 7 days |
| Squad member impersonation (captain fills someone's stats as 0) | When player claims row, they can edit → captain notified |
| Session delete post-verification | Green badge sessions: cannot be deleted (only edited via dispute) |
| extra_stats schema drift (wrong sport fields saved) | Validate keys per sport on write; ignore unknown keys on read |
| Missing migration 0013 → StatsPage infinite spinner | StatsPage must have error state: "Stats unavailable — run migrations" |
| Null result on match save | Blocked at form level: "Set a result for this match" |
| API direct call with no sport_type | DB: NOT NULL constraint on sport_type column |
| Unregistered opponent never joins → permanently Yellow | Accepted. Yellow = self-reported. Green is aspirational. |

---

## 19. UX Improvements Backlog (Prioritised)

### High value, relatively low effort:
1. **RPE label** → rename "RPE" to "Effort level (1–10)" in UI; keep the field name `rpe` in DB
2. **Recent opponents** → after tagging, save to recents; one-tap re-select next match
3. **Form guide on sport picker** → tiny `W W L W W` strip on each sport tile (last 5 results)
4. **Win streak on success screen** → "You've won 4 badminton matches in a row 🔥"
5. **Home page sport widget** → shows per-sport session count + Green/Yellow badge split for the month:
   ```
   🏏 Cricket   8 sessions   🟢×3  🟡×5
   🏸 Badminton 5 sessions   🟢×4  🟡×1
   ⚽ Football  3 sessions   🟡×3
                              [View all →]
   ```
   Yellow count = subtle nudge to tag opponents. "View all →" → Sport History page.
6. **"Quick re-log" button** on success screen → pre-fills same sport/duration, clear result/scores
7. **Smart defaults** → remember average duration per sport; pre-fill it next time
8. **Injury flag visibility** → flagged sessions show a ⚠ icon in history so user can track injuries

### Medium effort, high retention value:
9. **Head-to-head record** → when you view a tagged opponent's mini-profile, show your H2H vs them
10. **Per-sport win rate card** → on StatsPage: "Badminton 68% win rate (23W 11L)"
11. **Sport XP / levels** → separate from points; each sport has a level (1–10) based on sessions logged
    - Shows on profile: "Cricket Lv.7 · Badminton Lv.3"
    - Retention hook — doesn't affect points/ELO
12. **Share card on win** → "Share this match" button on success screen; generates an image card
    (sport emoji, result, score, opponent if tagged) — shareable to WhatsApp/Instagram

### Lower priority / future:
13. **Challenge system** → tap a friend's profile → "Challenge to a match" → creates pending match entry
14. **Squad leaderboard** → within a squad: rank members by wins, ELO, total sessions
15. **Onboarding moment** → first-time sport log: prompt to pin 3 favourite sports immediately

---

## 20. Animation Plan

### Cricket (current, needs redesign — see Section 8)

File: `src/components/sport/CricketAnimation.tsx`
Exports: `CricketWinAnimation`, `CricketLossAnimation`
Wired in: `SportLogPage.tsx` success screen ternary

### Other sports — future (same file-per-sport pattern)

File: `src/components/sport/<Sport>Animation.tsx`
Exports: `<Sport>WinAnimation`, `<Sport>LossAnimation`

| Sport | Win scene | Loss scene |
|---|---|---|
| Football | Ball hits top corner, net ripples | Goalkeeper dives, saves it |
| Basketball | Ball swishes through hoop, net sways | Ball rims out |
| Badminton | Shuttlecock smashes into ground | Shuttlecock hits net, drops |
| Tennis | Ace ball down the T-line | Double fault, ball into net |
| Boxing/MMA | Gloves raised, crowd dots burst | Boxer on one knee, count |

---

## 21. Ordered Build Queue (Next Sessions)

Execute ONE at a time in this order:

**NEXT → Cricket animation redesign**
File: `CricketAnimation.tsx`
Brief: Section 8 above. SIX animation (boundary rope, forward arc, bat clean). BOWLED animation (visible stumps, flat ball trajectory, scatter).

**→ Batch 2: Per-sport metric fields**
Add "Add detailed stats +" expander to SportExtraFields with all sport-specific fields (Section 11).
Cricket gets full batting + bowling + fielding sections.
Auto-computed fields (pace, strike rate, economy, avg speed, score vs par) are display-only — not stored, calculated from stored values on the fly.

**→ Sport History page + Edit**
Route: `/log/sport/history`
Layout: week-grouped session cards, filter chips, month summary header.
Edit sheet: all fields except sport type.
Badge behaviour on edit: per Section 9.

**→ "My Sports" pinned favourites**
Long-press → pin/unpin, max 5, pinned row above grid.

**→ Batch 3 UX polish**
Past-date picker (max 3 days, zero points label shown).
Recent opponents list.
Form guide on sport tiles (W/L strip).
Home page sport widget (last 3 sessions).
Rename RPE to "Effort level."

**→ Batch 4: Individual tagging**
Tagged players in extra_stats, recent contacts, invite email, auto-link on sign-up.
Claim unlinked matches screen.

**→ Batch 4: Squad system**
squads + squad_members + match_roster tables.
Squad picker in match section.
"Quick Match" squad.
Remind teammates button.

**→ Batch 5: Dispute + badges**
match_participants + match_invitations + match_disputes tables.
3-round dispute UI.
Bell notification inbox.
Yellow/Green badge display on session cards and StatsPage.

**→ Batch 6: ELO (Phase 3)**
sport_elo table.
ELO calculation on Green-badge confirmed matches.
Per-sport leaderboard.

---

## 22. Session Change Log

| Date | Change |
|---|---|
| ~2026-06 early | Initial sport logging form, Supabase schema, `useLogSport` hook |
| ~2026-06 mid | `useAnalytics` extra_stats integration, migration 0013 |
| 2026-06-25 | Racket per-game scoring (`RacketMatchContent`), accordion UI, ChevronDown icons, BO1, squash emoji 🎯→🟡, perf section open by default, pickleball accidentally 🥒 |
| 2026-06-29 (morning) | Fixed pickleball 🥒→🏓. Added `CricketWinAnimation` + `CricketLossAnimation`. Wired into success screen. |
| 2026-06-29 (user edit) | Added climbing 🧗, badminton/pickleball image support (`SportIcon`), `VENUE_TYPES`, SESSION_TYPES changed to `match/training/warmup/recovery/rest`, `WEATHER` and `MOOD_EMOJIS` arrays |
| 2026-06-29 (planning) | Full product review — all decisions captured in this document. |
