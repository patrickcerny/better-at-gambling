# MASTER IMPLEMENTATION PROMPT — "BETTER AT GAMBLING"

> **Read this whole document before touching anything.** This prompt is addressed to you, the autonomous agent (lead designer, architect and senior developer) who will build this game from an empty folder to a Steam-ready build. It is self-contained: every design decision below has already been made. Where something is still unspecified, pick the sensible default, record it in `docs/DECISIONS.md`, and keep going.

---

## 0. Operating rules for you (read first, obey always)

1. **Build, don't describe.** You must actually create files, write code, run the engine, run tests, read the output, and fix failures. A response that explains how something *could* be done instead of doing it is a failure of this task.
2. **Work autonomously.** Do not stop to ask the user questions. When blocked, debug: read the error, search the code, add logging, write a minimal reproduction, try an alternative. If a third-party dependency is unavailable, fall back to the documented alternative in this prompt (§3.4) or write the smallest replacement yourself. Record every non-trivial decision in `docs/DECISIONS.md` (date, decision, reason, alternatives rejected).
3. **Playable build over complexity.** Always prefer the simplest implementation that satisfies the acceptance criteria. Never start a polish milestone while an earlier milestone's acceptance criteria fail. If a feature is threatening the schedule, cut it to its MVP form and log it in `docs/TODO.md` under "Deferred".
4. **Never claim something works unless you ran it.** "Done" means: implemented, tests written, tests executed and passing, and (for runtime features) the game actually launched and the feature exercised (headless run, automated scenario, or screenshot). In progress notes, distinguish clearly between `IMPLEMENTED+TESTED`, `IMPLEMENTED (untested: reason)`, and `NOT STARTED`. If you could not verify something (e.g., Steam overlay needs a real Steam client), say so explicitly.
5. **Keep the progress files current — they are your memory across context windows.**
   - `docs/PROGRESS.md`: current milestone, what was done in each session, test status, known bugs, the exact next step. Update it **at the end of every milestone step and before any long operation**.
   - `docs/TODO.md`: checkbox list of every task in every milestone (copy §13 into it at M0), plus "Deferred" and "Bugs" sections.
   - `docs/DECISIONS.md`: decision log.
   - When starting in a fresh context: **first read `docs/PROGRESS.md`, `docs/TODO.md`, `docs/DECISIONS.md`, then this prompt's relevant section**, run the full test suite to confirm the baseline, then continue from "Next step".
6. **Commit often** (if git is available): one commit per completed task with a clear message. Never commit secrets. Never add Claude/AI co-author trailers to commits; the user is the only author.
7. **Tests are mandatory.** Every system in §13 has listed tests. Write them alongside the code. The full suite must pass before a milestone is marked complete.
8. **Fictional currency only.** This game contains no real-money wagering, no purchasable currency, no cash-out, no crypto/NFTs, no loot boxes, no real-world rewards, no ads for gambling. Do not add any of these, ever, even as "future hooks".
9. **Stay data-driven and extensible.** New casino games, minigames, items, maps and modes must be addable by creating a new resource/script that implements a documented interface and registering it — never by editing a giant switch statement.
10. **Owner-only inputs are the exception to "don't ask".** The owner (Patrick) wants to be asked when something is genuinely unclear. Ask, in one short message with your recommended default, only for things you cannot decide or obtain yourself: VPS access/details, domain, Steamworks App ID and publisher Web API key, Steam test accounts, store/legal decisions. Keep working on everything else while you wait, and record what you are waiting on in `PROGRESS.md` under "Blockers".
11. **Treat the VPS with care.** It is the owner's machine and may run other things. Install only under dedicated paths (`/opt/better-at-gambling`, `/etc/better-at-gambling`), use a dedicated non-root user, open only the documented ports, never delete or reconfigure anything you did not create, and never put secrets (Web API key, SSH keys, passwords) in the repository, logs, progress files or chat; reference them by the env-file path instead.
12. **Time-box rabbit holes.** If one bug consumes more than ~45 minutes of effort without progress, write down what you know in `PROGRESS.md`, implement a workaround or simplification, add a "Bugs" entry, and move on.

---

## 1. What is being built

**Better at Gambling** is an online multiplayer (2–8 players, bots fill empty slots) casino **party game** for PC (Steam), inspired by the structure and chaos of Mario Party but with **free 3D movement** instead of a board.

- Players spawn in a stylized, colorful casino ("The Lucky Lounge") full of gambling stations: **Blackjack, Roulette, Slot Machines, Plinko** (MVP), plus **Big Wheel**, **Hi-Lo** and **Duck Derby** (post-MVP, architecture-ready). A **VIP mezzanine** opens mid-match for rich players.
- Everyone starts with **$1,000 in fictional chips**. The player with the **most chips when the match timer expires wins**.
- Players run around freely in **first person** (third-person toggle), talk over **proximity voice**, sit at stations, place bets, and constantly make **risk/reward** decisions in real time, while **grabbing, shoving, throwing** each other and **shaking chips out of knocked-out rivals** when the security guards aren't looking.
- At fixed intervals, the casino freezes and everyone is pulled into a **shared minigame**. Version 1 has one minigame: the **Casino Quiz** (exactly 3 questions, simultaneous answers, faster correct answers score more).
- Quiz ranking awards **items/power-ups** (luck boosts, sabotage, protection, theft, payout multipliers…), which players carry back into the casino and activate strategically, generating chaos and interaction.
- Core loop: **Casino phase → Minigame → Rewards → Casino phase → … → timer expires → Results → richest player wins.**
- Match lengths: **5, 10, 15, 30 minutes** of casino time.
- Pillars: fast pacing, easy to understand in 30 seconds, constant player interaction, funny moments, strategic item use, replayability, polished party-game feel.
- **Genre feel: a "friendslop" game.** Physical, wobbly, slightly janky bean characters you can grab, shove, throw and ragdoll (Gang Beasts); **proximity voice chat** with mouths that move when you talk (PEAK, R.E.P.O.); a casino where the chaos is physical as well as financial (Gamble With Your Friends). The funniest moments should come from friends physically messing with each other while money is on the line, not only from menus.

### 1.1 Inspirations and exactly what we take from each

| Game | What made it work | What we adopt | What we deliberately do NOT adopt |
|---|---|---|---|
| **Gamble With Your Friends** (TENSTACK, 2025) | Up to 6 friends in a first-person casino, 5-minute "days" against a loan shark's quota, one **shared** bank account ("one bad all-in ruins the run for everyone"), 17 games of chance incl. physical ones (Plinko, duck racing), 15+ "sketchy" items bought with tickets, higher casino floors unlock as you get richer, proximity voice, friends-only Steam invites, "digestible" 2–3 h of content | First-person casino with physical, diegetic games (**Plinko** in MVP, **Duck Derby** post-MVP); short timed rounds with a ticking clock; **a VIP floor that unlocks mid-match** for richer players; sketchy items; proximity voice; friends-first invites; tight, digestible scope; a later **co-op "Loan Shark" mode** with a shared bank account (§2.24) | We keep **competitive individual wallets** as the core mode (that is the user's concept); shared-debt co-op is an optional mode built on the same systems |
| **Gang Beasts** (Boneloaf) | Wobbly physics characters, grab with each hand, punch/shove/throw, knock-outs, environmental hazards, the lobby itself is a playground | **Grab / shove / throw / carry / knockout** with tumbly physics bodies; **shaking a knocked-out player makes them drop chips**; hazards (fountain, revolving door, security throwing you out); a **physical lobby** you mess around in while waiting | Full multi-limb active ragdoll fighting as the core; combat is a spice, not the game (shoving cannot kill or eliminate, and seated players are mostly safe) |
| **PEAK** (Aggro Crab & Landfall, 2025) | Proximity chat as a "gateway into role-playing", expressive animation ("friendslop is when the mouths move"), low barrier: pop in, have a full session, pop out; light and chaotic; stress that friends manage together; clear single goal; cosmetics earned by playing; cheap price | Proximity voice with **mouth flaps and face reactions**; **one clear goal per match** ("be the richest"); no power progression between matches, only **cosmetic unlocks** from playing; short sessions; low price point; stress spikes (Last Call, quiz, VIP closing) that players talk through | Long-form survival/climbing structure |
| **R.E.P.O. / Lethal Company / Content Warning** (friendslop wave) | Physics-heavy object handling, voice-driven comedy, low-fi charming art, short runs, everyone laughing at failure | Physics props (chip stacks, banana peels, tossable stools), **failure is funny** (big readable reactions to losses), low-fi charming art that is cheap to produce and reads well | Horror, permadeath |
| **Mario Party** | Board-game rhythm of free play → minigame → rewards, items that target others, comeback mechanics | The original core loop of this concept (§2.1, §2.9, §2.10) | Turn-based board |

These inspirations change the following sections versus a plain party game: camera and movement (§2.4), physical interaction (§2.4.1), lobby (§2.2), map (§2.3), games (§2.5), voice (§2.22), progression (§2.23), the optional co-op mode (§2.24), networking (§4) and milestones (§13).

---

## 2. Design summary (the full game design — implement exactly this unless a test or playtest proves it broken)

### 2.1 Match flow

```
Main Menu → Play Online: Create Party / Join by code / accept a Steam invite (room on the VPS, §4.0.1) → Lobby in the entrance hall (pick character color/hat, ready up, party leader picks duration + bots)
→ Loading → Intro (3 s camera fly-over + "Get rich!" banner)
→ CASINO PHASE (segment 1) → MINIGAME (Quiz) → REWARDS (item draft) → CASINO PHASE (segment 2) → … 
→ final segment ends with LAST CALL (final 60 s, all payouts x1.5)
→ TIMER ENDS: all open bets auto-resolve (blackjack auto-stands, roulette spins immediately, slots finish)
→ RESULTS (podium, final money, fun awards) → Rematch / Back to lobby
```

**Match timer** counts **casino time only**; it pauses during minigames and rewards. Minigame schedule:

| Duration | Minigames | Casino segments | Segment length | Quiz occurs at casino time |
|---|---|---|---|---|
| 5 min | 2 | 3 | 1:40 | 1:40, 3:20 |
| 10 min | 3 | 4 | 2:30 | 2:30, 5:00, 7:30 |
| 15 min | 4 | 5 | 3:00 | every 3:00 |
| 30 min | 7 | 8 | 3:45 | every 3:45 |

Formula: `segment = duration / (minigames + 1)`. Store in `data/match_presets.tres`, never hard-code.

**Phase transitions:** 10 s before a minigame a banner + ticking SFX warn "QUIZ TIME in 10…"; betting windows that would not finish are blocked ("Table closing!"). When the phase ends, any unresolved round resolves instantly (server-side auto-resolution rules per game, §2.5). Players are then faded into the minigame scene. After rewards, everyone respawns at their previous position (or nearest free spawn point) with 3 s of spawn protection (no items can target them).

**Final "LAST CALL":** last 60 s of the last segment: music speeds up, lights turn red/gold, all winnings ×1.5 (applied after item multipliers, before rounding). Purpose: comebacks and a dramatic finish.

**Win condition:** highest money at the end. Tiebreakers: (1) higher total quiz points across the match, (2) higher biggest single win, (3) shared placement. Nobody is ever eliminated.

**Bankruptcy safety net ("House Comp")**: if a player has less than the lowest table minimum ($10) and no bets in play, the house gives them a comp of **$150**, at most once per casino segment, with a funny announcement ("The house feels sorry for you"). Keeps everyone playing.

### 2.2 Lobby

- The party leader creates a **room on the VPS** plus a matching **Steam lobby** (friends-only by default, also invite-only/public) for invites and presence (§4.0.1). Friends join through the in-game "Invite friends" button, the Steam overlay, or "Join Game" with zero menus in between; a 5-character **room code** also works. For development, `--server` + `--connect <ip:port>` and `AUTH_MODE=dev` allow testing without Steam. (Wherever this document says "host" for lobby settings, read "party leader".)
- **The lobby is a physical place** (Gang Beasts/PEAK style): the casino's **entrance hall**. Players spawn in it as soon as they join, can walk, grab, shove and talk (proximity voice works here), and change cosmetics at a **mirror wardrobe**. Readying up = standing on your colored **"READY" pad**. The host's **settings board** is a big in-world sign the host interacts with (it opens the settings panel). When everyone is on a pad, the doors to the casino open with a 3 s countdown. A traditional 2D lobby panel (Tab) mirrors all of this for accessibility and gamepad users.
- Lobby screen shows up to 8 slots: player name, chosen color (8 distinct colorblind-safe colors), hat (6 placeholder hats), ready state, ping. Empty slots can be set by the host to **Bot (Easy/Normal/Hard)** or Closed.
- Host settings: duration (5/10/15/30, default 10), bots on/off and difficulty, items on/off (for "pure gambling" mode), quiz category filter (all by default).
- Match starts when all humans are ready and at least 2 participants (humans + bots) exist; host presses Start → 3 s countdown.
- Join-in-progress: **not allowed** except for reconnecting players (§2.12).
- After results: "Rematch" keeps the lobby; "Leave" returns to menu.

### 2.3 Casino map — "The Lucky Lounge" (MVP map)

Single-floor 3D map, ~44 m × 32 m, readable from a high camera. Layout (top view, north = top):

```
+------------------------------------------------------------+
|  SLOT ROW A (6 machines)        |  PLINKO WALL (2 boards)     |
|  SLOT ROW B (6 machines)        |  Big Wheel stage (post-MVP)|
|---------------------------------+----------------------------|
|           [ROULETTE PIT: 2 tables, 6 spots each]             |
|                 ( central fountain/landmark )                |
|---------------------------------+----------------------------|
|  BLACKJACK LOUNGE: 3 tables x 4 seats | BAR (quiz entry deco)|
|                                        | Hi-Lo tables (later)|
|  ENTRANCE HALL = LOBBY (ready pads, wardrobe mirror, 8 spawns)|
+------------------------------------------------------------+
   Stairs + glass elevator up to the VIP MEZZANINE (above the roulette pit):
   2 high-limit blackjack seats + 1 high-limit roulette + 2 "Diamond" slots
```

- **Stations (MVP):** 12 slot machines, 2 roulette tables (6 betting spots each), 3 blackjack tables (4 seats each), 2 Plinko boards. Each station has an `InteractionArea` and seat/stand transforms.
- **VIP Mezzanine (GWYF-style "higher floor"):** closed at match start. It **opens after the first quiz**. A bouncer NPC at the velvet rope only lets in players holding **≥ $2,000** (scaled by the limits multiplier); others are physically pushed back with a funny bark. VIP stations have **×3 table limits** and the "Diamond" slots use a richer paytable with the same RTP but more variance. Purpose: rich players get a place to snowball *and* a place where they are cornered: the mezzanine has a low railing, so shoving someone over it is possible (they tumble down to the roulette pit unharmed but lose their seat and drop chips like a knockout, §2.4.1).
- Walkable floor with obstacles (pillars, plants, velvet ropes, tossable bar stools) forming lanes; corridors at least 2.5 m wide so players can collide and scuffle but never get stuck.
- **Hazards and physical props (Gang Beasts spice, never lethal):** the central **fountain** (players thrown in get soaked: 3 s slow + splash, funny), a **revolving door** at the entrance that spins players around, **tossable bar stools and chip stacks** (RigidBody3D props), slippery **spilled-drink puddles** spawned when a waiter NPC trips.
- **Security guards (2 NPCs, patrol routes):** if a guard sees a player knock out or shake another player within 8 m line-of-sight, the guard grabs the attacker and **throws them out through the revolving door** (respawn at entrance after 4 s, no money loss). Rough play is allowed, but it is risky near guards, which creates sneaking and "distract the guard" moments.
- **Hot Table event:** every 45–60 s (random, server-chosen) one station (or one slot row) becomes "HOT" for 30 s: spotlight beam, flames particle, HUD arrow, payouts ×1.25 there. This gives movement a purpose and creates races (and shoving matches for the seat).
- **Dropped chips:** physical chip pickups (small RigidBody3D chip piles) appear when a player slips, is knocked out and shaken, or gets robbed (§2.4.1, §2.8). Anyone can run over them to collect. Despawn after 20 s.
- Navigation mesh for bots and NPCs (`NavigationRegion3D`).
- Map is a scene `maps/lucky_lounge/lucky_lounge.tscn` with a `MapDefinition` resource listing spawn points, stations, hot-table candidates, hazards, guard routes and the VIP zone, so new maps plug in.

### 2.4 Player characters, movement & camera

- **Characters:** wobbly "bean" bodies (capsule body, big googly eyes, a **mouth that opens with voice volume**, hat, player color, short noodle arms with mitten hands). Expressiveness is a pillar: eyes widen on big wins, the mouth droops on losses, characters cheer, slump and flail automatically on money events, and 8 **emotes** (wheel on G / D-pad down: wave, point, cheer, cry, facepalm, dance, "come here", taunt).
- **Body model (achievable "active ragdoll lite"):** while standing, a `CharacterBody3D` drives movement, and the visual body uses **procedural wobble** (spring-damped lean on acceleration, head bob, arm IK toward grab targets, squash/stretch). When knocked out, thrown or slipping, the player switches to a **ragdoll state**: a `RigidBody3D` torso with head and arms as small rigid bodies on `Generic6DOFJoint3D`/`PinJoint3D` joints (5 bodies max, not a full skeleton). When it settles (or after max 2.5 s), the player gets up with a wobble animation. Full multi-bone active ragdoll is explicitly out of scope.
- Walk 5.5 m/s, sprint 8 m/s (Shift / L3, stamina 4 s, regenerates 1 s per 2 s), jump 1.1 m (Space / A), acceleration 30 m/s², slightly slippery deceleration for comedy (tunable).
- **Interact** (E / gamepad X) near a station → sit down or step up (camera eases to the station view, station UI opens). **Leave** (Q / gamepad B while seated) → stand up. Leaving mid-round: your bet stays in and auto-resolves by the game's auto-rule.
- Movement authority: **client-authoritative movement while standing** with server validation (server rejects positions implying speed > 1.5× sprint or through walls; snaps back). **Server-authoritative physics while ragdolled, grabbed or thrown** (§4). Everything involving money is **server-authoritative**.

#### 2.4.1 Physical interaction (grab, shove, throw, knock out, shake)

- **Grab** (hold LMB / RT; each player has one combined grab, not per-hand): reaching arms extend toward the crosshair; grabbing another standing player **holds them** (both slowed to 50%; the grabbed player breaks free by mashing jump: 6 presses, or automatically after 3 s). Grabbing a prop (stool, chip pile, banana) picks it up.
- **Shove** (RMB / RB tap, 1.2 s cooldown): short-range push (2 m knockback). A shove while the target is mid-air, or **a second hit within 1.5 s**, knocks them over (ragdoll 1.5 s).
- **Throw:** release grab while moving or press RMB while holding → throws the held player/prop in look direction (6 m/s + up 3 m/s). A thrown player ragdolls on landing. Thrown props can knock over players they hit.
- **Knock out** (dazed state, stars over head, 2.5 s): caused by being thrown into a wall/fountain, falling from the mezzanine, being hit by a thrown stool, or 3 shoves within 4 s.
- **Shake for chips:** grabbing a **knocked-out** player and mashing interact shakes them; each shake drops **2% of their money** (min $10) as physical chip piles, max **8% per knockout** (cap $400 × limits multiplier). The victim can still break free when they wake up. Chips can be picked up by anyone, including the victim.
- **Seated players are protected from grab, shove and throw** (they are "under casino protection") **except** by the Bouncer item (§2.8) or a guard. This keeps gambling playable while making walking between tables the dangerous part. Players standing at Plinko or roulette spots *are* grabbable, which is part of the fun at those shared stations.
- **Anti-grief rules:** spawn protection 3 s after respawn/minigame; after being knocked out a player gets 4 s of knockout immunity; "away" players (§2.12) are intangible; a player cannot be shaken by the same attacker twice within 20 s. All values in `balance.tres`.
- Every physical interaction emits a `GameEvent` (`player_grabbed`, `player_shoved`, `player_thrown`, `player_knocked_out`, `chips_shaken_out`) for stats, awards, achievements and the event feed.

#### 2.4.2 Camera

- **First-person by default** (FOV 85, adjustable 70–110), like Gamble With Your Friends and PEAK, so friends' faces, mouths and flailing bodies fill the screen and proximity voice feels personal. Your own arms and mitten hands are visible when grabbing/reaching. Optional gentle head bob (off when "Reduce motion" is on).
- **Third-person toggle** (V / gamepad View button): over-the-shoulder spring-arm camera at 3.5 m with collision, for players who want to see their own ragdoll antics or get motion sick in first person. The camera **auto-switches to third person while you are ragdolled** (so you watch yourself tumble), then returns to your chosen mode.
- **Seated at a station:** camera eases (0.4 s) to the station's `CameraAnchor` (a seated first-person view of the table/machine), and the station UI appears. Mouse look is limited to ±40° so you can glance at your neighbors.
- **Spectator glance:** while seated, hold Tab to see the leaderboard.
- Screen shake on big wins/losses and knockouts, toggleable via "Reduce motion".

### 2.5 Casino games (rules are authoritative, implemented as pure logic classes)

All games run on the **server**, use the match's seeded RNG via the Luck system (§2.7), and expose: `can_join`, `place_bet`, `player_action`, `tick(delta)`, `auto_resolve`, `get_public_state`, `get_private_state(player)`. Table limits scale with match progress so late-game stakes rise: limits multiplier = `1 + 0.5 × (segment_index)` capped at 3 (e.g., blackjack min/max $10/$200 → late $30/$600).

#### Blackjack (MVP)
- 3 tables, 4 seats each, one shared dealer per table. 6-deck shoe, reshuffle at 75% penetration.
- **Simultaneous play** for pace: each round = Betting window **8 s** (starts when first player bets; anyone seated may bet) → deal → all seated players act **simultaneously** (each 10 s action timer; timeout = stand) → dealer plays → payout → 2 s result display → next round.
- Rules: dealer stands on soft 17; blackjack pays 3:2; double on any first two cards; **split** once (pairs only, post-MVP polish task in M7 — MVP: no split); no insurance; no surrender.
- Limits: min $10, max $200 (× limits multiplier).
- Auto-resolve: unfinished hands stand; dealer completes.
- Display: other seated players' hands visible (social drama).

#### Roulette (MVP)
- European single-zero wheel (0–36). 2 tables, 6 standing spots each. Shared spin cycle: **15 s betting** → 4 s spin animation → result → 3 s payout display → repeat. Spins only cycle while at least one player is at the table.
- Bet types (MVP): straight number (35:1), red/black (1:1), odd/even (1:1), low 1–18 / high 19–36 (1:1), dozens (2:1), columns (2:1). Multiple bets per spin allowed; total per spin ≤ table max.
- Limits: min $10 per bet, max $300 total per spin (× multiplier).
- All players' chips are visible on the board in their color.
- Auto-resolve: phase end → spin immediately.

#### Slot machines (MVP)
- 12 machines, 1 player each. 3 reels × 1 payline, spin = 1.6 s (reels stop left to right; skip-stop by pressing Spin again after 0.5 s). Bet sizes: $10/$25/$50/$100 (× multiplier) selectable.
- Symbols with weights per reel (initial): Cherry 9, Lemon 8, Bell 6, Bar 5, Seven 3, Clover 2 (wild, substitutes any), Diamond 1.
- Paytable (multiplier of bet): 3× Diamond 100, 3× Seven 40, 3× Bar 20, 3× Bell 12, 3× Lemon 8, 3× Cherry 6, any 2 Cherries 2, any 1 Cherry (leftmost) 1 (push).
- **Target RTP ≈ 101% at neutral luck** (see §2.6 economy). Tune weights with the Monte-Carlo test (§13, M1) until 100.5%–102% with hit rate ≈ 30–40%.
- Auto-resolve: spin completes instantly.

#### Plinko (MVP, physical game inspired by Gamble With Your Friends)
- 2 big wall-mounted boards, each with 2 standing drop spots. Choose a bet ($10/$25/$50/$100 × multiplier) and a risk row (Low / Medium / High), then **physically drop a big chip** from the top: the chip is a real `RigidBody3D` bouncing through pegs into 13 slots with multipliers.
- **Outcome determinism:** the *result slot* is decided by the server RNG first (weighted per risk row, luck-rerollable with quality = multiplier), and the physics drop is then **steered** toward that slot (small invisible lateral impulses at each peg row, computed on the server, so it still looks natural). Clients replay the server's recorded chip path (positions at 30 Hz) for the visual, so every client sees the same bounce. Money never depends on client physics.
- Multipliers (initial, tune to RTP 100.5–102%): Low `[5, 2, 1.5, 1.1, 1, 0.6, 0.5, 0.6, 1, 1.1, 1.5, 2, 5]`; Medium `[13, 4, 2, 1.4, 0.8, 0.5, 0.3, 0.5, 0.8, 1.4, 2, 4, 13]`; High `[60, 12, 3, 1.2, 0.4, 0.2, 0.2, 0.2, 0.4, 1.2, 3, 12, 60]`. Slot probabilities via a binomial-ish weight table in `plinko.tres`.
- Drop cadence: one chip per player every 2.5 s. The board is shared, so a crowd forms and players standing there **can be grabbed and shoved away mid-drop** (the chip still lands; the bet still pays).
- Auto-resolve: chips in flight finish instantly.

#### Progressive jackpot (MVP, simple)
- 1% of every slot and Plinko bet feeds a casino-wide **progressive jackpot** displayed on a giant neon counter (seeded at $500 × multiplier). Three Diamonds on a slot (or the far-edge High slot on Plinko with 1-in-4 chance) wins it. It is house money (not taken from players beyond the 1% feed, which is accounted for in RTP). Everyone hears the siren: big shared moment.

#### Big Wheel (post-MVP, M10) — wheel with 54 segments paying ×1 up to ×40 (joker); shared spin like roulette, players physically spin the wheel's handle (strength = how long they held, cosmetic only).
#### Hi-Lo (post-MVP) — guess if next card is higher/lower, chain up to 5 for growing multiplier, cash out anytime.
#### Duck Derby (post-MVP, GWYF-inspired shared spectacle) — every 90 s a 6-duck race runs on a track along the bar; bet on a duck (odds shown, RTP ~101%), the race is server-simulated and replicated; players can throw props onto the track for comedy (props are cosmetic and do not change the server-decided result, to keep it fair).

Each game is a folder `games/<game_id>/` containing logic (`*_logic.gd`, pure, no Nodes), station scene, UI scene, `GameDefinition` resource. Registered in `data/registry/games.tres`.

### 2.6 Economy

- Start money $1,000. Money is an integer (whole dollars). All arithmetic server-side, rounding **down** for payouts after multipliers (except pushes, which are exact).
- **Games are tuned slightly player-favorable (RTP 100.5–102% at neutral luck, ignoring Hot Table and Last Call).** Rationale: in a party game, gambling must be the engine of growth; standing still should lose to playing. Variance and decisions separate players, not house edge. Blackjack with these rules under basic strategy is ~99.5% RTP, so add the **"Dealer Bust Bonus"**: when the dealer busts, winning hands are paid 1.1:1 instead of 1:1 (rounded down). Validate via simulation that basic-strategy RTP lands in range; tune the bonus (config value) if needed.
- Roulette: European roulette RTP is 97.3%. Apply a flat **"house generosity" bonus** of +5% on all winning roulette payouts → ≈ 100.5–101%. Validate by simulation.
- Expected money flow per 10-minute match for an active player: ±$1,000–$4,000 swings; median final ~$1,500–2,500; leader typically $3,000–8,000. Verify with bot simulation (M9) and tune limits multiplier if leaders exceed ~$15,000 or medians fall below $800.
- **Quiz cash prizes** (on top of items): 1st $150, 2nd $100, 3rd $50 (× limits multiplier).
- **No transfers between players** except via items (steal, Robin Hood) and dropped chips.
- All money changes go through one server function `Economy.apply(player_id, amount, reason: StringName, source_id)` that emits a `money_changed` event (used for UI, stats, awards, logs, anti-cheat audit). Nothing else may modify money.

### 2.7 Luck system

Luck is a transparent, bounded modifier that influences RNG **only through rerolls**, so it plugs into any game generically.

- Each player has `luck` = sum of active luck effects, clamped to **[-3, +3]**. Game-specific luck (e.g., "slots luck") is added only inside that game, same clamp.
- **Reroll mechanism:** whenever a game draws a random outcome that affects only one player (a card dealt to their hand, their slot spin), the server calls `LuckRng.draw(player, generator, quality_fn)`:
  - With luck L > 0: with probability `0.12 × L`, draw a second candidate and keep the one with **higher** `quality_fn` for that player.
  - With luck L < 0: with probability `0.12 × |L|`, draw a second candidate and keep the **lower** one.
  - Otherwise single draw.
- Quality functions per game: Slots = payout of the result. Blackjack = for a card dealt to the player's hand: the resulting non-bust total (bust = −1; a natural blackjack = 22). Since the dealer is shared, **dealer cards are never luck-modified**. The rejected candidate card goes back into the shoe at a random position.
- **Roulette is shared**, so luck applies as a **per-player "near-miss save"**: if a player with L > 0 loses a straight-number bet and the result is adjacent on the wheel to their number, with probability `0.12 × L` they get a "Lucky neighbor" payout of 5:1 (on that bet). With L < 0, with probability `0.12 × |L|` a winning even-money bet pays 0.9:1 instead of 1:1 ("Jinxed!"). Show these explicitly with special VFX so players *see* luck.
- Every luck-modified outcome is flagged in the result event so UI shows a 🍀 / 🐈‍⬛ flourish. Luck must feel real but visible.
- Luck HUD: a clover meter (−3…+3) next to the player's money, with active effects and timers.

### 2.8 Items & sabotage

- **Inventory:** 3 slots. Keys 1/2/3 (gamepad: D-pad left/up/right) to activate. If full when receiving an item, the player chooses which to discard (5 s, default: discard oldest).
- Items are usable only in casino phase. Activation is server-validated. **Targeted items** open a quick target picker (player portraits with money, arrows/stick to cycle, confirm; 4 s timeout = cancel) or auto-target if only one valid target; some require **proximity** (target within 4 m), which drives movement and chasing.
- Cooldown: 3 s between any item activations per player. Each player can be targeted by at most one negative item per 5 s ("grace"), to avoid dogpile frustration.
- Protection rules: **Bodyguard** blocks the next negative item; **Mirror** reflects it to the attacker; spawn protection after minigames blocks everything for 3 s.

| ID | Name | Rarity | Target | Effect | Duration |
|---|---|---|---|---|---|
| lucky_clover | Lucky Clover | Common | Self | Luck +2 | 45 s |
| black_cat | Black Cat | Common | Any player | Target luck −2 | 45 s |
| hot_hands | Hot Hands | Common | Self | Blackjack luck +3 and peek dealer hole card | next 3 blackjack hands (expires end of segment) |
| loaded_reels | Loaded Reels | Common | Self | Slots luck +3 | next 8 spins (expires end of segment) |
| double_down | Double Trouble | Rare | Self | Next winning payout ×2 (stacks with Last Call/Hot Table multiplicatively) | 60 s or first win |
| golden_chip | Golden Chip | Common | Self | Next losing bet is refunded | 60 s or first loss |
| pickpocket | Pickpocket | Rare | Player within 4 m (works on seated players too) | Steal 12% of target's money (min $50, max $500, never more than they have). Your character visibly reaches into their pocket; the victim gets a 1 s "HEY!" reaction | Instant |
| banana_peel | Banana Peel | Common | Placed at your feet | First other player to walk over it slips: drops 6% of money (min $20, max $300) as chip pickups scattered 3 m around; stunned 1.2 s | 60 s on floor |
| bouncer | Bouncer | Rare | Any seated player | A bouncer NPC walks up and **physically throws the target out of their seat** (ragdoll) after their current round resolves; they cannot sit anywhere for 12 s | Instant |
| grease | Butter Fingers | Common | Player within 6 m | Target's hands are greasy for 20 s: they cannot grab and drop anything they hold; their next shake-for-chips victimization drops double | 20 s |
| bribe | Bribe the Guard | Rare | Self | For 30 s security guards look the other way when you rough people up (knockouts, shaking) | 30 s |
| boxing_glove | Spring Glove | Common | Self | Your next 3 shoves knock players over instantly with a huge "BOING" and fly-back | 3 uses / 45 s |
| bodyguard | Bodyguard | Common | Self | Blocks next negative item | 90 s |
| mirror | Mirror Mirror | Rare | Self | Reflects next negative item to its user | 60 s |
| robin_hood | Robin Hood | Legendary | Leader (auto) | Takes 8% of the current leader's money (max $800) and splits it equally among all *other* players (including you). Cannot be used if you are the leader. | Instant |
| jackpot_magnet | Jackpot Magnet | Legendary | Self | For 30 s, every other player's win at any station gives you 10% of it as a bonus paid by the house (not taken from them) | 30 s |
| wild_card | Wild Card | Common | — | Becomes a random item (weighted by rarity, excluding Wild Card) on activation | — |

**MVP item set (M5):** lucky_clover, black_cat, loaded_reels, hot_hands, double_down, golden_chip, pickpocket, banana_peel, bodyguard, mirror, boxing_glove. The remaining six are M10 content tasks. (Bodyguard and Mirror also protect against physical interactions from an attacker who used an item that round: Bodyguard absorbs one knockout; Mirror is items only.)

Every item is a `ItemDefinition` resource (`id, name, description, icon, rarity, target_mode, requires_proximity, range, is_negative, duration, params`) + an `ItemEffect` script implementing `can_activate(ctx)`, `activate(ctx)`, `on_event(event)`, `on_expire()`. Effects hook into a central **ModifierStack** (§3.6) rather than into game code.

Chaos feedback is essential: every item activation triggers a big readable banner to all players ("🐈‍⬛ ANNA jinxed BOB!"), an SFX sting, and a VFX on the affected character (cloud of black cats, golden sparkle, etc.).

### 2.9 Minigame system & Casino Quiz

**Minigame framework:** `MinigameDefinition` resource + `MinigameBase` scene/script with lifecycle `setup(players, rng, params) → intro() → run() → finished(scores: Dictionary[player_id → int])`. The `MinigameDirector` picks the next minigame (V1: always Quiz; later: weighted random without immediate repeats), loads its scene for everyone, and converts scores into a ranking.

**Casino Quiz (V1 minigame):**
- Setting: game-show stage; each player stands at a podium with their color; host character ("Lucky the dealer cat") reads questions (text + bark SFX, no VO needed).
- **Exactly 3 questions.** Each question: 2 s "get ready" → question + 4 answers appear simultaneously for everyone → **12 s** answer window (or until all players answered) → 2.5 s reveal (who answered what, correct answer highlighted, points fly up) → next.
- Input: 4 answer buttons mapped to 1/2/3/4, mouse click, gamepad face buttons (A/B/X/Y with colored shapes ▲●■◆ for colorblind support). **One answer only, no changes.**
- **Scoring:** correct = `500 + round(500 × remaining_time / 12)` (500–1000); wrong or no answer = 0. Time measured on the **server** from the moment the server broadcast the question (+ the client-reported render delay is ignored; we use server receive time minus question send time minus that client's half-RTT smoothed estimate, clamped to ≥0, to be fair to higher-ping players).
- Running scoreboard after each question; after question 3, final ranking with fanfare.
- Ties: equal points → faster cumulative correct-answer time wins; still tied → shared rank, both get the higher rank's reward.
- **Question bank:** `data/quiz/questions_en.json`, ≥ 150 questions at M4 completion (≥ 60 for the MVP threshold), categories: `casino_trivia`, `cards_and_dice`, `luck_and_superstition`, `game_rules` (about this game's own mechanics — teaches players), `silly` (absurd humor). Schema: `{ "id", "category", "difficulty": 1-3, "question", "answers": [4], "correct_index", "explanation"? }`. Questions are shuffled; answers are shuffled per question (server decides order, same for all players). No question repeats within a match.
- **Dynamic questions (2 templates in MVP, more later):** generated from match stats, e.g. "Who has won the most at slots so far?", "How much money does the current leader have? (4 numeric options)". At most 1 dynamic question per quiz, 40% chance.
- Bots answer with difficulty-dependent accuracy (Easy 40%, Normal 60%, Hard 80%) and response time 2–9 s.
- **Anti-cheat:** the correct index is **never sent** to clients before the reveal.

### 2.10 Rewards (after each minigame)

Ranking → rewards ("item draft"):
| Placement | Reward |
|---|---|
| 1st | Pick 1 of 3 offered items (weighted Rare/Legendary), **plus** 1 random Common, **plus** $150 cash |
| 2nd | Pick 1 of 3 items (weighted Common/Rare) + $100 |
| 3rd | Pick 1 of 2 Commons + $50 |
| 4th+ | 1 random Common |
| **Last place (if ≥3 players)** | Additionally 1 **"Underdog"** guaranteed Rare item (comeback mechanic) |

Draft is simultaneous; 8 s to pick (default: first option). Cash scales with the limits multiplier. Item weight tables live in `data/items/loot_tables.tres`. If items are disabled in lobby settings, rewards are cash only (×2 values).

### 2.11 Rankings & results

- HUD live leaderboard (top-right): rank, avatar color, name, money, small arrows on change; leader wears a golden crown in-world (makes them the obvious target).
- Results screen: 3-podium scene with character animations (dance/cry), final money, then **fun awards** computed from stats: "High Roller" (biggest single bet), "Jackpot!" (biggest single win), "Glass Cannon" (biggest single loss), "Chaos Agent" (most items used on others), "Punching Bag" (most negative items received), "Quiz Wiz" (most quiz points), "Banana Bandit" (most slips caused), "Comeback Kid" (lowest point → final rank delta), "Bouncer's Favorite" (thrown out by security most), "Fountain Regular" (most times in the fountain), "Sticky Fingers" (most chips shaken out of others), "Ragdoll" (most knockouts suffered), "Chatterbox" (most time talking on voice, opt-in stat). Show 3–4 awards per match.
- Match summary (money-over-time line graph per player) — M7 polish.

### 2.12 Disconnects & reconnects

- Every player has a stable `player_uid`: SteamID64 in Steam mode; a random UUID persisted in `user://profile.cfg` in ENet mode. Server maps `peer_id ↔ player_uid`.
- **Client drops:** their avatar turns translucent with a "zzz" bubble and stays where it is ("Away"), money preserved, open bets auto-resolve, intangible (cannot be grabbed, shoved or shaken), cannot be targeted by items or slip (protected, to avoid exploiting disconnected players), excluded from quiz (scores 0) and from minigame rewards while away. A bot does **not** take over (keeps fairness simple). Grace window: **until match end**.
- **Reconnect:** the player rejoins the same lobby (Steam: lobby invite/rich presence "Join Game"; ENet: same IP) → server recognizes `player_uid` → sends a full `MatchSnapshot` → client loads straight into the current phase. Must be tested.
- **Party leader disconnect:** nothing breaks, because the room runs on the VPS; leadership passes to the longest-connected player. **Server/room crash:** clients show "Server error" with the last known standings (marked "Unfinished"), then the main menu; the crash log is kept on the VPS.
- Network timeouts: ENet/Steam peer timeout 10 s; UI shows a "Connection lost — reconnecting…" overlay after 3 s of silence.

### 2.13 Tutorial & onboarding

- **First-launch interactive tutorial** (offline, ~3 minutes, offered but never forced, skippable): walk, jump, grab and shove a dummy, throw it into the fountain, shake a knocked-out dummy for chips (a guard watches and explains the rule) → sit at slots and spin → play a blackjack hand → place a roulette bet → receive and use an item (Lucky Clover, Black Cat on a dummy bot) → a 1-question quiz → done. Built as a scripted single-player match variant (`modes/tutorial/`) reusing real systems (local server in-process).
- **Contextual hints** (toggleable): first time near each station shows a 1-line rules card ("Blackjack: get closer to 21 than the dealer. Pays 1:1, Blackjack 3:2"). Every station UI has a "?" button with full rules.
- **Loading-screen tips** (≥ 20 tips).
- **Practice mode:** solo vs bots with any duration (same as hosting a local-only lobby).

### 2.14 UI/UX

Godot `Control` UI with a single theme resource `ui/theme/main_theme.tres`: Art-deco gold + neon magenta/teal on deep purple; rounded chunky panels; big readable fonts (UI scale 75–150%). All UI fully navigable with **mouse, keyboard, and gamepad** (focus neighbors set, visible focus outline).

Screens: Splash → Main Menu (Play Online → Create Party / Join by Code / Rejoin Match, Practice vs Bots, Tutorial, Settings, Credits, Quit; dev builds also show Join by IP) → Lobby → Loading → In-game HUD → Minigame UI → Reward Draft → Results → Pause menu (Resume, Settings, How to Play, Invite Friends, Leave Match).

**In-game HUD:** minimal, so the 3D world and friends' faces stay the focus: a small center dot crosshair that becomes a hand icon over grabbable things, money (large, animated count-up/down with green/red flashes), luck meter, 3 item slots with key hints, match timer (big, pulses in last 10 s of a segment and during Last Call), next-quiz countdown, leaderboard, event feed (left, last 5 events: wins, items, slips), Hot Table arrow indicator, interaction prompt ("[E] Play Blackjack — Min $10").

**Betting UI (shared component `ui/betting/bet_panel.tscn`):**
- Chip tray: $10/$25/$100/$500 chip buttons (disabled if unaffordable or above table max), "Clear", "Repeat last bet", "×2", "Max". Current bet total shown, table min/max shown, remaining money preview ("after bet: $740").
- Keyboard: 1–4 select chip value, Space/Enter confirm (deal/spin), Backspace clear, R repeat. Gamepad: LB/RB cycle chip, A place, X clear, Y repeat.
- Roulette: clickable board (mouse) / cursor moved by stick or arrows with chip placement; shows all players' chips.
- Blackjack: action buttons Hit (H) / Stand (S) / Double (D) / Split (P, when added), with the 10 s action timer ring.
- Slots: bet size selector + big SPIN button (Space), auto-spin ×10 option (stops on big win or when money < bet).
- Results always shown with a clear delta: "+$240" in green / "−$100" in red, plus luck/item flourishes.

### 2.15 Audio

- Buses: Master → Music, SFX, UI, Ambience, Voice. Volume sliders per bus.
- Music: lobby loop, casino loop (lounge-jazz/funk, ~110 BPM), Last Call variant (faster/intense), quiz game-show loop, results fanfare. Crossfade 1 s between phases.
- SFX: footsteps, jump, sprint breath, grab/whoosh, shove "oof", throw, ragdoll thuds (soft, comedic), knockout birdies, Spring Glove "BOING", fountain splash, guard whistle + "OUT YOU GO!" bark, cartoon voice gibberish barks for NPCs, Plinko peg plinks (pitch rising with each row), chip clicks (bet), card deal/flip, roulette ball rolling/clatter, slot reel spin/stop/jingles (small/big/jackpot), win/lose stingers, item activation stings (one per item), slip, coin scatter/pickup, quiz tick/correct/wrong, UI hover/click/back, countdown beeps, crowd "ooh/aah" on big wins.
- Ambience: casino murmur, distant slots.
- **Voice chat audio** (§2.22) is a separate `Voice` bus with its own volume, ducking music by 3 dB while anyone near you is talking.
- Placeholder audio: generate with a script (§11.3) — never block on missing audio.

### 2.16 Visual style & animation

- **Low-fidelity charm on purpose** (friendslop look): simple, slightly goofy low-poly, cheap to produce and endlessly readable, where comedy comes from motion, faces and physics rather than detail. Stylized low-poly, saturated colors, toon/cel shading (a simple `toon.gdshader` with 3-step ramp + rim light), bloom/glow on neon signs, warm spotlights. Readability first: stations have bold silhouettes and colored floor rugs per game type (Blackjack = green, Roulette = red, Slots = gold).
- Characters: bean/capsule body, 8 player colors, googly eyes, a mouth driven by voice amplitude (and by emotes/reactions for bots and muted players), mitten hands on noodle arms, simple hats (top hat, cowboy, crown (leader only override), visor, beanie, party cone) and unlockable cosmetics (§2.23). **"The mouths move"** is a hard requirement: a talking player's mouth must visibly flap in sync with their voice for everyone nearby.
- Animations (code-driven tweens and procedural motion where no rigged assets exist): idle bob, walk wobble/squash/stretch, arm reach IK, grab/hold poses, ragdoll get-up, knockout stars, flailing while thrown, guard carry-and-toss, slip (flip + stars), sit, cheer (jump), sad (shrink + rain cloud), card deal arcs, chip slides, roulette wheel + ball physics-fake (tweened path), slot reels (scrolling UV / rotating cylinders), money popups (floating "+$500" text), confetti, crown shine.
- Camera and UI juice: tweens with overshoot, number tick-ups, hit-stop (0.05 s) on jackpots, screen shake (optional).

### 2.17 Settings

`SettingsManager` autoload saving to `user://settings.cfg`:
- **Video:** window mode (windowed/borderless/fullscreen), resolution, VSync, FPS cap (30/60/120/144/unlimited), render scale (50–100%), quality preset (Low/Medium/High: shadows, glow, MSAA), UI scale.
- **Audio:** per-bus volumes, mute when unfocused.
- **Voice:** enabled on/off, mode (open mic with voice activation threshold / push-to-talk on Caps or T / gamepad L1), input device, input gain with live meter and "hear myself" test, voice volume, per-player volume and mute (also from the leaderboard and lobby), "only friends can talk to me" option.
- **Controls:** rebinding for all actions (keyboard + gamepad), mouse sensitivity, invert Y, gamepad look sensitivity, gamepad vibration on/off.
- **Camera:** first/third-person default, FOV (70–110), head bob on/off, auto third-person when ragdolled on/off.
- **Gameplay:** contextual hints on/off, auto-spin confirmation, show luck numbers vs icons.
- **Accessibility:** motion-sickness preset (third person, FOV 100, no head bob, no shake), grab as toggle instead of hold, colorblind-safe palette mode (also uses shapes/patterns, always on for quiz answers and player markers), reduce motion (no shake/flash), text size, high-contrast UI outlines, hold-vs-toggle for any held input.
- **Language:** English only in V1; all strings go through `tr()` with a CSV translation file from day one.

### 2.18 Steam integration (M8)

Via **GodotSteam** (GDExtension). Steam is the social/identity layer; game traffic goes to the VPS (§4.0):
- Init with `steam_appid.txt` = 480 (Spacewar) during development; real App ID injected at release via an export preset feature/config, never hard-coded in multiple places.
- Steam lobbies as the invite/presence layer (**friends-only default**, lobby data: room_id, room_code, host, port, build), friend invites via overlay and an in-game "Invite friends" button, "Join Game" via rich presence `connect`, launch args `+connect_lobby` / `+join_room`, full flow in §4.0.1.
- **Auth tickets for the Web API** (`getAuthTicketForWebApi`) for every orchestrator call; cancel tickets on leave.
- A real **Steam App ID is required** for Web API ticket validation and real invites; App ID 480 (Spacewar) works for local lobby/overlay experiments only, so production online play waits on the owner's Steamworks app.
- **Steam Voice** for proximity chat (§2.22): `SteamUser` voice capture (`startVoiceRecording`, `getVoice`, `decompressVoice`) through GodotSteam; the compressed packets go over ENet to the game server, which relays them to listeners in range; clients decompress and spatialize locally.
- Rich presence: "In lobby (3/8)", "Playing — 4:21 left — 2nd place".
- Achievements (≥ 16): Thrown Out (get thrown out by security), Fountain of Youth (throw 3 players into the fountain in one match), Sticky Fingers (shake $500 out of players in one match), Plinko Prophet (hit a 60× slot), First Win, Win a 30-min match, Hit 3 Diamonds, Blackjack ×3 in a row, Perfect Quiz (3/3), Steal $500 in one Pickpocket, Reflect a sabotage with Mirror, Comeback (last → first in final segment), Slip 3 players with bananas in one match, Go bankrupt and still win, Play all game types in one match, Play 10 matches. Stats: matches played, wins, total winnings.
- Steam Input: rely on Godot's joypad input + Steam Input's default "gamepad" configuration; ship a default controller config.
- Steam Cloud: `user://settings.cfg` and `user://profile.cfg` (auto-cloud configuration on Steamworks side; documented in release checklist).
- Overlay works (tested manually on a real Steam client — mark untested if not possible in your environment).
- Without Steam running: Practice vs Bots and Tutorial work offline; online play shows "Steam is required for online play" (release builds). Dev builds can still go online with `AUTH_MODE=dev` against a dev orchestrator.

### 2.19 Bots

Server-side AI (`ai/bot_brain.gd`) using a utility-based decision every 1–2 s:
- Choose station by utility: preference by difficulty personality ("cautious", "degenerate", "trickster"), hot table bonus, distance cost, seat availability.
- Bet sizing: % of bankroll by personality (cautious 3–5%, degenerate 10–25%); blackjack actions via basic strategy (Hard), simplified (Normal), random-ish (Easy).
- Item use: rule-based (e.g., use Pickpocket when within 4 m of a richer player; Bodyguard when leader; Lucky Clover before sitting at slots; Black Cat on the leader).
- Physical play: "trickster" bots shove players near the fountain/railing and shake knocked-out rich players when no guard is near; all bots occasionally shove someone blocking a hot seat, break free from grabs by mashing (reaction time by difficulty), and pick up nearby dropped chips. Bots never chain-harass the same human (same anti-grief limits as humans, plus a 30 s per-victim cooldown for bots).
- Bots do not talk; they use emotes and gibberish barks so they still feel alive.
- Navigation via `NavigationAgent3D`. Bots use the exact same server APIs as humans (intents), so they double as integration-test drivers.

### 2.20 Basic anti-cheat & trust model

- **Server (host) is authoritative** for money, bets, RNG, items, timers, quiz answers and scoring. Clients send **intents only** (`request_place_bet`, `request_action`, `request_use_item`, `submit_answer`…).
- Validate every intent: player exists, is in the right phase, is seated at that station, amount within limits and ≤ money, item owned, cooldowns, target valid/in range (server-side positions), rate limiting (max 20 intents/s per peer; excess dropped and logged).
- RNG lives only on the server (seeded `RandomNumberGenerator` per match, seed logged). Future outcomes (shoe order, quiz correct answers) never leave the server.
- Movement: server sanity checks (speed, teleport, out-of-bounds) with snap-back.
- Physical interactions: grabs, shoves, throws, knockouts and shakes are **requested** by clients and **resolved by the server** using server-side positions (range, line of sight, cooldowns, immunities). Chips dropped by shaking are created and collected only by the server.
- Voice: the server relays voice packets but never interprets them; per-peer voice bandwidth is capped (drop packets above 6 KB/s per speaker) to prevent flooding.
- Because all online matches run on the owner's dedicated server, **no player has authority over anything that matters**; the client is untrusted. Identity is the Steam Web API-verified SteamID. Join tokens are single-use and room-bound. The publisher Web API key and any secrets live only on the VPS.
- No kernel anti-cheat, no DRM beyond Steam's default.

### 2.21 Balancing knobs (all in `data/balance/balance.tres`)

Start money, table limits and multiplier growth, RTP adjustments (blackjack dealer-bust bonus, roulette generosity, slot weights), luck reroll chance per point (0.12), luck clamp (3), item durations/percentages/caps, loot table weights, quiz points, quiz cash, comp amount, Hot Table frequency/multiplier, Last Call multiplier, movement/sprint/jump params, grab/shove/throw/knockout/shake params and immunities, guard sight range, VIP entry threshold, Plinko multipliers and weights, jackpot feed rate. **No balance number is hard-coded in logic code.**

Balance targets (verified by automated bot simulation in M9): no single item accounts for > 25% of total player-to-player transfers; the winner's final money is < 6× the median in 90% of simulated matches; last place after the final quiz wins the match in 8–20% of simulations (comebacks possible but not random); every game type is chosen by bots and produces similar EV; **physical theft (shaking) accounts for 5–20% of player-to-player transfers** (enough to matter, not enough to replace gambling); no human in a playtest is knocked out more than ~once per minute on average.

### 2.22 Proximity voice chat & expression (PEAK / R.E.P.O. / GWYF)

- **Proximity voice is on by default** in online play: full volume within 4 m, linear-ish falloff to silence at 20 m, muffled (low-pass) through walls via a single raycast per speaker per 200 ms. Voices are 3D-positioned at the speaker's head.
- **Exceptions that make it social, not lonely:** during the **quiz and reward phases everyone hears everyone** (game-show stage, global voice); seated at the **same table** = full volume regardless of distance; in the **results podium** everyone hears everyone (gloating/crying is the point). A **"Megaphone"** prop on the bar lets one player at a time broadcast globally for 5 s (comedy tool, 30 s cooldown).
- **Mouths move:** each avatar's mouth openness = smoothed RMS of that player's decoded voice; eyebrows bounce on loud peaks. A small speaker icon above heads when talking (toggleable).
- **Transports:** Release builds use **Steam Voice** (Steam's codec, ≈1–3 KB/s, §2.18), relayed by the game server. Dev/test builds without Steam use a built-in fallback: `AudioEffectCapture` on a mic bus → 16 kHz mono → **μ-law 8-bit** (~16 KB/s per speaker; dev only, too heavy for the VPS at scale) through the same `VoiceChannel` interface. Optional later: an Opus GDExtension if one is reliably available (log as Deferred). Both paths are behind `VoiceCodec` so the rest of the code is codec-agnostic.
- Playback per remote speaker: `AudioStreamGenerator` → `AudioStreamPlayer3D` attached to their avatar head, on the Voice bus, 100–150 ms jitter buffer.
- Text fallback: none in V1 (no free-text chat to moderate); emote wheel + quick pings ("Come here!", "Look!", "Help!", "Run!") with on-screen markers cover players without microphones.
- Safety: per-player mute, lobby host can mute anyone for the match, "only friends can talk to me" option, voice disabled entirely if the Steam account has voice restricted (respect what the Steam API reports).

### 2.23 Session design, progression & price positioning (PEAK lessons)

- **Pop in, pop out:** from launching the game to standing in a friend's lobby in ≤ 3 clicks (Steam invite → accept → you are in the entrance hall). No account creation, no tutorial gate (the tutorial is offered, never forced), no progression that punishes skipping a session.
- **One clear goal per match:** "be the richest when the clock runs out." Everything on screen serves that goal.
- **No power progression between matches.** Every match starts equal. Persistent unlocks are **cosmetic only** (hats, body patterns, googly-eye styles, victory dances, chip colors), earned through play: per-match "Casino Tokens" (fictional, non-purchasable, not tradeable, not random-box based; fixed unlock costs shown up front) plus achievement-linked cosmetics. Stored in `user://profile.cfg` (Steam Cloud). Cosmetics are a post-MVP task (M10); MVP ships with the 6 base hats and 8 colors.
- **Digestible content scope:** V1 ships 1 map, 6 games (Blackjack, Roulette, Slots, Plinko + Big Wheel, Hi-Lo; Duck Derby if time), 1 minigame, ~17 items, 2 modes (Versus + Loan Shark co-op). That is a complete "digestible" game; more content later.
- **Price positioning (for STORE_PAGE.md):** low impulse price typical of the genre (~$5–8 USD) with a launch discount. A PEAK-style "Friend Pass" (one purchase lets a friend join for free) is a post-launch consideration only, not V1 work.

### 2.24 Optional co-op mode: "Loan Shark" (Gamble With Your Friends homage, post-MVP M10)

Built entirely from existing systems via a `ModeDefinition`, which proves the mode architecture:
- 1–6 players share **one bank account**. Each "night" lasts 4 minutes of casino time; the **Loan Shark's quota** must be in the account when the night ends (quota grows each night: $1,500, $3,000, $6,000, $12,000 …). Missing it ends the run with a comedic "broken kneecaps" ragdoll cutscene (cartoon, non-graphic).
- Between nights: the Casino Quiz still runs, but rewards are **team items** chosen by the top scorer of the quiz (who gets to decide is a great argument starter).
- Individual players still physically fight over seats and can shake chips out of teammates (chips go back to the shared account only when picked up, so griefing a teammate is pointless, but fumbling is funny). The VIP Mezzanine opens when the team account exceeds the threshold.
- Score = nights survived; local best stored in profile.
- Disabled in V1 if it threatens the release schedule; the requirement is that adding it touches only `modes/loan_shark/` plus registry entries.

---

## 3. Technology decisions

### 3.1 Engine & language
- **Godot 4, latest stable 4.x release (≥ 4.4)**, standard (non-.NET) build. **GDScript with static typing everywhere** (`var x: int`, typed arrays/dictionaries, `class_name`), warnings for untyped declarations enabled as errors in project settings where practical.
- Why Godot: free and MIT-licensed (no royalties), text-based scenes/resources an agent can author and diff, excellent headless mode for automated tests and exports from a Linux CLI, built-in high-level multiplayer (RPCs, `MultiplayerSynchronizer`, `MultiplayerSpawner`), mature Steam integration via GodotSteam, and lightweight enough for a stylized 3D party game.
- Renderer: **Forward+** for desktop with a **Compatibility** fallback preset selectable via command line/setting for low-end GPUs. Keep shaders compatible with both.
- Pin the exact versions you install in `docs/TOOLCHAIN.md` (Godot version + SHA, export templates, GUT, GodotSteam).

### 3.2 Libraries / add-ons
| Purpose | Choice | Fallback if unavailable |
|---|---|---|
| Unit/integration tests | **GUT** (Godot Unit Test) 9.x for Godot 4 | Minimal in-house test runner `tests/runner/mini_runner.gd` (assert helpers + headless runner that exits with non-zero code on failure) |
| Steam | **GodotSteam** GDExtension (4.x): lobbies, invites, rich presence, Web API auth tickets, voice, achievements (no Steam networking needed) | Stubbed `SteamService` (`steam_service_stub.gd`) + `AUTH_MODE=dev`; Steam work is then logged as blocked in PROGRESS.md |
| Networking transport (all online play) | Built-in `ENetMultiplayerPeer` (UDP to the VPS) | — |
| Room Orchestrator (VPS) | **Python 3.12 + FastAPI + uvicorn + httpx**, Caddy for TLS, Docker Compose | systemd units + plain `http.server`-based minimal API if Docker is unavailable on the VPS |
| 3D physics | **Jolt Physics** (built into Godot ≥ 4.4; set `physics/3d/physics_engine = "Jolt Physics"`) for stable stacking, ragdolls and props | Godot Physics (default) with tuned solver iterations |
| Voice | **Steam Voice** via GodotSteam (Steam builds); built-in `AudioEffectCapture` + μ-law codec (ENet/LAN builds) | Voice disabled with a clear UI note; emotes/pings still work |
| Placeholder 3D/2D assets | Procedural meshes (Godot primitives/CSG), optional **Kenney CC0** packs if downloadable | Primitives only |
| Fonts | Open-licensed Google Fonts (e.g., "Lilita One" for headings, "Nunito" for body), OFL | Godot default font |
| Audio placeholders | Generated by a Python script (sfxr-style synthesis with numpy/wave or pure Python) | Silent placeholder streams; never block |

Every third-party asset/add-on goes into `CREDITS.md` and `THIRD_PARTY_LICENSES.md` with source URL and license.

### 3.3 Toolchain setup (M0)
- Download Godot headless-capable Linux binary + matching export templates into `tools/` (do not commit binaries; add to `.gitignore`; write `tools/setup_toolchain.sh` that downloads, verifies checksums, and unzips).
- Commands you will use (wrap them in scripts under `scripts/`):
  - `scripts/test.sh` → `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit` (or the mini runner). Must return non-zero on failure.
  - `scripts/import.sh` → `godot --headless --path . --import` (first run / after asset changes).
  - `scripts/run_server.sh` → `godot --headless --path . -- --server --port 24680 --bots 3 --duration 5 --timescale 4 --autostart`.
  - `scripts/run_client.sh` → `godot --path . -- --connect 127.0.0.1:24680 --name P2`.
  - `scripts/sim_match.sh` → headless full-match simulation, bots only, accelerated time, prints JSON summary.
  - `scripts/screenshot.sh` → run a scene under `xvfb-run` with the Compatibility renderer and save PNG screenshots to `build/screenshots/` (used to visually check UI/scenes; if no display/GPU emulation works in your environment, record that and rely on headless tests).
  - `scripts/export.sh <platform>` → `godot --headless --path . --export-release "<preset>" build/<platform>/...`.
- Command-line arguments are parsed by `core/boot/cmdline.gd` (after `--`).

### 3.4 If something is unavailable
- No network to download Godot → this is a hard blocker for running anything; write all code/data anyway, write `docs/PROGRESS.md` stating the blocker clearly, and design `tools/setup_toolchain.sh` so the next session can resume. Do not claim anything runs.
- GUT incompatible with the installed Godot version → use the mini runner (same test file conventions: `tests/**/test_*.gd`, methods `test_*`).
- GodotSteam unavailable for the Godot version → pin Godot to the newest version GodotSteam supports; if still impossible, ENet-only + stub (above).

### 3.5 High-level architecture

Layered, with strict dependency direction (**lower layers never reference higher ones**):

```
[Presentation]  scenes, UI, VFX, audio, camera, input        (client only; reads state, sends intents)
      ↓ reads / sends intents via
[Net layer]     NetSession, IntentRouter, StateReplicator     (RPC definitions, serialization, snapshot/deltas)
      ↓ calls
[Simulation]    MatchServer (server-only orchestration):     phase machine, stations, economy, items, luck,
                                                              minigame director, bots, stats
      ↓ uses
[Core logic]    pure RefCounted classes, no Nodes, no I/O:    BlackjackLogic, RouletteLogic, SlotsLogic, Shoe,
                                                              LuckRng, ModifierStack, Economy, QuizScoring,
                                                              LootTables, MatchSchedule, data definitions
```

- **Core logic** is deterministic given an RNG seed and fully unit-tested headlessly. ~70% of game rules bugs should be catchable here.
- **Simulation** runs only on the server: the dedicated server process online, or in-process for Practice/Tutorial. There is **one code path** for both.
- **Presentation** never mutates game state; it renders replicated state and plays effects in response to events.
- **Event bus:** server emits typed `GameEvent`s (Dictionary with `type: StringName` + payload, built by `core/events/game_events.gd` factory functions, validated by tests). Events are both applied server-side (stats, achievements progress, bots) and broadcast to clients (presentation). This decouples items/luck/stats/audio from game code.

### 3.6 Key systems and how they interact

- **`MatchServer`** (server-only node): owns `MatchState` (players, money, inventories, active effects, phase, timers, station states, stats), the `PhaseMachine` (`LOBBY → INTRO → CASINO → PRE_MINIGAME → MINIGAME → REWARDS → CASINO … → RESULTS`), and ticks all subsystems at a fixed **20 Hz** server tick.
- **`Economy`**: the only writer of money (§2.6); emits `money_changed`.
- **`ModifierStack`**: per-player list of active effects (from items, Hot Table, Last Call, luck). Games query it: `get_luck(player, game_id)`, `get_payout_multiplier(player, game_id, context)`, `consume_on_win(...)`, `consume_on_loss(...)`, `is_protected(player)`. Items register modifiers; games never know which item caused them.
- **`LuckRng`**: wraps the match RNG and implements reroll logic (§2.7).
- **`StationManager`**: instantiates station logic per map `MapDefinition`, tracks seats/occupancy, routes intents to the right station, calls `auto_resolve` on phase end.
- **`ItemSystem`**: inventories, activation validation, targeting, proximity checks (server positions), protection/reflect resolution, cooldowns, effect lifetimes; uses `ItemDefinition` + `ItemEffect` scripts from the registry.
- **`MinigameDirector`**: schedules minigames per `MatchSchedule`, spawns minigame scene for everyone, collects scores, produces ranking → `RewardSystem` (draft + cash) → back to casino.
- **`QuizMinigame`**: question selection (no repeats, category filter, dynamic templates), answer collection, server-side timing, scoring.
- **`HotTableDirector`**, **`PickupSystem`** (dropped chips), **`BankruptcyComp`**.
- **`StatsTracker`**: consumes events → per-player stats → awards + achievements.
- **`BotDirector`**: one `BotBrain` per bot; submits intents like a client.
- **Client side:** `ClientMatchView` applies snapshots/deltas into a `ClientMatchState` mirror; UI binds to it via signals. `InputRouter` maps input actions → intents (with client-side prediction only for movement and cosmetic UI).
- **Registries** (`data/registry/*.tres`): games, items, minigames, maps, modes — the only places new content is registered.
- **Autoloads** (keep minimal): `Log`, `Settings`, `Net` (NetSession), `Steam` (SteamService or stub), `Audio` (AudioDirector), `SceneRouter`, `Registry`.

---

## 4. Networking specification

### 4.0 Online architecture: dedicated servers on the owner's VPS (decided by the owner)

The game is an **online Steam game**. All online matches run on **dedicated headless Godot servers on the owner's VPS**, never on a player's machine. Players only ever run the client. Steam provides identity, friends, invites, rich presence, voice capture and achievements; it does **not** carry game traffic.

```
 Steam client A ──(Steam lobby = invite/presence layer, lobby data holds room info)── Steam client B
      │  HTTPS: create/join room (with Steam auth ticket)                               │
      ▼                                                                                 │
 ┌──────────────────────────── VPS ────────────────────────────┐                        │
 │ Caddy (TLS, 443) → Room Orchestrator (HTTP API, port 8080)  │                        │
 │      │ spawns/kills one process per room                     │                        │
 │      ▼                                                       │                        │
 │ Godot headless game server processes (ENet/UDP 24700-24799) │◄── ENet UDP ───────────┘
 └──────────────────────────────────────────────────────────────┘   (and from client A)
```

**Components**
- **Game server** = the same Godot project exported with a `dedicated_server` export preset (headless, no rendering/audio, server-only feature tag). Launched as `BetterAtGamblingServer.x86_64 --headless -- --server --port <p> --room-id <id> --room-secret <s> --orchestrator http://127.0.0.1:8080`. One process = one room (entrance-hall lobby → match → results → rematch, until empty). Target footprint ≤ 250 MB RAM and ≤ 25% of one core per 8-player room; measure and record.
- **Room Orchestrator** (`services/orchestrator/`): a small **Python 3.12 + FastAPI + uvicorn** service (alternatives rejected: writing it in GDScript adds HTTP-server plumbing Godot lacks; Node is fine but Python keeps the tooling single-language with the asset/balance scripts). Responsibilities:
  - `POST /v1/rooms` (Steam ticket required) → validates the ticket, allocates a free UDP port from the pool, spawns a game server process, returns `{room_id, room_code, host, port, join_token}`. A player may own at most 1 room; global cap from config (default 20 rooms).
  - `POST /v1/rooms/join` with `room_code` or `room_id` (Steam ticket required) → returns `{host, port, join_token}` if the room exists, is not full and is in the lobby phase (or the caller is a reconnecting member).
  - `POST /v1/internal/verify` (localhost only, called by game servers) → verifies a player's `join_token` + Steam identity, returns `{steam_id, display_name}`.
  - `POST /v1/internal/heartbeat` (localhost only) → room phase, player count; rooms without a heartbeat for 30 s are killed; rooms empty for 120 s shut themselves down; orchestrator reaps zombie processes and frees ports.
  - `GET /v1/status` → build version accepted, room count (public); `GET /healthz`.
  - Rejects clients whose build version does not match the deployed server build ("Update required — restart Steam to update").
  - Rate limits per Steam ID and per IP; structured JSON logs; no database needed in V1 (in-memory state; a restart kills rooms, which is acceptable and documented).
- **Room codes:** every room also gets a 5-character code (no ambiguous letters, e.g. `KX7PQ`). Shown in the lobby; "Join by code" in the main menu works for friends who prefer it, and for testing without Steam.
- **Steam authentication:** the client calls `getAuthTicketForWebApi("better-at-gambling")` (GodotSteam) and sends the ticket to the orchestrator, which calls the Steam Web API `ISteamUserAuth/AuthenticateUserTicket` with the **publisher Web API key** (secret, stored only in `/etc/better-at-gambling/orchestrator.env` on the VPS, never in the repo or the client). The verified SteamID64 becomes the `player_uid`. **Dev mode:** `AUTH_MODE=dev` accepts `dev:<name>` tickets so tests and non-Steam builds work; the orchestrator **refuses to start in dev mode when `ENV=production`**.
- **Transport:** `ENetMultiplayerPeer` over UDP from clients to the VPS for all game traffic and relayed voice. `SteamMultiplayerPeer` is **not used**. In-process server (no network) for Practice vs Bots and the Tutorial, which also work offline.
- **Ports & firewall (documented and scripted):** TCP 443 (Caddy → orchestrator), UDP 24700–24799 (game servers), SSH. Everything else closed (ufw). Orchestrator listens on 127.0.0.1 only.
- **Deployment:** `deploy/` contains a `Dockerfile` for the server+orchestrator image (Debian slim, non-root user), `docker-compose.yml` (orchestrator + Caddy, host networking for the UDP range), a `systemd` alternative unit for hosts without Docker, `deploy/deploy.sh` (build server export → build image → push via SSH/rsync → `docker compose up -d` → health check → rollback on failure), and `deploy/README.md`. Zero-downtime-ish updates: the new orchestrator starts accepting new rooms, old room processes are allowed to finish (max 45 min) before the old version is stopped.
- **Domain/TLS:** if the owner provides a domain, Caddy gets automatic Let's Encrypt certificates and clients use `https://<domain>`. Without a domain, fall back to plain HTTP on the VPS IP **only for development**; the release checklist requires a domain before launch (Steam tickets must not travel unencrypted in production).
- **Configuration:** the client reads the orchestrator URL from `data/online/online_config.tres` (release) with a `--orchestrator <url>` override for development. Never hard-code the VPS IP in code.
- **Observability:** server and orchestrator logs to stdout (JSON) collected by Docker with log rotation; `deploy/status.sh` shows rooms, CPU/RAM per room, recent errors. Crash of a room process → orchestrator marks the room dead, clients see "Server error — returning to menu" with the match standings, and the crash log is kept.
- **Load test:** `tools/loadtest/` spawns N headless autoplay clients against a deployed or local orchestrator to fill K rooms; record max rooms per VPS size in `docs/DECISIONS.md`.

### 4.0.1 Steam lobby ↔ game room flow (invites must work)

1. Player clicks **Play Online → Create Party**. The client (a) calls `POST /v1/rooms`, (b) creates a **Steam lobby** (friends-only by default, max members 8) and sets lobby data `{room_id, room_code, host, port, build}` and (c) connects to the game server with its `join_token`. The player now stands in the entrance-hall lobby on the VPS.
2. Rich presence is set: `status` = "In the lobby (3/8)", `connect` = `+join_room <room_code>`, `steam_player_group` = room_id (so the Steam friends list groups the party).
3. Friends are invited with the in-game **"Invite friends"** button (`activateGameOverlayInviteDialog(lobby_id)`) or the Steam overlay. Accepting fires `join_requested`/`lobby_join_requested` in a running game, or launches the game with `+connect_lobby <id>` / `+join_room <code>` (parse both in `cmdline.gd`). The client joins the Steam lobby, reads the lobby data, calls `POST /v1/rooms/join`, and connects.
4. "Join Game" from a friend's Steam profile uses the rich-presence `connect` string, which is the same path without the Steam lobby.
5. If the creator leaves, the **room keeps running** on the VPS (no host migration needed); Steam lobby ownership passes automatically to another member, and the room's "party leader" (who can change settings and start) passes to the longest-connected player.
6. When the room shuts down, clients leave the Steam lobby and clear rich presence.
7. Reconnect: the client keeps `room_id` in memory and in `user://last_room.cfg`; on a dropped connection it retries for 60 s, then shows "Rejoin match" in the main menu while the room still exists; identity is the verified SteamID.

### 4.1 Game-traffic protocol

- **Topology:** dedicated server (§4.0) for all online play; the server's `MatchServer` is authoritative. The same server code runs in-process for Practice/Tutorial and as a local headless process for tests (`--server`).
- **Transport:** `ENetMultiplayerPeer` (UDP, one port per room from the VPS pool; port 24680 default for local development) behind a `TransportFactory` so the rest of the code is transport-agnostic. An `InProcessTransport` serves Practice/Tutorial.
- **Handshake:** on connect the client sends `hello(protocol_version, build_id, join_token, display_name, cosmetics)`; the server verifies the `join_token` with the orchestrator (§4.0), which yields the verified SteamID as `player_uid`; it rejects invalid tokens and mismatched versions with a clear message ("Host is on a different version"), assigns a slot, or recognizes a reconnecting `player_uid`.
- **Replication model:**
  - Player transforms: `MultiplayerSynchronizer` per player avatar, **client-authoritative** for own avatar (set multiplayer authority to owning peer), 20 Hz, with interpolation (100 ms buffer) for remote avatars; server validates and may snap back via `force_position` RPC.
  - **Physical interactions & ragdolls (server-authoritative):** grab/shove/throw/shake are intents (`request_grab(target_uid|prop_id)`, `request_release(throw: bool, aim: Vector3)`, `request_shove(aim)`, `request_shake()`), resolved on the server with server-side positions. When a player enters a ragdoll/grabbed/thrown state, **movement authority for that avatar moves to the server**: the server simulates the 5-body ragdoll and streams the torso transform + 4 limb rotations at 20 Hz (unreliable, sequenced) to all clients, which interpolate; when the player gets up, authority returns to the owning client (`authority_changed` event with a position handoff). Props (stools, chip piles, Plinko chips) are server-simulated `RigidBody3D`s; clients render interpolated transforms only for props that are moving (sleeping props send nothing). Budget: ≤ 24 simultaneously moving networked bodies; extra props become client-only cosmetic debris.
  - **Client prediction for feel:** the attacker's client plays the grab/shove animation immediately; the server's confirm/deny event either continues or cancels it (cancel = small "whiff" animation). The victim's client applies the knockback immediately on receiving the event.
  - **Voice:** a dedicated unreliable channel (`transfer_channel` 3) carries compressed voice frames `{speaker_uid, seq, bytes}` client → server → clients within hearing range (the server filters by distance + exceptions in §2.22 to save bandwidth). Never mixed with game events.
  - Game state: **server-authoritative reliable events** for discrete changes (`money_changed`, `bet_placed`, `round_started`, `cards_dealt`, `round_result`, `item_used`, `effect_added/expired`, `phase_changed`, `quiz_question`, `quiz_reveal`, …) using `@rpc("authority", "call_remote", "reliable")` on a single `NetEvents` node with one `deliver_event(event: Dictionary)` channel. Unreliable channel for frequent cosmetic stuff (timer sync every 1 s, slot reel spin cosmetics).
  - **Snapshot:** `MatchSnapshot` (full serializable state minus secrets) sent on join/reconnect and on demand if the client detects an event sequence gap (each event carries an incrementing `seq`; gap → request snapshot).
  - **Secrets never replicated:** shoe order, dealer hole card (until reveal, except to a player with Hot Hands), quiz correct indices, future hot tables, RNG state, other players' item draft offers.
- **Intents (client → server)**, all `@rpc("any_peer", "call_remote", "reliable")` on `NetIntents`, each validated and rate-limited: `request_sit(station_id, seat)`, `request_leave()`, `request_place_bet(station_id, bet: Dictionary)`, `request_clear_bets(station_id)`, `request_action(station_id, action: StringName)`, `request_spin(station_id, bet)`, `request_use_item(slot, target_uid)`, `request_discard_item(slot)`, `submit_answer(question_id, index)`, `submit_draft_pick(offer_id, choice)`, `set_ready(bool)`, lobby setting changes (host only), `chat_emote(id)` (8 quick emotes, rate-limited — no free text chat in V1, avoids moderation needs).
- **Serialization:** only Dictionaries/Arrays of primitive types (int, float, String, StringName, bool, PackedArrays). Never send Objects/Resources. Central `Serializer` with `to_wire()/from_wire()` per state class and round-trip unit tests.
- **Timing:** server is the clock. Phase/timer events carry `server_time_ms` and remaining time; clients estimate offset via ping (`NetClock`, smoothed RTT) and display countdowns locally.
- **Bandwidth budget:** < 30 KB/s per client at 8 players for game traffic, **plus voice** (Steam Voice ≈ 1–3 KB/s per active speaker; μ-law LAN fallback ≈ 16 KB/s per active speaker). Measure in M3 integration test (count bytes via `multiplayer` peer stats or by instrumenting the event serializer).
- **Latency tolerance:** game must remain fair and playable at 150 ms RTT with 2% packet loss (test with a simulated-latency wrapper or OS `tc netem` if available; if not available, inject artificial delay in a debug transport wrapper `DelayedPeer` used only in tests).
- **Version:** `PROTOCOL_VERSION` constant bumped on any network change.

---

## 5. Project / file architecture

```
better-at-gambling/
├── project.godot
├── export_presets.cfg
├── steam_appid.txt                # 480 for dev; excluded from release export
├── README.md                      # how to build/run/test
├── CREDITS.md / THIRD_PARTY_LICENSES.md / LICENSE (proprietary placeholder)
├── docs/
│   ├── PROGRESS.md  TODO.md  DECISIONS.md  TOOLCHAIN.md
│   ├── GDD.md                     # condensed design from §2 (keep in sync with reality)
│   ├── ARCHITECTURE.md            # layer diagram, systems, event list, RPC list
│   ├── ADDING_CONTENT.md          # how to add a game / item / minigame / map / mode
│   ├── RELEASE_CHECKLIST.md
│   └── STORE_PAGE.md              # draft Steam store text, tags, content descriptors
├── addons/                        # gut/, godotsteam/ (gitignored binaries if large; setup script fetches)
├── tools/ setup_toolchain.sh, gen_audio.py, gen_icons.py, check_balance.py
├── scripts/ test.sh, sim_match.sh, run_server.sh, run_client.sh, run_orchestrator.sh, export.sh, screenshot.sh, lint.sh
├── services/orchestrator/          # Python FastAPI room orchestrator (pyproject.toml, app/, tests/ with pytest)
├── deploy/ Dockerfile, docker-compose.yml, Caddyfile, systemd/, deploy.sh, status.sh, firewall.sh, README.md,
│           orchestrator.env.example (never the real secrets)
├── core/                          # PURE LOGIC — no Node, no scene, no I/O
│   ├── boot/ cmdline.gd
│   ├── rng/ luck_rng.gd, seeded_rng.gd
│   ├── economy/ economy.gd, money_ledger.gd
│   ├── modifiers/ modifier_stack.gd, modifier.gd
│   ├── cards/ card.gd, shoe.gd, hand_eval.gd
│   ├── match/ match_state.gd, match_schedule.gd, phase.gd, player_state.gd, standings.gd
│   ├── events/ game_events.gd
│   ├── net/ serializer.gd, protocol.gd
│   └── defs/ game_definition.gd, item_definition.gd, minigame_definition.gd, map_definition.gd, balance_config.gd
├── games/
│   ├── station_logic_base.gd      # interface every casino game logic implements
│   ├── plinko/    plinko_logic.gd,   plinko_station.*,   plinko_ui.*,   plinko.tres
│   ├── jackpot/   progressive_jackpot.gd
│   ├── blackjack/ blackjack_logic.gd, blackjack_station.tscn/.gd, blackjack_ui.tscn/.gd, blackjack.tres
│   ├── roulette/  roulette_logic.gd, roulette_station.*, roulette_ui.*, roulette.tres
│   └── slots/     slots_logic.gd,    slots_station.*,    slots_ui.*,    slots.tres
├── items/
│   ├── item_effect_base.gd
│   └── <item_id>/ <item_id>.tres, <item_id>_effect.gd, (vfx scene)
├── minigames/
│   ├── minigame_base.gd, minigame_director.gd
│   └── quiz/ quiz_logic.gd, quiz_minigame.tscn/.gd, quiz_ui.*, dynamic_questions.gd
├── server/ match_server.gd, phase_machine.gd, station_manager.gd, item_system.gd, reward_system.gd,
│           hot_table_director.gd, pickup_system.gd, stats_tracker.gd, intent_validator.gd, rate_limiter.gd
├── net/ net_session.gd, transport_factory.gd, enet_transport.gd, steam_transport.gd, net_events.gd,
│        net_intents.gd, net_clock.gd, delayed_peer.gd (test only), lobby_service.gd
├── client/ client_match_view.gd, client_match_state.gd, input_router.gd
├── ai/ bot_director.gd, bot_brain.gd, bot_personalities.tres
├── player/ player_avatar.tscn/.gd, avatar_visuals.gd (wobble, face, mouth), player_camera.tscn/.gd (first/third person),
│           ragdoll_body.tscn/.gd, hands_ik.gd, emote_wheel.tscn
├── physics/ interaction_resolver.gd (server: grab/shove/throw/knockout/shake rules), prop.gd, prop_sync.gd,
│            plinko_steering.gd, authority_handoff.gd
├── voice/ voice_channel.gd, voice_codec.gd, steam_voice_codec.gd, mulaw_codec.gd, voice_playback.gd (3D, jitter buffer),
│          voice_capture.gd, proximity_rules.gd
├── npc/ security_guard.tscn/.gd, bouncer_npc.tscn/.gd, waiter_npc.tscn/.gd
├── maps/lucky_lounge/ lucky_lounge.tscn, lucky_lounge_map.tres, props/
├── modes/ versus/ (default mode definition), loan_shark/ (co-op, M10), tutorial/ tutorial_script.gd, practice/
├── ui/ theme/, hud/, betting/, menus/, lobby/, results/, reward_draft/, pause/, settings/, common/
├── audio/ audio_director.gd, music/, sfx/, buses (default_bus_layout.tres)
├── vfx/ particles, shaders/toon.gdshader, outline.gdshader
├── assets/ models/, textures/, fonts/, icons/ (with source/license notes)
├── data/
│   ├── balance/balance.tres, match_presets.tres
│   ├── items/loot_tables.tres
│   ├── quiz/questions_en.json
│   ├── registry/ games.tres, items.tres, minigames.tres, maps.tres, modes.tres
│   └── localization/strings.csv
├── services/ online_service.gd (HTTPS client for the orchestrator), room_session.gd, settings_manager.gd, steam_service.gd, steam_service_stub.gd, achievement_service.gd, profile.gd, log.gd, scene_router.gd
└── tests/
    ├── unit/ (core logic, one file per class)
    ├── integration/ (headless server + simulated clients/bots)
    ├── sim/ (Monte-Carlo RTP & balance)
    └── runner/ mini_runner.gd (fallback)
```

**Conventions:** snake_case files, PascalCase `class_name`, signals past tense (`bet_placed`), constants UPPER_SNAKE, every public function typed and documented with `##` doc comments; no function > 60 lines without reason; no magic numbers outside `balance.tres`/definitions; `Log.info/warn/error` with category tags instead of bare `print`.

**Extensibility contracts (document in `docs/ADDING_CONTENT.md`, and prove them by adding at least the Hi-Lo game or Big Wheel and one extra item post-MVP using only the documented steps):**
- *New casino game:* implement `StationLogicBase` (+ station scene + UI scene + `GameDefinition` resource), register in `games.tres`, place station in a map. No other file edits.
- *New item:* `ItemDefinition` + `ItemEffect` script, register in `items.tres` and loot table.
- *New minigame:* `MinigameDefinition` + scene extending `MinigameBase`, register in `minigames.tres`.
- *New map:* scene + `MapDefinition` resource, register in `maps.tres`.
- *New mode:* `ModeDefinition` (rules overrides: durations, items on/off, starting money, minigame pool).

---

## 6. MVP definition (the first thing that must be playable and fun)

The MVP is reached at the end of **M6** and must satisfy all of:
1. Launch the game → main menu → **create a room on a dedicated server** (local headless server and, if VPS access is available, the real VPS) and join it from a second client by **room code** (dev auth); plus a solo practice lobby with bots (in-process).
2. 2–8 participants (humans via ENet on the same or different machines, plus bots).
3. Choose duration 5/10/15/30 minutes.
4. Greybox Lucky Lounge (with physical entrance-hall lobby and VIP mezzanine) with **Blackjack (no split), Roulette, Slots, Plinko** and the progressive jackpot, fully playable with betting UI, correct payouts, visible other players.
5. Wobbly bean characters: walk/sprint/jump, **grab, shove, throw, knockout ragdoll, shake-for-chips**, fountain hazard, security guards, first-person camera with third-person toggle, sit/leave stations, emote wheel.
5b. **Proximity voice chat over ENet (μ-law fallback codec)** with 3D falloff, global voice during quiz/results, per-player mute, and **mouths that move** with voice.
6. Match timer, Hot Table event, Last Call, bankruptcy comp.
7. **Casino Quiz** with exactly 3 questions, simultaneous answers, speed-based scoring, ranking, ≥ 60 questions.
8. Reward draft with the **11 MVP items**, item activation with targeting, luck system, sabotage/protection, dropped chips.
9. Results screen with winner and podium (awards optional for MVP).
10. Bots that play all games, use items, and take part in physical chaos (shove, grab, break free, collect chips).
11. Client disconnect → away state; reconnect restores state.
12. Placeholder art/audio everywhere (no missing-resource errors, no pink/missing textures).
13. A full automated 4-bot, 5-minute match simulation completes without errors on a headless server, and a 2-process (server + client) integration match completes without desync.

Not in MVP: Steam (and therefore Steam Voice), achievements, tutorial (contextual hints are fine), settings beyond volume/fullscreen/voice/camera/rebinding basics, split, Big Wheel, Hi-Lo, Duck Derby, Legendary items, cosmetic unlocks, Loan Shark co-op mode, waiter NPC, Megaphone, final art.

**The "fun check" for the MVP:** run a scripted 4-bot match and capture a short screenshot sequence of (a) a crowded Plinko board with a shove, (b) a knockout + shake + chip scramble, (c) a guard throwing someone out, (d) the quiz reveal, (e) the results podium. If any of these cannot be produced, the MVP is not done.

---

## 7. Testing strategy (applies to every milestone)

- **Unit tests (headless, fast, < 30 s total):** every class in `core/`, every `*_logic.gd`, every item effect, quiz scoring, serializer round-trips, schedule math, loot tables. Use fixed seeds; assert exact outcomes.
- **Statistical tests (`tests/sim/`, < 2 min):** Monte-Carlo RTP per game at neutral luck (≥ 1,000,000 slot spins, ≥ 200,000 blackjack hands with basic strategy, ≥ 500,000 roulette bets per bet type), luck effect monotonicity (L = −3 … +3 strictly ordered RTP), item effect expected values. Assert within tolerances; print a table.
- **Integration tests (headless):**
  - In-process: `MatchServer` with N bots and `timescale` ×10 runs a whole 5-minute match; assert phases occurred in order, exactly the scheduled number of quizzes, each quiz had exactly 3 questions, money conservation (sum of all `money_changed` amounts = final total − initial total, and every change has a reason), no errors in log, results produced.
  - Multi-process: `scripts/run_server.sh` + 1–2 headless clients with `--autoplay` (client-side bot that sends intents through the real network) → full match completes; client mirror state equals server state at the end (compare snapshot hashes); reconnect test (kill client process mid-match, restart with same `player_uid`, assert state restored and match finishes).
  - Latency test with `DelayedPeer` (150 ms, 2% loss) → match completes, no desync.
- **Scene smoke tests:** instantiate every `.tscn` headlessly, run 10 frames, assert no errors (catches broken references). Script that greps Godot output for `ERROR`/`SCRIPT ERROR` and fails the run.
- **UI tests:** for key screens, instantiate, simulate input events (keyboard + joypad actions) to navigate focus and press buttons; assert expected signals/intents.
- **Visual checks:** `scripts/screenshot.sh` captures main menu, lobby, casino overview, each station UI, quiz, reward draft, results. Look at the screenshots (if your environment lets you view images) and fix obvious layout problems. If rendering is impossible in your environment, record that in PROGRESS.md.
- **Physics determinism caveat:** physics is not bit-deterministic across machines; tests for networked physics assert tolerances (positions within 0.3 m, same discrete events), never exact floats. Money must never depend on client physics (assert in tests that every `money_changed` reason originates from server logic).
- **Manual-only items** (real-microphone voice quality, Steam overlay, invites, controller rumble on real hardware, real multi-machine play) go into `docs/RELEASE_CHECKLIST.md` as explicitly untested-by-agent items. Never mark them verified unless they were.
- **CI-style gate:** `scripts/test.sh all` runs lint (gdlint if available, else a grep-based check for untyped `var`), unit, sim (short mode), integration, smoke. Run it before marking any task done and before each commit.

## 8. Debug & developer tools

- `--voice-test <wav>` (feed a WAV file into the voice capture path instead of a microphone), `--knockout <uid>`, `--spawn-prop <id>`, `--timescale N` (server time acceleration), `--seed N`, `--duration`, `--bots N`, `--autostart`, `--autoplay`, `--skip-intro`, `--minigame-now`, `--give-item <id>`, `--money N`.
- In-game debug overlay (F3, dev builds only): FPS, ping, server tick, phase, seed, event seq, money ledger tail, active modifiers per player.
- Dev console (F1, dev builds only) for the same commands at runtime.
- Structured logs to `user://logs/` with match seed; `scripts/sim_match.sh` writes JSON summaries for balance analysis (`tools/check_balance.py` aggregates many runs).
- All debug features are compiled out/hidden in release exports via `OS.has_feature("release")` / custom feature tag `steam_release`.

## 9. Performance & quality bars

- 60 FPS at 1080p on a GTX 1050 / integrated Iris Xe–class GPU on Medium; 144 FPS capable on mid-range hardware. Low preset playable on Steam Deck (target: Deck Verified-friendly: 1280×800 UI legibility, gamepad-only navigation, no text < 9 px at Deck resolution).
- Server tick 20 Hz must take < 2 ms with 8 players + bots; physics at 60 Hz with ≤ 24 moving networked bodies must stay < 3 ms on the host.
- Voice end-to-end latency < 250 ms on LAN; no audible crackle in the playback path with 4 simultaneous speakers (jitter buffer test).
- Load from main menu to casino < 10 s.
- Zero `ERROR` lines in logs during the automated full-match runs.
- No softlocks: every phase has a hard timeout; every UI modal has a timeout or close path.

## 10. Content, rating & compliance notes

- Fictional chips only; no purchases at all in V1 (no DLC currency, no microtransactions). Cosmetics unlock by playing (post-launch idea), never by paying for randomness.
- Store page and in-game "About" state: "Contains simulated gambling with fictional currency only. No real money can be wagered or won."
- Expect rating descriptors "Simulated Gambling" (ESRB) / PEGI 12+ "Gambling" depiction; fill the Steam content survey accordingly (documented in `docs/STORE_PAGE.md`).
- Quiz questions: no real casino brands, no promotion of real gambling, no offensive content; include a few "gambling-facts" questions with a light responsible-play tone (e.g., "Over many plays, real casino games favor…? → The house").
- Accessibility and localization groundwork as in §2.17.

## 11. Assets (required list + placeholder strategy)

Never block on art or audio. Every asset slot below must have a working placeholder by the milestone that needs it; final assets can replace placeholders 1:1 because every visual is referenced through a scene or resource with the same path.

### 11.1 3D (placeholder = Godot primitives, CSG, procedural meshes, toon material)
- Player bean (capsule + googly sphere eyes + mouth mesh with blend/scale for open/closed + noodle arm capsules with mitten spheres + hat meshes ×6), 8 color materials, crown; ragdoll collision shapes.
- NPCs: security guard bean (black suit, sunglasses), bouncer, waiter, quiz host cat.
- Props: bar stools, chip piles, megaphone, fountain (with water shader), revolving door, VIP stairs/elevator/railing, velvet rope.
- Plinko board (pegs as cylinders, slot dividers, multiplier labels), big Plinko chip, progressive jackpot neon counter.
- Blackjack table (rounded box + felt material + 4 stools + dealer bean), card mesh (thin box with texture from 2D card atlas), chip mesh (cylinder, 4 colors by value).
- Roulette table + wheel (cylinder with segment texture generated procedurally), ball (sphere).
- Slot machine (box cabinet + 3 cylinder reels with symbol atlas texture + lever + light strip).
- Big Wheel (post-MVP), Hi-Lo table (post-MVP).
- Environment: floor tiles with carpet pattern (procedural shader), walls, pillars, plants, velvet ropes, chandeliers (emissive), neon signs (Label3D/emissive meshes: "BLACKJACK", "ROULETTE", "SLOTS", "LUCKY LOUNGE"), bar, quiz stage + 8 podiums + host cat (bean with ears).
- Pickups: chip stack; banana peel (curved capsule, yellow).
- Optional: Kenney CC0 packs (if downloadable): furniture/character/card assets. Credit them.

### 11.2 2D / UI (placeholder = generated with `tools/gen_icons.py` (Pillow) or Godot-drawn `StyleBox`/SVG)
- Card face atlas (52 cards, procedurally rendered: rank + suit symbols; suits use 4 colors + shapes in colorblind mode), card back.
- Slot symbols (Cherry, Lemon, Bell, Bar, Seven, Clover, Diamond) as simple SVG icons.
- Chip icons ($10 white, $25 green, $100 black, $500 purple).
- Item icons ×17, emote wheel icons ×8, ping markers ×4, talking-indicator icon, voice mute icon (simple SVG shapes + emoji-like glyphs drawn as vectors; do not depend on system emoji fonts).
- Luck meter, timer, crown, rank badges, input glyphs (keyboard, Xbox, PlayStation, Steam Deck sets — placeholder text-in-rounded-rect), quiz answer shapes ▲●■◆.
- Logo/wordmark "BETTER AT GAMBLING" (font-based), app icon 256×256 / 32 / 16, Steam capsule placeholders (header 920×430, small 462×174, main 1232×706, vertical 748×896, page background, library hero 3840×1240, library logo) generated from the logo + gradient background with Pillow and clearly marked PLACEHOLDER in `docs/STORE_PAGE.md`.
- Fonts: OFL fonts (see §3.2).

### 11.3 Audio placeholder generation
- `tools/gen_audio.py` synthesizes all SFX listed in §2.15 to `audio/sfx/*.wav` (sine/square/noise envelopes, pitch sweeps — sfxr style) and simple music loops (chord progressions with square/triangle waves + noise drums) to `audio/music/*.ogg` or `.wav`, using only Python stdlib (+ numpy if available). Deterministic output. If Python is unavailable, create silent `AudioStreamWAV` placeholders in Godot.
- `AudioDirector` references sounds by **id** (`&"chip_place"`) through `audio/sound_bank.tres`, so replacing files later needs no code change.

### 11.4 Asset manifest
Maintain `assets/ASSET_MANIFEST.md`: every asset id, path, status (`placeholder` / `final`), source, license. The release checklist requires reviewing which placeholders remain.

## 12. Build, export & Steam release requirements

- **Export presets:** `Dedicated Server (Linux x86_64)` (headless, `dedicated_server` feature, resources stripped of textures/audio where Godot's server export allows), `Windows Desktop (x86_64)`, `Linux (x86_64)`, `macOS (universal)` (macOS: export only; signing/notarization documented as manual step). Steam Deck runs the Linux build natively (also test Proton with Windows build if possible — manual).
- Release export: `--export-release`, PCK embedded or alongside per Steam convention (choose separate `.pck` for smaller patches; record decision), debug features off, custom feature tag `steam_release`, version string from `project.godot` `application/config/version` (SemVer, e.g., `0.1.0`), build id = git short SHA, both shown in main menu corner and sent in network handshake.
- GodotSteam libraries and `steam_api64.dll` / `libsteam_api.so` included in the client exports; `steam_appid.txt` **excluded** from release builds. The dedicated server build needs no Steam libraries (auth is checked by the orchestrator via the Web API).
- **Server release:** `deploy/deploy.sh <version>` ships the server build + orchestrator to the VPS; client and server versions are released together (the orchestrator rejects mismatched client builds). The release checklist pairs every Steam depot upload with a server deploy.
- `scripts/export.sh all` produces `build/windows/BetterAtGambling.exe`, `build/linux/BetterAtGambling.x86_64`, `build/macos/BetterAtGambling.zip`; verify each export exists, the Linux build launches headless with `--smoke-test` (boots, loads main menu + casino scene, runs 300 frames, exits 0).
- **Steamworks packaging docs** in `docs/RELEASE_CHECKLIST.md`: depots per OS, `app_build.vdf`/`depot_build.vdf` templates in `tools/steam/` with placeholder App/Depot IDs, SteamCMD upload command, launch options per OS, achievements/stats definitions to enter in Steamworks (`tools/steam/achievements.json` mirroring the in-game ids), Steam Cloud paths, controller config, rich presence localization file (`tools/steam/rich_presence_english.vdf`), store assets checklist, content survey answers, Deck compatibility checklist.
- Crash safety: catch and log fatal errors to `user://logs/`; settings/profile writes are atomic (write temp file then rename).
- Performance, save, and input settings persist across restarts (tested).

---

## 13. Milestones (execute in order; each ends only when its acceptance criteria pass and PROGRESS.md is updated)

Legend: **Tasks** → **Tests** → **Acceptance criteria (AC)**.

### M0 — Toolchain & skeleton
**Tasks:** create project folder `better-at-gambling/`, `git init`, `.gitignore` (`.godot/`, `build/`, `tools/godot*`, `*.import` caches as appropriate), `tools/setup_toolchain.sh`, install Godot + export templates + GUT (or mini runner), `project.godot` (name, version 0.1.0, window 1920×1080 stretch mode `canvas_items`/aspect `expand`, input map for all actions in §2.4/§2.8/§2.14 with keyboard+joypad, audio bus layout, autoload stubs), folder structure (§5), `docs/` files (copy §13 task list into `TODO.md`; create `PROGRESS.md`, `DECISIONS.md`, `TOOLCHAIN.md`, `GDD.md` summary, `ARCHITECTURE.md`), `scripts/*.sh`, `core/boot/cmdline.gd`, `Log` autoload, empty main menu scene that boots.
**Tests:** one trivial passing test and one deliberately failing test (confirm the runner exits non-zero, then delete the failing test); smoke test that boots main scene headless for 60 frames.
**AC:** `scripts/test.sh` runs headless and passes; `godot --headless --path . -- --smoke-test` exits 0; `TODO.md` contains all milestone tasks; first commit made.

### M1 — Core logic library (no visuals)
**Tasks:** `SeededRng`, `LuckRng` (reroll mechanics), `Card/Shoe/HandEval`, `BlackjackLogic` (state machine: idle → betting → dealing → acting → dealer → payout; simultaneous player actions; timeouts; auto-resolve), `RouletteLogic` (bet validation, all MVP bet types, payout + generosity bonus, luck neighbor/jinx rules), `SlotsLogic` (weighted reels, wild, paytable, luck reroll), `PlinkoLogic` (risk rows, weighted slot outcome, luck reroll) + `ProgressiveJackpot`, `InteractionRules` (pure rules for shove/knockout counting, immunities, shake amounts and caps, guard-sight decision given positions), `StationLogicBase` interface, `Economy` + ledger, `ModifierStack`, `BalanceConfig` + `balance.tres`, `MatchSchedule` (durations → segment times, Last Call), `MatchState/PlayerState`, `GameEvents` factory, `Serializer` + protocol constants, `QuizScoring`, `LootTables`.
**Tests:** unit tests for every class: blackjack totals (soft/hard aces, blackjack vs 21, dealer S17, double, bust), shoe reshuffle at penetration, simultaneous actions & timeout auto-stand; roulette color/dozen/column mapping for all 37 numbers, payouts per bet type, limits; slots paytable incl. wild substitution and cherry rules; Plinko multipliers/weights per risk row and jackpot feed/accounting; interaction rules (3 shoves in 4 s → knockout, immunity windows, shake cap 8% / $400 × multiplier, same-attacker 20 s limit, seated players immune); luck reroll: L=0 never rerolls, L>0 never yields worse quality than the first draw, probability ≈ 0.12·L (statistical); economy cannot go negative, every change has a reason; schedule table from §2.1 exactly; serializer round-trip for MatchState; quiz scoring boundaries (0 s → 1000, 12 s → 500, wrong → 0, ties). **Sim tests:** RTP within 100.5–102% at L=0 for each game (tune constants until true), monotonic RTP over L∈[−3,3].
**AC:** all tests green; RTP table recorded in `DECISIONS.md` with final tuned constants; no Node references in `core/` (enforce with a grep test).

### M2 — Local playable sandbox (single player, in-process server)
**Tasks:** `MatchServer` + `PhaseMachine` (casino-only for now), `StationManager`, in-process local session (host = local player, no network peer yet, but go through the same intent/event API), greybox Lucky Lounge (layout §2.3, navmesh, spawn points, all MVP stations placed via `MapDefinition`), wobbly bean avatar (walk/sprint/jump, procedural wobble, googly eyes, mouth driven by a test tone until voice exists), 5-body ragdoll + get-up, **grab/shove/throw/knockout/shake** against dummy bean bots via server-side `InteractionResolver`, props (stools, chip piles) on Jolt physics, fountain hazard, revolving door, 2 security guards with patrol + sight cone + throw-out, VIP mezzanine with bouncer check and railing, first-person camera + third-person toggle + auto third-person when ragdolled, emote wheel, Plinko station with server-steered chip and recorded path playback, interaction prompts, sit/leave, station scenes with placeholder visuals, **betting UI component**, Blackjack/Roulette/Slots UIs wired to logic through intents/events, HUD (money, timer, event feed), money popups, basic SFX hookup with generated placeholders (run `tools/gen_audio.py`), toon shader, main menu → "Practice" → casino.
**Tests:** scene smoke tests for all new scenes; physics integration tests (shove ×3 → knockout; throw into fountain → slow; shake drops exactly the capped amount and chip piles sum to it; seated player immune; guard throws out an attacker in sight but not one out of sight; Plinko chip lands in the server-chosen slot in 1,000 seeded drops); integration test: scripted local player intents sit at each station type, places bets, plays rounds; money in HUD matches server state; leave mid-round auto-resolves correctly; UI navigation test with keyboard and joypad events on bet panel.
**AC:** you can launch the game, walk around, grab/shove/throw dummy beans and shake chips out of them, get thrown out by a guard, and play all four games with correct payouts using mouse/keyboard and gamepad (verified by automated UI tests + screenshots); no errors in log during a scripted 3-minute session.

### M3 — Networking, dedicated server & lobby
**Tasks:** `Dedicated Server` export preset and `--server` boot path, **Room Orchestrator** (§4.0) with `AUTH_MODE=dev`, port pool, spawn/heartbeat/reap, room codes, join tokens and `/internal/verify`; client `OnlineService` (create party, join by code, rejoin) and `RoomSession`; `NetSession`, `TransportFactory`, ENet transport, handshake/versioning, `NetIntents` & `NetEvents`, `IntentValidator` + `RateLimiter`, `ClientMatchView`/`ClientMatchState`, snapshot + delta with seq/gap recovery, `NetClock`, player avatar replication with interpolation and server sanity checks, **physical entrance-hall lobby** (ready pads, wardrobe mirror, host settings board) plus the mirrored 2D lobby panel (slots, colors, hats, ready, host settings, bot slots placeholder), physics/ragdoll replication with **authority handoff** (client-owned while standing, server-owned while ragdolled/grabbed/thrown) and prop sync, client-side prediction of grab/shove animations with server confirm/deny, host/join by IP menus, connection error UI, `DelayedPeer` for tests, command-line `--server/--connect/--autoplay`.
**Tests:** orchestrator **pytest** suite (room create/join/full/closed, port allocation and release, heartbeat timeout reaping, empty-room shutdown, one-room-per-owner, rate limits, version mismatch, dev auth refused when `ENV=production`, join token single-use); end-to-end local test: start orchestrator → create room via API → orchestrator spawns a headless server → 2 autoplay clients join by room code → match runs → room shuts down when empty and the port is freed; serializer/protocol tests; validator tests (bet over money, wrong phase, not seated, foreign station, spam > 20/s); multi-process integration: headless server + 2 headless autoplay clients play 3 minutes of casino; assert client mirrors equal server (state hash) at end; version-mismatch rejection; networked physics test (client A grabs and throws client B; both clients and server agree on B's final position within 0.3 m and on the knockout event; authority returns to B after get-up); latency test 150 ms/2% loss (including a shove exchange); bandwidth measured < 30 KB/s/client.
**AC:** with the orchestrator running locally, one client creates a party, a second client joins by room code; both ready up, enter the casino, see each other move and wobble, shove and throw each other, play at the same roulette/blackjack table and Plinko board together, and money stays consistent; all tests green.

### M4 — Match flow, timer, Quiz minigame, rewards (cash only for now)
**Tasks:** full `PhaseMachine` (intro, casino segments, pre-minigame warning, minigame, rewards, Last Call, results), match timer & HUD countdowns, durations from lobby, `MinigameDirector` + `MinigameBase`, quiz stage scene, `QuizMinigame` (question flow, server timing with RTT compensation, reveal, scoreboard, ranking with tiebreaks), `questions_en.json` with ≥ 60 questions (aim 150 by M10) + JSON schema validation, 2 dynamic question templates, reward phase with cash prizes (item draft UI built but items stubbed), Hot Table director, bankruptcy comp, results screen (podium, final money, rematch/leave), auto-resolve all stations at phase end.
**Tests:** schedule integration (5-minute match at timescale → exactly 2 quizzes at 1:40/3:20 casino time; 30-minute → 7); each quiz exactly 3 questions, no repeats within a match; correct index never present in any client-bound event before reveal (assert on serialized traffic); scoring with simulated latencies; ties; question JSON validation (4 answers, valid index, unique ids, non-empty); Last Call multiplier applied only in final 60 s; comp rules; results tiebreakers.
**AC:** full multi-process match (server + 2 autoplay clients + 2 bots stubs or scripted players) completes from lobby to results for 5-minute duration; quiz playable with keyboard/mouse/gamepad; screenshots of quiz and results look correct.

### M5 — Items, luck, sabotage, pickups
**Tasks:** `ItemSystem`, inventory (3 slots, discard flow), `ItemDefinition`/`ItemEffect` for the 11 MVP items (incl. Spring Glove's physical effect and Bouncer NPC hook-up when Bouncer lands in M10), targeting UI (picker + proximity indicator ring), activation banners/VFX/SFX placeholders, luck HUD meter, effect timers HUD, protections (Bodyguard/Mirror/spawn protection/away protection), negative-item grace window, cooldowns, `PickupSystem` (dropped chips, banana peel slip), reward draft with real items + loot tables + Underdog rule, game-specific luck hooks, peek dealer card for Hot Hands (private event to that player only).
**Tests:** unit test per item (activate, effect, expiry, interaction with Bodyguard and Mirror, edge cases: target broke, target away, target protected, self-target invalid, out of range); Pickpocket min/max/never-negative; Double Trouble × Last Call × Hot Table stacking order; Golden Chip refund exactness; banana drop amount & pickup conservation (money dropped = money picked up + despawned, despawned money is logged as `pickup_expired`); draft offers follow loot weights (statistical); Underdog only with ≥ 3 players; integration: bots/autoplay use items during a full match without errors.
**AC:** every MVP item is usable in a networked match with visible feedback for all players; money conservation test passes with items enabled; all tests green.

### M6 — Bots, reconnects, MVP hardening → **MVP COMPLETE**
**Tasks:** **VPS deployment** (§4.0): `deploy/` Dockerfile + compose + Caddyfile + firewall script + `deploy.sh`/`status.sh`; if the owner has provided SSH access, deploy to the VPS (dev auth mode, or production mode only once a Steam App ID and Web API key exist) and run the internet test below; if not, run the same stack locally in Docker and log VPS deployment as waiting on the owner; `BotDirector`/`BotBrain` with personalities and difficulties (§2.19), lobby bot slots, bot quiz answers, bot item use, bot physical behavior (§2.19); **proximity voice**: `VoiceChannel`, `VoiceCapture` (mic bus + `AudioEffectCapture`), μ-law `VoiceCodec`, server relay with distance filtering, `VoicePlayback` (3D `AudioStreamPlayer3D` + `AudioStreamGenerator` + jitter buffer), global-voice exceptions (quiz, rewards, results, same table), push-to-talk/open-mic, per-player mute, mouth-flap from decoded RMS, talking indicator; disconnect → away state; reconnect by `player_uid` with snapshot; host-left flow; pause menu (Resume/Leave/basic settings: volumes, fullscreen); contextual hints; loading tips; fix all known bugs; basic settings persistence.
**Tests:** internet test: 2–4 headless autoplay clients connect to the deployed VPS orchestrator, create/join a room by code and finish a 5-minute match with zero errors (or the same against the local Docker stack if no VPS access); load test filling rooms until CPU 70%, record rooms-per-VPS; deploy rollback works (deploy a broken build on purpose in a staging port range, confirm the health check rolls back); 50 headless bot-only matches (mixed durations, seeds 1–50, timescale) with zero errors and money conservation; multi-process reconnect test; host-left test; voice tests: μ-law encode/decode round trip within error bound, jitter buffer reorder/loss handling, proximity filter (speaker at 25 m not relayed, at 3 m relayed, global during quiz), mouth openness rises with a fed sine tone and returns to closed in silence, voice bandwidth per speaker under cap (use a WAV file fed into the capture path instead of a real microphone in headless tests); bots take part in shoves/knockouts/chip pickups in ≥ 80% of matches; bots visit all four game types in ≥ 90% of matches; average bot decision cost < 0.2 ms.
**AC:** all MVP criteria in §6 verified and listed with evidence (test names, screenshot paths) in `PROGRESS.md`. Tag the commit `v0.1.0-mvp`. Produce a Linux and Windows debug export that launches (smoke test the Linux one).

### M7 — Polish: UI/UX, audio, VFX, animation, feel
**Tasks:** full theme pass; animated money counters; card dealing/chip sliding/roulette ball/slot reel animations; win/lose/jackpot VFX and hit-stop; character squash/stretch, slip, cheer, sad animations; face reactions (eyes widen on wins, droop on losses), better ragdoll flail and get-up, knockout birdies, guard carry-and-toss animation, fountain splash VFX, waiter NPC who trips and spills puddles, Megaphone prop; crown on leader; Hot Table spotlight/fire; Last Call lighting & music; quiz show juice (host cat reactions, confetti); results podium animations + fun awards + money-over-time graph; music crossfades, all SFX hooked; emotes wheel; blackjack **split**; input glyph switching (keyboard ↔ gamepad); improved placeholder art (better procedural props, lighting, glow).
**Tests:** smoke tests for all scenes; split logic unit tests; awards computation tests; no FPS regression in a scripted benchmark scene (record FPS in PROGRESS.md if a renderer is available).
**AC:** screenshots of every screen show a cohesive, readable, polished look; game feel checklist in `docs/GDD.md` ticked (every action has visual + audio feedback).

### M8 — Steam integration (invites must work end to end)
**Tasks:** GodotSteam install, `SteamService` (+ stub fallback), Steam lobby ↔ VPS room flow exactly as §4.0.1 (create party = room + Steam lobby, lobby data, invite button, overlay invites, `join_requested`, `+connect_lobby`/`+join_room` launch args, rich presence `connect` + `steam_player_group`, leader handoff, reconnect), Web API auth tickets for every orchestrator call and orchestrator-side `AuthenticateUserTicket` validation (`AUTH_MODE=steam`), production config on the VPS with domain + TLS, **Steam Voice codec** behind `VoiceCodec` (fall back to μ-law when Steam is unavailable), friends-only default lobby and in-game "Invite friends" button, rich presence, overlay invites, "Join Game" handling (`+connect_lobby` launch arg + `join_requested` signal), achievements & stats (`AchievementService` fed by `StatsTracker`), Steam Cloud paths documented, offline/"Steam not running" fallback.
**Tests:** unit tests with the stub (achievement unlock conditions from event streams, lobby data encode/decode, launch-arg parsing, invite → join flow state machine); orchestrator tests with the Steam Web API mocked (valid ticket, invalid ticket, wrong app id, Steam API timeout → clear error); **two-account Steam test script** `docs/STEAM_INVITE_TEST.md` (account A creates party, invites B via button and via overlay, B accepts while the game is closed and while it is running, "Join Game" from profile, A leaves and B stays, B disconnects and rejoins) — run it yourself if two Steam accounts/clients are available, otherwise hand it to the owner and record the result they report; app runs headless with Steam unavailable without errors; if a Steam client is available, run two-account manual test (otherwise mark in RELEASE_CHECKLIST as manual).
**AC:** builds work with and without Steam; Steam code paths are exercised by stub tests; against the production VPS with the owner's real App ID, the two-account invite test passes (verified by you or reported by the owner, and recorded as such). Until the owner's App ID and Web API key exist, M8 stays "IMPLEMENTED, waiting on owner" rather than done.

### M9 — Onboarding, settings, accessibility, balancing
**Tasks:** interactive tutorial (§2.13), full settings menu (§2.17) with persistence and rebinding, colorblind/reduce-motion/text-size options, localization CSV with all strings via `tr()`, credits screen; balancing via `scripts/sim_match.sh` × 500 bot matches → `tools/check_balance.py` report vs targets in §2.21; tune `balance.tres`; record results.
**Tests:** settings save/load round-trip; rebinding persistence; tutorial completes via scripted input; no untranslated user-facing string literals (grep test); balance report meets targets.
**AC:** a new player can learn the game from the tutorial alone (scripted run passes); balance targets met (or deviations justified in DECISIONS.md).

### M10 — Content expansion (extensibility proof)
**Tasks:** add **Big Wheel**, **Hi-Lo** and **Duck Derby** using only `ADDING_CONTENT.md` steps; add items robin_hood, jackpot_magnet, bouncer, wild_card, grease, bribe; **Loan Shark co-op mode** (§2.24) touching only `modes/loan_shark/` + registries; **cosmetic unlocks** with Casino Tokens (§2.23: fixed prices, no randomness, wardrobe mirror UI); quiz bank to ≥ 150 questions + 2 more dynamic templates; 2 more fun awards.
**Tests:** same per-game/per-item test sets as M1/M5; RTP sims for new games; Loan Shark: quota progression, shared-account economy conservation, run ends on missed quota; cosmetics: token earn/spend persistence, no purchasable or random path exists (grep test for any store/IAP API usage); registry tests (every registered entry loads and passes interface checks).
**AC:** new content works in full matches; `ADDING_CONTENT.md` updated with anything you had to do that wasn't documented (then fix the architecture so it isn't needed).

### M11 — Release candidate
**Tasks:** export presets finalized (including the dedicated server); `scripts/export.sh all`; release server deployed to the VPS with production auth;  smoke-test exports; app icons; placeholder store assets; `RELEASE_CHECKLIST.md`, `STORE_PAGE.md`, Steamworks VDF templates, achievements json; final full test run; README with build/run/test instructions; version `1.0.0-rc1`.
**Tests:** full `scripts/test.sh all`; 100 bot matches error-free; exported Linux build smoke test; exported client builds connect to the production VPS (room code, autoplay) and complete a match; orchestrator health check green after deploy.
**AC:** release builds for Windows/Linux (macOS exported) exist in `build/`; every manual-only item listed clearly; PROGRESS.md states exactly what was verified and what still requires a human (Steam partner setup, Web API key, domain DNS, real art/audio replacement, multi-machine and Steam client testing, macOS signing).

---

## 14. How to work each session (the loop)

1. Read `docs/PROGRESS.md` → `docs/TODO.md` → `docs/DECISIONS.md` → the relevant sections of this prompt.
2. Run `scripts/test.sh all` to establish the baseline. If red, fix that first.
3. Pick the next unchecked task in the current milestone. Implement it with its tests.
4. Run the relevant tests, then the full suite. Launch/smoke the game when the task touches runtime behavior. Capture screenshots for visual tasks when possible.
5. Fix until green. Update `TODO.md` checkbox, append to `PROGRESS.md` (what changed, evidence, next step), log decisions, commit.
6. Repeat. When a milestone's AC all pass, write a milestone summary in `PROGRESS.md` with evidence and move on.
7. Before the context window runs low, make sure `PROGRESS.md` has an accurate "Next step" and the tree is committed.

**`docs/PROGRESS.md` template:**
```markdown
# Progress
## Current milestone: Mx — <name>
## Next step: <one precise, actionable instruction>
## Status by milestone
- M0: DONE (evidence: tests/..., commit abc123)
- M1: IN PROGRESS (7/12 tasks)
## Verified features (IMPLEMENTED+TESTED, with test names/screenshots)
## Implemented but unverified (with reason)
## Known bugs
## Blockers
## Session log
### <date/session n>: what was done, test results summary
```

---

## 15. Final directive

Start now with **M0**. Create the project, install the toolchain, and work through the milestones in order until **M11** is complete, testing everything as you go. Prioritize reaching the **MVP (end of M6)** as a working, fun, networked build before any polish. Make reasonable decisions on your own, log them, debug through problems, and never stop to ask the user minor questions. Never report a feature as working unless you implemented it and ran the tests or the game to prove it. Keep `PROGRESS.md` and `TODO.md` accurate at all times so any future session can pick up exactly where you left off.
