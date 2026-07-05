# EvoFit App Audit — Remaining Pages Deep Analysis
## Multi-Perspective Critique: New User · Casual User · Serious User · Critic · Developer/Security

> Covers: **Dashboard · Habits · Yoga · Log Track Select · Stats · Leaderboard · Profile**
> (Gym Log + Sport + Plans already documented in PLANNING_REFERENCES.md)

---

## 1. DASHBOARD (DashboardPage.tsx)

### New User
- Opens to streak "0 days" and "0 points" — immediately feels like failure, not welcome
- No onboarding nudge; page jumps straight into empty sections
- Pokémon card ("My Pokémon · View your collection") sits at the same visual weight as "Performance Stats" — a brand-new user has zero Pokémon and zero context for what this feature is
- Muscle heatmap section only appears when `weeklyNames.length > 0` — invisible for new users, causing a jarring layout shift after first workout
- No "What do the 4 tracks mean?" explanation anywhere on dashboard

### Casual User
- No date picker — can't look at yesterday's summary if you forgot to log
- Week/Month tabs show stats but no *motivational context* ("You did 4/7 days last week — your best was 5!")
- Track progress bars in `RangeSummaryView` are animated to `Math.min(100, t.pct * 3)` — **the `*3` multiplier is wrong**. 7 gym sessions in 30 days = 23% of days but the bar shows 70%. The scale is meaningless.
- Activity strip uses color gradient (indigo→emerald→yellow) for track count but the legend labels are "1 track / 2 tracks / 3–4 tracks" — no mention of *which* tracks
- "Add another" workout link is buried at the bottom of the workout list

### Serious User
- No quick "Log workout" FAB on dashboard — user must navigate to tab bar → Log → choose track
- No streak forecast: "Log today to maintain your 14-day streak"
- No rest day logging from dashboard
- `profile?.current_streak` comes from cached profile — may not update until next page load after logging

### Critic
- `pct * 3` bar animation bug appears in **two places**: RangeSummaryView:183 and DashboardPage week/month tabs. A serious lifter logging 5 gym sessions in 7 days (71%) sees the bar at 100% (213% capped). A new user with 1 session sees 14% → 43%. Neither is meaningful.
- `completeGoal.isPending` at line 379 is shared across ALL daily goal buttons — the **same isPending bug as clonePlan** (see PLANNING_REFERENCES.md §14). Tap one goal, all buttons freeze.
- Daily Goals section is invisible if `goals.length === 0` — but there's no "Add a goal" CTA here. Goals appear magically only if set up from Habits → Manage.
- Pokémon button sits between Performance Stats shortcut and Streak Shields — disrupts the fitness-first hierarchy. Should be in profile or a rewards section.
- `(w as unknown as { exercises?: unknown[] }).exercises?.length` at line 353 — `as unknown as` double cast indicates a schema type mismatch that should be fixed properly.

### Developer / Security
| Issue | Severity | Location |
|---|---|---|
| `completeGoal.isPending` shared across all goal buttons | High | DashboardPage.tsx:379 |
| `pct * 3` animation multiplier — misleading metric | Medium | DashboardPage.tsx:183 |
| Muscle heatmap conditional render causes layout shift | Low | DashboardPage.tsx:319 |
| `as unknown as { exercises? }` type hack | Medium | DashboardPage.tsx:353 |
| No error state for `useTodayWorkouts` — silent empty on failure | High | DashboardPage.tsx:249 |
| `profile?.current_streak` stale after logging workout | Low | DashboardPage.tsx:299 |

### Ideas / Improvements
- "Keep your streak alive" banner when it's past 8pm and nothing logged
- Motivational streak callout: "5 days — your longest run ever!"
- Quick-log shortcut chip row on dashboard: `[+ Gym] [+ Sport] [+ Yoga] [✅ Habits]`
- Fix `pct * 3` → use actual percentage, rethink the scale
- Fix `completeGoal.isPending` to be per-goal (use `completeGoal.variables?.goalId`)

---

## 2. HABITS (HabitsPage.tsx + HabitsManagePage.tsx)

### New User
- Empty state is clean with a "Add Habits" CTA — well done
- Template picker shows name, icon, category, description — but **no points value**. User doesn't know logging habits is worth points until after they add one.
- No explanation of what "binary," "numeric," "time," or "negative" habit types mean before setup
- Push notification banner appears immediately even before any habit has a reminder set — confusing

### Casual User
- No drag-to-reorder habits — they appear in creation order forever
- DAY_LABELS = `['M', 'T', 'W', 'T', 'F', 'S', 'S']` — **both Tuesday and Thursday show "T"**. Confusing in the day-picker buttons.
- No way to view yesterday's or last week's habit log — you can only see today. No history calendar on the habits page itself.
- Numeric habit "quick picks" are 25%/50%/75%/100% of target — if target is 8 glasses and you've had 6, the quick picks show 2, 4, 6, 8. Not useful for "I just drank 1 more glass" incremental logging.
- Partial credit not possible: logging 30 min, then 30 more min of walking replaces the value (not adds to it) — confirmed `replace: true` behavior in NumericInput

### Serious User
- No pause/skip feature — you can only archive/restore. No "pause for 1 week (vacation)" option.
- No bulk-complete option for habits that don't need individual tracking
- No habit streak mini-calendar on this page — must go to Stats → Habits tab to see per-habit streaks
- "Negative" habit slip flow is counterintuitive: `done=true` means "no slip today" but the button says "I Slipped" — the mental model (done = stayed clean) conflicts with "I Slipped" = toggle to done

### Critic
- `<details>` HTML element used for archived habits (HabitsManagePage.tsx:509) — unstyled browser-native `<summary>` in a dark glass UI. Looks completely broken in Chrome/Edge. Should be a styled expand/collapse.
- Back button navigates to `/log` — if user came from dashboard, pressing back sends them to the log track select page, not dashboard. Breaks mental navigation model.
- Slip confirmation dialog appears inside a `motion.div` with `height: 0 → auto` — if the parent card is near the bottom of the screen, the confirmation panel is off-screen and user can't see it.
- Push notification "active" banner at top of habits page **never auto-dismisses** — it shows on every visit even after being acknowledged. Permanent visual clutter.
- `reminder_time` displayed as raw `"08:00"` string in manage page (HabitsManagePage.tsx:478) — should format to "8:00 AM"

### Developer / Security
| Issue | Severity | Location |
|---|---|---|
| `DAY_LABELS['T','T']` — Tuesday and Thursday both show 'T' | High | HabitsManagePage.tsx:15 |
| `<details>` unstyled in dark UI — broken visual | High | HabitsManagePage.tsx:509 |
| `useAddHabitFromTemplate` + `useCreateCustomHabit` both read `existing` to compute `maxSort` — race on simultaneous adds | Medium | HabitsManagePage.tsx:27,75 |
| Push subscribed banner never auto-clears — shows every visit | Medium | HabitsPage.tsx:436 |
| `notificationSupported()` not guarded for iOS Safari where `Notification` may be undefined | Medium | HabitsPage.tsx:352 |
| `createHabit.isError` shown but no retry button | Low | HabitsManagePage.tsx:390 |
| Numeric habit replace-not-accumulate — undocumented UX expectation | Low | HabitsPage.tsx:182 |

### Ideas / Improvements
- Fix day labels: `['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su']`
- Replace `<details>` with a styled collapsible chevron component
- Add 7-day mini streak dot row to each habit card (shows completion last 7 days)
- Add "pause until" date to habits instead of archive/restore
- Accumulate numeric values instead of replacing (with per-day total stored)
- Quick "+" button on habit card for incrementing by 1 unit without opening input

---

## 3. YOGA (YogaLogPage.tsx)

### New User
- Cleanest log page in the app — minimal steps, good defaults
- Style is required (asterisk shown) — appropriate gate
- Mood before/after pickers look identical side-by-side — easy to accidentally fill "after" first

### Casual User
- No "repeat last session" shortcut — must re-select style, focus area, duration every time
- Duration slider range 5–120 with step 5 — but the slider thumb shows no label tooltip while dragging, only the static readout at the right changes. Hard to land on exact value.
- **No past-date picker** — yoga done yesterday must be logged today, but the date shown is always today's date
- No cancel/back confirmation — if user fills 80% of the form then taps back, everything is silently lost

### Serious User
- No class/instructor name field — studio practitioners want this
- No sequence tracking (what poses were done)
- No location field beyond outdoor toggle — "studio name" or "home" distinction missing
- `navigate(-1)` on back button — if user arrives via direct URL or bookmark, this sends them to an unrelated page in the history stack

### Critic
- `saveError` message for PostgreSQL error 42P01 is **"Yoga sessions table not set up yet. Open Supabase → SQL editor → run migration 0012_yoga_sessions.sql"** — this leaks internal architecture (Supabase, SQL migrations) directly to end users. **Critical UX violation.** Should show "Something went wrong, please try again" and log internally.
- FLEX_EMOJIS = `['🪨', '😬', '🙂', '😊', '🤸']` — 🪨 (rock) for stiff is not universally understood. Requires cultural context. Should use a scale like 😐→🤸 with text labels "Stiff → Flexible"
- MOOD_EMOJIS: only 1-5 numbers below emojis — no label like "Stressed / Okay / Great." A 3/5 could mean anything.
- Success screen has no comparison to last session ("Last time: 45 min Vinyasa") and no "plan next session" action
- `navigate(-1)` inconsistent with HabitsPage which uses explicit `navigate('/log')` — pick one pattern

### Developer / Security
| Issue | Severity | Location |
|---|---|---|
| Internal Supabase migration error shown to users | Critical | YogaLogPage.tsx:106 |
| `navigate(-1)` — broken on direct URL arrival | Medium | YogaLogPage.tsx:157 |
| No form state preservation on accidental back | Medium | YogaLogPage.tsx (no `useRef` or state save) |
| Duration not validated > 0 before save | Low | YogaLogPage.tsx:86 |
| FLEX_EMOJIS and MOOD_EMOJIS duplicated across Yoga+Stats pages | Low | YogaLogPage.tsx:31–32 |

### Ideas / Improvements
- "Same as last time →" quick-fill button at top (loads last session's values)
- Add instructor/class name optional field
- Replace 🪨 with 😐 or stiff body silhouette icon
- Add mood label words below scale numbers: (😞 Low → 😄 Great)
- Suppress technical error messages in production — map known codes to friendly messages

---

## 4. LOG TRACK SELECT (LogTrackSelectPage.tsx)

### New User
- 2×2 grid with large icons — instantly scannable, well done
- "Work" track is disabled but takes full 2-column width — wastes significant screen space on something the user can't use
- Cross-track bonus teaser at bottom is good but doesn't say what the bonus IS (points? badge? Pokémon?)

### Casual User
- "View Sport Stats" shortcut button at the BOTTOM of this page — odd. Why would someone want to view stats when they're about to log? Should be in stats or dashboard.
- No swipe navigation — must tap precisely
- Page doesn't greet user or show today's logged tracks summary

### Critic
- "Work — Focus · Deep work · Planner" occupies 100% width (col-span-2) and is permanently disabled. This is the most expensive piece of visual real estate on this page, reserved for a feature that doesn't exist yet. Hide it entirely until built.
- Click handler `!track.comingSoon && navigate(track.to)` — disabled button still responds to touch events, just silently does nothing. Should use proper `disabled` attribute.
- Route is `/log` but there's no breadcrumb — users deep-linking to `/log/yoga` skip this page entirely (which is fine) but also skip the cross-track bonus reminder
- No visual indicator of what tracks you've already logged today

### Developer
| Issue | Severity | Location |
|---|---|---|
| Coming-soon card intercepts touch events silently | Low | LogTrackSelectPage.tsx:75 |
| No today's completed tracks indicator | Medium | LogTrackSelectPage.tsx (feature gap) |
| "View Sport Stats" button misplaced on log selection page | Low | LogTrackSelectPage.tsx:94 |

### Ideas / Improvements
- Show today's completion status on each tile: small ✓ badge on Gym card if already logged today
- Remove "Work" card until feature is built
- Move "View Sport Stats" to bottom nav or stats tab
- Show cross-track bonus progress: "Log 2 more tracks today for +50 bonus points ✨"

---

## 5. STATS PAGE (StatsPage.tsx)

### New User
- Per-tab empty states are clear and well-designed
- But Overview tab still renders "7-Day Velocity" chart with a flat line when there's zero data — looks like a rendering bug to a new user
- KPI widget strip shows "0.0" for all metrics — "Gym / Week: 0.0" reads as broken, not as "you have no data yet"

### Casual User
- 5 tabs: Overview / Gym / Sport / Yoga / Habits — no tab for Insights (Insights tab code exists in the file but may not be wired up in tab strip — needs verification)
- Time range filter (1W / 1M / 3M) is at the top but the **Heatmap always shows 91 days** regardless of filter selection — inconsistent. User selects "1 Week" but sees 13 weeks of history in the heatmap.
- Sport tab: "Win Rate by Day" section only appears after 5+ match results (`matchResults.length >= 5`) — silently appears with no explanation. User may wonder why it appeared after a few more sessions.
- Weekly Gym volume calculated as `sets × reps × weight_lbs × 0.453592` — includes isolation and compound exercises equally. A tricep kickback at 10kg counts same as a deadlift at 10kg. Not labelled as "strength volume (approximate)"
- PR section shows max weight ever lifted (`lbs + kg`) in each row — no date of PR, no indication if it was recently broken

### Serious User
- No progressive overload view — "am I lifting more this month than last month for bench press?"
- No export/share function for any stats
- Habit stats only go 30 days while gym/sport use 90 days — inconsistent analysis window
- `gymConditioningSessions` in Sport tab parsed via `w.notes?.match(/Sport:\s*(.+)/i)?.[1]` — regex-based DB coupling is fragile. No documentation on this format.
- No data freshness indicator — user doesn't know if viewing live data or cached

### Critic
- **File is 2440 lines** — second largest component in the codebase. No separation of concerns. GymTab, SportTab, YogaTab, HabitsTab, InsightsTab should be individual files.
- `SportKPIBlock` called as a function `SportKPIBlock({...})` not as JSX `<SportKPIBlock />` at line 1215 — won't be memoized by React, re-executes on every parent render
- `SPORT_META` in StatsPage (line 161) and `SPORT_LABELS` (line 1040) are **two separate lookup objects** for the same data. One should reference the other.
- Heatmap color scheme: 5 shades of emerald (`bg-emerald-900/70 → bg-emerald-400`) — on dark background, these are nearly indistinguishable. Accessibility fail.
- `pct × 3` animation bug (from Dashboard) also affects how stats bars are scaled in some sub-views

### Developer / Security
| Issue | Severity | Location |
|---|---|---|
| 2440-line file — single component doing too much | High | StatsPage.tsx (whole file) |
| `SportKPIBlock({...})` called as function not JSX | Medium | StatsPage.tsx:1215 |
| Heatmap always 91 days regardless of time range filter | Medium | StatsPage.tsx:413 |
| Duplicate SPORT_META + SPORT_LABELS objects | Low | StatsPage.tsx:161, 1040 |
| Gym conditioning linked by regex on notes text — fragile | High | StatsPage.tsx:1072 |
| `filterDataByRange` then per-section re-filter = double filtering, inconsistent results | Medium | StatsPage.tsx:194 |
| `localStorage` KPI widget storage not synced across devices | Low | StatsPage.tsx:256 |
| Heatmap colors — 5 near-identical emerald shades on dark bg | Medium | StatsPage.tsx:74 |

### Ideas / Improvements
- Split into GymTab.tsx, SportTab.tsx, YogaTab.tsx, HabitsTab.tsx, InsightsTab.tsx
- Progressive overload chart: per-exercise weight trend line (last 8 sessions)
- Heatmap time range should match selected filter (or be explicitly labelled "Always 91 days")
- Add PR date alongside max weight
- Use Epley formula for 1RM in PR section (currently max single weight, not 1RM)
- Fix `SportKPIBlock` to use proper JSX component pattern
- Unify SPORT_META and SPORT_LABELS into one shared constant

---

## 6. LEADERBOARD (LeaderboardPage.tsx)

### New User
- Good empty state: "No public trainers yet. Be the first to make your profile public!" with clear action
- Group tab: "You're not in any group yet. Join one with an invite code." — **no invite code input field shown anywhere**. User told they need a code but have nowhere to enter it.
- No explanation of points system — "ranked by total points" with no link to how points are earned

### Casual User
- Global leaderboard shows ALL users ranked by all-time points — new user with 200 points sees themselves at position #847 behind someone with 240,000 points. **Extremely discouraging.**
- No "nearby" filter — show ±20 positions around the user's current rank
- No weekly/monthly leaderboard — same users dominate forever (first-mover advantage)
- Pokémon count shown with sword icon in rows — context unclear to anyone who hasn't explored the Pokémon feature

### Serious User
- Cannot view a user's profile from the leaderboard — can only send a friend request
- No activity indicator on user rows (last active date)
- Friend activity feed doesn't exist after becoming friends

### Critic
- **`sendFriendRequest.isPending` shared across ALL rows** — this is the same clonePlan.isPending pattern for the third time. Click "Add Friend" on row 5, and EVERY "Add Friend" button in the entire list freezes while the request sends.
- Leaderboard ranked by `total_points_earned` not `available_points` — users who spent points on Pokémon still rank high. Is this intentional? A user who logs consistently AND spends points could rank lower than someone who logs less but never spends. The metric needs explicit documentation.
- Group selector uses `<select>` dropdown (LeaderboardPage.tsx:80) — the only place in the entire UI that uses a native dropdown. Everything else uses custom pill/chip selectors. Visual inconsistency.
- No pagination — presumably loads all public users in a single query. At scale this will hang.
- `Sword` icon (Lucide) is used for Pokémon count — semantic mismatch. Sword ≠ Pokémon.

### Developer / Security
| Issue | Severity | Location |
|---|---|---|
| `sendFriendRequest.isPending` shared across all rows | Critical | LeaderboardPage.tsx:147 |
| No pagination — full user list fetched | High | LeaderboardPage.tsx / useLeaderboard hook |
| `<select>` dropdown for group — inconsistent UI pattern | Medium | LeaderboardPage.tsx:79 |
| No invite code input field for groups | High | LeaderboardPage.tsx:91 |
| `Sword` icon for Pokémon — wrong icon | Low | LeaderboardPageParts.tsx:99 |
| `activeGroupId = null` on first render before groups load → double fetch | Low | LeaderboardPage.tsx:21 |

### Ideas / Improvements
- Fix `sendFriendRequest.isPending` to be per-user-id
- Add "Near Me" filter showing ±25 ranks around logged-in user
- Add weekly/monthly leaderboard tab
- Group invite code: add a text input field in the empty group state
- Tap any user row → view their public profile (stats summary)
- Replace `<select>` with custom chip/pill group selector
- Add "This Week" leaderboard tab (points earned in last 7 days)

---

## 7. PROFILE PAGE (ProfilePage.tsx)

### New User
- First-letter avatar is acceptable as placeholder but there's no path to add a real photo
- "Upload Plan File" row is visible immediately — no new user knows what this means or why they'd want it
- "Points Spent: 0" shown in the stats grid — implies there's a store/spend mechanism but there's no store anywhere in the app nav

### Casual User
- Display name edit pencil icon uses `opacity-0 group-hover:opacity-100` — **on mobile (touch), hover doesn't exist**. User cannot discover or trigger name editing on mobile unless they tap the name area directly and happen to hit the 14×14 invisible pencil.
- Stats grid: Streak / Points / Total Earned / Shields / Points Spent — "Total Earned" and "Available Points" are confusingly similar. Most users won't understand the distinction.
- No link to leaderboard rank from profile — user has no idea where they stand

### Serious User
- No data export
- No account deletion — GDPR concern for any EU users
- No notification preferences
- No theme or appearance settings
- "My Gym Setup" shows equipment count but no quick summary of what's selected — must navigate to /gear to see

### Critic
- `opacity-0 group-hover:opacity-100` pencil on display name is **invisible on touch devices** (all mobile users). This is the primary editable field on the page. Should be permanently visible as a small edit icon, or the name itself should look tappable (underline/border hint).
- "Points Spent" metric in stats grid — requires knowing there's a spending mechanism. Otherwise it just shows "Points Spent: 0" which is meaningless. Replace with "Sessions Logged" or "Active Days."
- Profile page has no social elements beyond friend requests — if the app has leaderboards, the profile should show the user's rank, sport ELO rating, and public stats.
- `FriendRequestsSection` (imported from ProfilePageParts) has no loading state guard — on first render it may flash empty then populate.
- There is no Settings page — all settings-adjacent items (visibility, equipment, plan upload) are dumped here. As the app grows this becomes unwieldy.

### Developer / Security
| Issue | Severity | Location |
|---|---|---|
| Pencil edit icon invisible on mobile (hover-only) | High | ProfilePage.tsx:92 |
| No error display for failed profile update | Medium | ProfilePage.tsx:82 |
| No account deletion option — GDPR concern | High | ProfilePage.tsx (feature gap) |
| `leaderboard_visibility as VisibilitySetting` — no runtime validation | Low | ProfilePage.tsx:29 |
| `CreatePlanFromFileModal` mounts instantly on file select — no loading transition | Low | ProfilePage.tsx:225 |
| No settings page — profile page doubling as settings | Medium | App-wide architecture |

### Ideas / Improvements
- Make display name always show a small edit icon (not hover-dependent)
- Add avatar upload (Supabase Storage)
- Replace "Points Spent" with "Sessions Logged" or "Active Days (90d)"
- Add rank badge: "You are #47 globally" with link to leaderboard
- Add "Settings" section: notification prefs, theme (when added), account actions
- Add GDPR-compliant account deletion flow

---

## 8. CROSS-CUTTING ISSUES (All Pages)

### Bugs Confirmed Across Multiple Pages

| Bug Pattern | Occurrences |
|---|---|
| `mutation.isPending` shared across all cards/rows — wrong button freezes | Dashboard goals, Plans clone, Leaderboard friend, (gym set rows pending) |
| `navigate(-1)` inconsistent navigation | Yoga ← vs Habits → `/log` |
| Missing pagination on list fetches | Leaderboard, possibly plan list |
| `pct * 3` wrong progress bar scale | Dashboard RangeSummaryView |
| `<select>` native dropdown inconsistent with rest of UI | Leaderboard group selector |

### Missing App-Wide Features

| Feature | Impact |
|---|---|
| Past-date logging | High — all 4 tracks assume today |
| Settings page | High — profile doing too much |
| Data export | Medium — power users need this |
| Account deletion | High — GDPR / legal |
| Push notification preference center | Medium — scattered across pages |
| Pagination on lists | High — leaderboard, exercise DB |

### Architecture Issues

| Issue | Severity |
|---|---|
| StatsPage.tsx at 2440 lines | High |
| No shared Sport metadata constant (SPORT_META / SPORT_LABELS split) | Medium |
| `navigate(-1)` vs explicit path — inconsistent across pages | Medium |
| Supabase errors with internal details leaked to users (yoga page) | Critical |
| No toast/notification system — errors shown inline with no dismiss | Medium |

---

## 9. PRIORITISED FIX LIST

### P0 — Must Fix Before Any Feature Launch
1. `sendFriendRequest.isPending` shared → per-user-id (Leaderboard)
2. `completeGoal.isPending` shared → per-goal-id (Dashboard)
3. Yoga internal Supabase migration error shown to users → friendly error message
4. Pencil edit icon invisible on mobile → permanently visible

### P1 — High Friction, Fix This Sprint
5. `DAY_LABELS ['T','T']` → `['Mo','Tu','We','Th','Fr','Sa','Su']`
6. `<details>` unstyled in archived habits → custom styled collapsible
7. `pct * 3` animation bug in RangeSummaryView → correct percentage
8. Past-date picker — at minimum for Yoga and Habits (sport already planned)
9. Leaderboard group tab — add invite code input field
10. Push notification "subscribed" banner auto-dismiss after 3 seconds

### P2 — UX Polish
11. StatsPage.tsx split into per-tab files
12. `SportKPIBlock` refactor to proper JSX component
13. Heatmap time range should filter to match selection (or explicit label)
14. Add today's completed tracks badge to LogTrackSelectPage tiles
15. Remove/hide "Work" coming-soon card until feature is built
16. Leaderboard: "Near Me" filter + weekly tab
17. Profile: replace "Points Spent" with meaningful metric
18. Yoga: friendly success screen with last-session comparison
19. Yoga: fix FLEX_EMOJIS and add text labels to mood scale

### P3 — Future / Nice to Have
20. Habit pause/skip feature (not just archive)
21. Numeric habit accumulation (add, not replace)
22. Drag-to-reorder habits
23. PR date shown alongside max weight in stats
24. Progressive overload chart per exercise
25. Profile: avatar photo upload
26. Account deletion flow (GDPR)
27. Data export
28. Settings page (extract from profile)
