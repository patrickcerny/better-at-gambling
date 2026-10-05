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
| player_shoved | bonk at the target |
| player_knocked_down | oof (banana/puddle: slip first) |
| player_knocked_out | bonk, low |
| player_got_up | jump, low and quiet |
| player_respawned (you) | whoosh, low |
| player_grabbed | oof, high |
| player_released / player_broke_free | thud / whoosh |
| player_thrown | whoosh |
| chips_dropped | chip_clack at the pile |
| chips_collected | pickup |
| pickup_expired | — (piles fade out) |
| chips_shaken_out | coin |
| player_sat (you) / player_stood (you) | ui_click / ui_hover |
| player_thrown_out | whistle (pea-whistle tweet-tweeet) |
| emote | jump, high |
| intent_rejected | buzzer for VIP denied; soft buzzer for other refusals with a toast |
| round_result | money pop: chip_clack (stake), coin, big_win (≥ $200); your loss: loss_sting (muted trumpet, at most every 6 s) |
| bet_placed | chip_clack (HUD stake) |
| jackpot_won | jackpot_siren (bell arpeggio, coin shower, held chord) |
| last_call | last_call_bell (brass hand bell ×3) + Last Call music |
| minigame_started | whoosh + quiz music |
| rewards_started | coin (reward panel) |
| draft_result (you, got items) | card_flip |
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
last_call, quiz (quiz and reward draft), results; 2.5 s equal-power crossfades. Loops are
generated by `tools/audio/gen_music.py` (walking bass, brushed kit, Rhodes, vibes).
