# Better at Gambling — Game Design (condensed)

Authoritative long form: [`docs/MASTER_PROMPT.md`](MASTER_PROMPT.md) §1–§2. Keep this summary in sync
with what is actually built.

## Pitch
Online 2–8 player casino party game (bots fill slots) with free first-person movement in a stylized
casino. Everyone starts with **$1,000 in fictional chips**; richest at the end wins. Physical
"friendslop" chaos (grab, shove, throw, ragdoll, shake chips out of knocked-out rivals) and
proximity voice. **Fictional currency only**: no real money, purchases, cash-out or loot boxes.

## Match loop
Lobby (physical entrance hall, ready pads) → Intro → Casino segment → Minigame (open bets are
refunded and everyone is stood up first) → Round results (cash by placement + one item each,
rolled by rarity weighted by placement) → Regroup (5 s in the entrance hall, doors shut) → Casino …
→ last gambling stretch with Last Call (final 60 s, winnings ×1.5) → Results.

The host sets the match length in the lobby: **minigames** (default 5, 1–10) and **gambling minutes
between them** (default 3, 1–6); duration = gambling minutes × (minigames + 1).

Timer counts casino time only. House Comp when broke (once per segment): $300, then $450, $600,
$750 after each minigame played, $900 from the fourth on (`BalanceConfig.comp_amounts`).

**Odd Jobs** cabinet next to the Gift Shop (casino phases, not in minigames-only): look at its big
red 3D button and click (or E). One bar shared by everyone; each click adds the clicker's share,
1/presses where presses = 10 at $0 up to 60 at $499 (refused at $500+), and the click that fills
the bar wins $50, then it starts over. Idle bar drains 0.1/s after 0.5 s; no click rate limit.
The aim target is the cabinet's whole front (deck, bar riser, marquee), not just the cap.
The cabinet's lamps pulse and the button is outlined while you are below the House Comp line.

## Casino games (MVP)
- **Blackjack:** 6-deck shoe, S17, 3:2, double any two (also after a split), split one pair once
  (aces get one card each), simultaneous play, Dealer Bust Bonus 1.07:1. Limits $10–$200.
- **Roulette:** European, straight/colour/odd-even/low-high/dozens/columns, +5% generosity. $10
  min per bet, $300 per spin.
- **Slots:** 3 reels, 1 line, wild clover, weighted symbols, target RTP ~101%.
- **Plinko:** 13 slots, Low/Medium/High rows; server picks slot then steers a physical chip.
- **Horse Race** (Race Hall annex): 4 horses with names drawn from a pool each round, one horse per
  player per race, the first over the line pays 1:4. A seeded server race (~9 s, the lead changes)
  every client replays. $10–$100.
- **Wheel of Fortune** (Big Six money wheel, casino floor by the lobby doors): 54 segments, $1 ×24,
  $2 ×15, $5 ×7, $10 ×4, $20 ×2, Joker and Logo ×1 each. Chips on any symbols; a symbol pays its
  face value to one ($1 1:1 … $20 20:1), Joker and Logo 40:1, exactly as printed on the layout. The
  dealer spins 12 s after the first bet; the server draws the segment (house rule: a spin no bet
  would win is redrawn once with 31% chance, then luck rerolls, never shown) and every client slows
  the wheel onto it. 5 stools, a dealer. $10 min per bet, $200 per spin.
- **Craps** (casino floor, east of the roulette pit): two dice. Pass Line (come-out 7/11 win, 2/3/12
  lose, else the point, then the point before a 7) and Don't Pass (the other side, bar 12 pushes)
  1:1, ride until decided, go down only on a come-out; Field (2, 3, 4, 9, 10, 11 at 1:1, 2 and 12 at
  2:1) and Any Seven (4:1) for one roll. The shooter is whoever has sat longest and keeps the dice
  until a seven-out, then they pass on; SHOOT throws (2 s after a betting window opens), the
  stickman throws after 12 s. The client throws two tumbling dice that rest on the server's faces
  (a deterministic throw relabelled by a cube rotation, `CrapsDice`). The felt's odds are the real
  ones; the one-roll bets pay a bit better (Field 1.08 / 2.1, Any Seven 4.8) and a roll on which no
  bet wins and one would lose is redrawn with 5.5% chance, so every bet returns 101–101.6% to a
  player alone. A stickman (shoves like a dealer). $10 min per bet, $200 on the felt.
- **Hi-Lo** (casino floor, east of the roulette pit): oval card table, a dealer, 4 seats, one shared
  single deck (aces high, reshuffled under 15 cards). Everyone plays their own hand: ante, a card is
  turned up, call HIGHER or LOWER (a tie loses). Each call shows its true chance from the cards left
  and its pay, locked when the card goes up: the fair odds less a small edge (×2.00 at 47% on an 8,
  ×1.06 at 94%, ×11.42 at 8%), at most ×25. A right call multiplies the pot; ride it on the next
  card or cash out; the ladder stops at 6 right calls or 50× the ante. Timeout (15 s), standing up
  or the match end: a won pot is cashed out, a fresh ante takes the likelier side. A minigame gives
  fresh antes back and banks won pots. House rule as at the horse race (0.9.6): a call that would
  lose has its card redrawn once with 15% chance, then luck rerolls it; never shown. $10–$100.
- **Progressive jackpot:** 1% of slots and Plinko bets.
- Limits multiplier `1 + 0.5 × segment_index` (cap 3). All games tuned to RTP 100.5–102%.

**Floor plan** ([`FLOOR_PLAN.md`](FLOOR_PLAN.md)): in online matches every casino round starts on a
new floor. The floor is a set of fixed spots (table-, slot- and Plinko-sized, on the floor and in
the VIP lounge); when the lobby opens and at every regroup (everyone shut in the entrance hall)
each spot is redrawn from the match seed: a game of its size that fits there (measured floor,
keep-outs, a walkway to its neighbours) by weight, or closed tonight (velvet
rope and a CLOSED TONIGHT sign, or a plant). Nothing is guaranteed; at least 60% of each area is
open and at most 2 tables of one game per area (soft). The Race Hall, the waiting room, Odd Jobs,
the shop and the jail never move. A TONIGHT'S FLOOR board in the entrance hall lists the games and
the feed says "The floor has changed". Practice keeps the full floor. New table games join the
draw on their own (`FloorPlanConfig`, `GameDefinition.floor_footprint`).

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

## Minigames
- **Jackpot Climb** (climb room "towers"): a jump-and-run up a 26 m cake of giant casino chips to
  the gold pad under the JACKPOT sign. Three giant-chip tiers (tops at 8.5, 16 and 21.5 m) each
  carry a checkpoint flag; round every tier two lanes of chip stacks fork at the flag and rejoin
  on the next tier: a steady side of short hops (0.6–1.2 m of air) and a bold side with one or two
  wide running jumps (2.6–2.9 m), the last climb round the jackpot stack is two lanes of narrow
  stacks. The layout is fixed, so everyone climbs the same tower. The server sets each bean's
  checkpoint when it stands on a tier and puts anyone who drops 2.5 m below it back at that flag
  (before the first flag a fall just lands on the net). Bats knock climbers off, shoving is on,
  grabbing off. 150 s; first to the pad wins, then the order of arrival, then the rest by height
  (never counted below their checkpoint), with a 10 s last call once all but one are up.

## Online
Dedicated Godot server per room on the owner's VPS, FastAPI room orchestrator, ENet over UDP,
5-character room codes, Steam lobbies for invites/presence (M8).

## Game-feel checklist (M7)
- [ ] Every action has visual + audio feedback
- [ ] Wins/losses show clear deltas and character reactions
- [ ] Mouths move with voice

### Event → sound map (M7 audio pass)
Every server event `MatchScene._on_event` handles has a sound (or is silent on purpose, marked
"—"). Clips live in `audio/sfx/` (recorded Kenney CC0 takes `<name>-vN.ogg`, synthesized
`<name>.wav` from `tools/audio/gen_sfx.py`); the calls are in `match/match_scene.gd`,
`audio/event_sfx.gd` and `npc/casino_floor.gd`. `tests/unit/test_audio_moods.gd` fails if any
`Audio.play*(&"name")` in the game has no clip.

| Event | Sound |
|---|---|
| player_joined / player_rejoined | ui_click (soft) |
| player_left | ui_hover, low |
| player_removed | — (follows player_left) |
| player_skin | pickup pop at the avatar |
| match_started / phase INTRO | chime (lounge vibes roll) |
| phase PRE_MINIGAME | countdown_beep (+ HUD per-second beeps) |
| phase CASINO after rewards | chime |
| player_shoved | whoosh on the press (predicted swing), bonk + hit pop at the contact moment |
| player_knocked_down | oof (banana/puddle: slip pose; shove, wall slam, bottle: ragdoll) |
| player_knocked_out | bonk, low |
| player_got_up | jump, low and quiet |
| player_respawned (you) | whoosh, low |
| player_grabbed | oof, high |
| player_released / player_broke_free | thud / whoosh |
| player_thrown | whoosh |
| chips_dropped | chip_clack at the pile |
| chips_collected | chip_clack + coin, chips fly into the collector, "+$X" pop (own pickups predicted online) |
| pickup_expired | — (piles fade out) |
| chips_shaken_out | coin |
| player_sat (you) / player_stood (you) | ui_click / ui_hover |
| player_thrown_out | whistle (pea-whistle tweet-tweeet) |
| emote | jump, high |
| intent_rejected | buzzer for VIP denied; soft buzzer for other refusals with a toast |
| round_result | money pop: chip_clack (stake), coin, big_win (≥ $200); your loss: loss_sting (muted trumpet, at most every 6 s) |
| bet_placed | chip_clack (HUD stake) |
| horse_race_countdown | — (the tote board counts down) |
| horse_race_started | last_call_bell, high (the starting bell) |
| horse_race_finished | chime when the winner's nose crosses the line on the table |
| craps_rolled | chip_clack, low (the dice leave the hand; another as they rest) |
| wheel_spin_started | whoosh, low (the dealer's pull), then the clicker: plink, high, one per peg (at most ~20/s) |
| wheel_result | — (the clicker slows down); reel_stop, low, as the wheel rests on the segment |
| hilo_dealt / hilo_call | card_deal as the card slides out of the deck onto the seat's spot (TableCards) |
| hilo_reshuffle | — (the deck on the table is full again) |
| jackpot_won | jackpot_siren (bell arpeggio, coin shower, held chord) |
| last_call | last_call_bell (brass hand bell ×3) + Last Call music |
| minigame_started | whoosh + quiz music |
| rewards_started | coin (reward panel) |
| bets_refunded (you) | chip_clack |
| regroup_started | whoosh |
| hot_table | hot_table (shimmer + rising vibes) |
| house_comp | cash_register |
| match_ended | big_win on the podium + results music |
| match_reset | chime + casino music |
| item_used | whoosh + per item: bonk (bat, bottle, roulette bang, blocked), coin (scratch, pickpocket), boing (mirror), chip_clack (others) |
| bodyguard_saved | bonk, low |
| banana_placed | thud, high |
| banana_slip | slip (slide-whistle zip + skid) |
| monkey_passed | boing |
| credit_repaid | chip_clack, low |
| collar_cut | coin |
| fake_cash_used | — (it's sneaky) |
| fake_cash_caught | buzzer |
| rps_invite / rps_start | countdown_beep |
| rps_result | big_win / loss_sting |
| rps_cancelled | ui_hover, low |
| shop_bought | cash_register |
| shop_restocked | — |
| discard_needed | countdown_beep |
| waiter_tripped | tray_crash (tray clatter, glass, splash) |
| puddle_slip | slip + small splash |
| puddle_removed | — (dries up) |
| megaphone_taken / megaphone_dropped | megaphone (click + bullhorn chirp) / ui_click |
| (world) fountain fall | splash |

Music (`Audio.set_mood`, `audio/music_mood.gd`): menu, casino (lobby, intro, casino floor),
last_call, quiz (quiz and round results), results; 2.5 s equal-power crossfades. Loops are
generated by `tools/audio/gen_music.py` (walking bass, brushed kit, Rhodes, vibes).
