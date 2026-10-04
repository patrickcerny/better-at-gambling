# Better at Gambling — Game Design (condensed)

Authoritative long form: [`docs/MASTER_PROMPT.md`](MASTER_PROMPT.md) §1–§2. Keep this summary in sync
with what is actually built.

## Pitch
Online 2–8 player casino party game (bots fill slots) with free first-person movement in a stylized
casino. Everyone starts with **$1,000 in fictional chips**; richest at the end wins. Physical
"friendslop" chaos (grab, shove, throw, ragdoll, shake chips out of knocked-out rivals) and
proximity voice. **Fictional currency only**: no real money, purchases, cash-out or loot boxes.

## Match loop
Lobby (physical entrance hall, ready pads) → Intro → Casino segment → Quiz (3 questions) → Item
draft → Casino … → Last Call (final 60 s, winnings ×1.5) → Results.

| Duration | Quizzes | Segment length |
|---|---|---|
| 5 min | 2 | 1:40 |
| 10 min | 3 | 2:30 |
| 15 min | 4 | 3:00 |
| 30 min | 7 | 3:45 |

Timer counts casino time only. House comp $150 when broke (once per segment).

## Casino games (MVP)
- **Blackjack:** 6-deck shoe, S17, 3:2, double any two, no split (M7), simultaneous play, Dealer
  Bust Bonus 1.1:1. Limits $10–$200.
- **Roulette:** European, straight/colour/odd-even/low-high/dozens/columns, +5% generosity. $10
  min per bet, $300 per spin.
- **Slots:** 3 reels, 1 line, wild clover, weighted symbols, target RTP ~101%.
- **Plinko:** 13 slots, Low/Medium/High rows; server picks slot then steers a physical chip.
- **Progressive jackpot:** 1% of slots and Plinko bets.
- Limits multiplier `1 + 0.5 × segment_index` (cap 3). All games tuned to RTP 100.5–102%.

## Luck
Luck L ∈ [−3, +3]. Single-player draws are rerolled with probability 0.12·|L| keeping the better
(L>0) or worse (L<0) candidate. Roulette uses "Lucky neighbour" / "Jinxed" effects. Always visible.

## Items (MVP 11)
Lucky Clover, Black Cat, Loaded Reels, Hot Hands, Double Trouble, Golden Chip, Pickpocket, Banana
Peel, Bodyguard, Mirror Mirror, Spring Glove. 3 inventory slots, 3 s cooldown, 5 s negative grace.

## Physical play
Grab/hold, shove (2 hits in 1.5 s or 3 in 4 s → knockdown/KO), throw, knockout 2.5 s, shake drops 2%
per shake capped 8% / $400×mult. Seated players protected. Security guards throw out attackers seen
within 8 m. Money never depends on physics.

## Online
Dedicated Godot server per room on the owner's VPS, FastAPI room orchestrator, ENet over UDP,
5-character room codes, Steam lobbies for invites/presence (M8).

## Game-feel checklist (M7)
- [ ] Every action has visual + audio feedback
- [ ] Wins/losses show clear deltas and character reactions
- [ ] Mouths move with voice
