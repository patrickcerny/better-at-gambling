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
- **Wheel of Fortune** (Big Six money wheel, casino floor, its back to a wall in every layout): 54 segments, $1 ×24,
  $2 ×15, $5 ×7, $10 ×4, $20 ×2, Joker and Logo ×1 each. Chips on any symbols; a symbol pays its
  face value to one ($1 1:1 … $20 20:1), Joker and Logo 40:1, exactly as printed on the layout. The
  dealer spins 12 s after the first bet; the server draws the segment (house rule: a spin no bet
  would win is redrawn once with 31% chance, then luck rerolls, never shown) and every client slows
  the wheel onto it. 5 stools, a dealer. $10 min per bet, $200 per spin. Seated, each stool's view
  sits close over the layout and right of the middle so the wheel (over half the screen's height),
  the chips in every box and the dealer fill the left two thirds of the screen; the overlay is a column down the right third
  (symbols with their odds, chips, status, result and last spins, your bets), the rules folded
  under a HOW IT WORKS line.
- **Craps** (casino floor; east of the roulette pit on the full floor): two dice. Pass Line (come-out 7/11 win, 2/3/12
  lose, else the point, then the point before a 7) and Don't Pass (the other side, bar 12 pushes)
  1:1, ride until decided, go down only on a come-out; Field (2, 3, 4, 9, 10, 11 at 1:1, 2 and 12 at
  2:1) and Any Seven (4:1) for one roll. The shooter is whoever has sat longest and keeps the dice
  until a seven-out, then they pass on; SHOOT throws (2 s after a betting window opens), the
  stickman throws after 12 s. The client throws two tumbling dice that rest on the server's faces
  (a deterministic throw relabelled by a cube rotation, `CrapsDice`). The felt's odds are the real
  ones; the one-roll bets pay a bit better (Field 1.08 / 2.1, Any Seven 4.8) and a roll on which no
  bet wins and one would lose is redrawn with 5.5% chance, so every bet returns 101–101.6% to a
  player alone. A stickman (shoves like a dealer). $10 min per bet, $200 on the felt. Seated, each
  stool's view looks almost straight down from high over the felt, right of the middle, so the
  felt end to end, every seat's chips and the stickman fill the left two thirds of the screen; the overlay is
  a column down the right third (the four bets, chips, SHOOT, the point, the shooter or the last
  roll), the rules folded under a HOW IT WORKS line.
- **Hi-Lo** (casino floor; east of the roulette pit on the full floor): oval card table, a dealer, 4 seats, one shared
  single deck (aces high, reshuffled under 15 cards). Everyone plays their own hand: ante, a card is
  turned up, call HIGHER or LOWER (a tie loses). Each call shows its true chance from the cards left
  and its pay, locked when the card goes up: the fair odds less a small edge (×2.00 at 47% on an 8,
  ×1.06 at 94%, ×11.42 at 8%), at most ×25. A right call multiplies the pot; ride it on the next
  card or cash out; the ladder stops at 6 right calls or 50× the ante. Timeout (15 s), standing up
  or the match end: a won pot is cashed out, a fresh ante takes the likelier side. A minigame gives
  fresh antes back and banks won pots. House rule as at the horse race (0.9.6): a call that would
  lose has its card redrawn once with 15% chance, then luck rerolls it; never shown. $10–$100.
- **Casino Hold'em** (casino floor; only in The Grand Hall layout until the layout generator places it): oval card table, a
  dealer, 4 seats, one fresh deck per hand (Evolution's / bwin's Casino Hold'em). ANTE ($10–$100)
  plus an optional AA BONUS (up to $50), 8 s betting window; two hole cards each, the dealer two
  face down, the flop. FOLD (the ante is lost) or CALL for twice the ante on your own 15 s clock
  (out of time, standing up or the match end = fold); the balance must cover the call when you
  ante. Turn and river, best five of seven. The dealer qualifies with a pair of 4s or better: if
  not, the ante pays by the table and the call comes back; if so, a win pays the ante by the table
  and the call 1:1, a tie gives both back. Ante table: royal 100, straight flush 20, quads 10, full
  house 3, flush 2, straight or lower 1. AA Bonus on your two cards and the flop, paid at the flop
  even if you fold: pair of aces to straight 7, flush 20, full house 30, quads 40, straight flush
  50, royal 100. House rules (never shown): the turn, river and dealer's cards are drawn again once
  with 12% when nobody would win and someone would lose; a flop on which no bonus bet pays is drawn
  again once with 9.5%; luck rerolls hole cards, flop and showdown through `LuckRng`. A lone
  player with the simple strategy (call any pair, an ace or king in the hole, or a flush/straight
  draw) gets about 101.1% back; the AA Bonus 101.1% (93.7% plain). A minigame gives the open ante
  and call back (a bonus the flop settled stays). The overlay is a column down the right third
  (ante chips, AA BONUS sizes, DEAL; FOLD / CALL with amounts, the hand named live, the dealer's
  hand, the result), the paytables folded under HOW IT WORKS; each stool's view frames the board,
  the dealer and the seat's own cards and spots in the left two thirds.
- **Scratch Cards** (counter on the casino floor, by the Gift Shop on the full floor): one player at the counter at a time. Buy a
  $10 / $25 / $50 card (× limits); the server draws the whole card at purchase and sends it in one
  `scratch_card` event; the panel shows it big under foil, scratched with the mouse or REVEAL ALL,
  and it pays (`action reveal`) once bare, on walking away, or after 60 s. 3×3 symbols: three in a
  row/column/diagonal pays that symbol's printed prize, a $ anywhere the instant prize. Prize tables
  (× price, cherry/lemon/bell/clover/seven/diamond, then $): $10 1/2/3/5/15/50, $0.5; $25
  1/2/4/8/25/100, $0.4; $50 1/3/5/10/40/200, $0.5. House rule: a blank is drawn again once with 25%
  chance (`scratch_favour`), then luck rerolls the card; RTP 101.2% per tier. Fixed prices: a card
  the balance can't cover is greyed out and refused, never sold cheaper (no all-in at the kiosk).
- **Sword Tapper** (two pedestals `sword_1` / `sword_2` side by side on the casino floor; modelled
  on Greentube's Lucky Sword – Tapper): a marble plinth with a gold sword in a grey stone, ringed by
  17 gem lamps on burgundy velvet, each printed with its prize for the stake. One player per
  pedestal, standing (no stool). Pick a $10–$100 stake (× limits, chip buttons, all-in over the
  balance) and tap PULL (Space / E / gamepad A pulls again with the same stake): the sword stays
  (stake lost; thud, dust puff) or comes free and lights 3 to 17 gems (a uniform pick from the
  ring), paying their sum; a win of 9 or fewer gems may get ×2 / ×3 / ×5 / ×10. Ring (× stake):
  6 × 0.1, 4 × 0.2, 2 × 0.3, 2 × 0.5, 1, 2 and the ruby 5 at the top (all 17 = 11×; best pull the
  nine biggest × 10 = 100×, `sword_max_pay` 100× is only a clamp). Free at 24%
  (`sword_pull_chance`); house rule (0.9.6): a stuck pull is drawn again once with 8%
  (`sword_favour`), then luck rerolls the whole pull like a slot line; neither is shown or sent.
  The panel says "about 1 pull in 4 frees the sword". Exact RTP 100.9% at luck 0 (95.1% without
  the house rule); free 25.5%, ≥ 1× 19.6%, ≥ 10× 1 in 59, ≥ 50× 1 in 3,200. Decided at the tap
  (one `sword_pull` event), paid when the 2.5 s reveal ends, or at once on walking away, being
  knocked off, the casino closing or a minigame starting (never refunded); a pull later than 3 s
  before closing is refused. A pull paying ≥ 20× posts "X pulled the sword: $N!" in the feed and
  raises a golden light column over the pedestal. Seat view right over the pedestal's top, the
  ring of gems and the stone filling most of the screen; a compact overlay on the right draws the
  same ring (gem dots sized and coloured like the lamps, the ruby at the top, the prize for the
  stake beside each, the multiplier rule on the stone, lit as the pedestal lights them), then the
  chips, PULL, the last pulls and HOW IT WORKS. Not a Hot Table candidate; slot-only items do not touch it.
- **Progressive jackpot:** 1% of slots and Plinko bets.
- Limits multiplier `1 + 0.5 × segment_index` (cap 3). All games tuned to RTP 100.5–102%.

**Floor layouts** ([`FLOOR_PLAN.md`](FLOOR_PLAN.md)): the casino floor has six hand-made layouts
(`data/floor_layouts/*.tres`: The Grand Hall, Wheel Night, The Pit, The Arcade, The Long Room, The
Salon). A layout moves and turns the games only (the wheel's back to a wall, craps players on a
walkway, blackjack dealers backed by a wall or each other, Plinko on the north wall, the scratch
counter by the Gift Shop or the lobby wall, nothing in the entrance hall); the room, the VIP
lounge, the Race Hall, the waiting room, Odd Jobs, the shop and the jail never move. Online matches
take the next layout from a shuffled bag (seeded, no repeats before the bag is empty, never the
same twice in a row) when the lobby opens and at every regroup, while everyone is shut in the
entrance hall; the feed says "The floor has changed!". A layout that needs a game that is off
(weight 0) or does not fit the map is skipped and the next one goes in; there are no closed spots,
ropes, signs or boards. Practice and the menu keep The Grand Hall. There is no bar on the casino
floor (Patrick: "the casino bar (its useless)").

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

## Emotes
Seven on the wheel (hold **G** / D-pad down, point, release): **6-7** (top slot), wave, laugh,
taunt, cry, dance, GG; and on the number keys while walking: **4** thumbs up, **5** thumbs down,
**6** 6-7, **7** the default dance (remappable, Settings > Controls). Every emote is sent as an
intent and played on every client from its id (`Emotes`; a late joiner picks one up part-way
through), shows its bubble ("🤲 6-7", "👋 WAVE") when it is a wheel emote, and is acted out by the
bean in beats (`EmotePoses`): a wind-up, key poses reached with a small overshoot and held, the
body squashing, bouncing and tilting along, arms swinging in arcs (and stretching like rubber
hoses on a reach), and the face playing its part. Each has its own length (2.2–3.4 s,
`Emotes.LENGTHS`) and a sound cue timed to its beats (`emote_<id>.wav`), which stops if the emote
is cut short. Walking off (after the first 0.3 s), a hit, a shove, a ragdoll, sitting down or a
new emote ends one; our own emote swings the camera round to watch it (emote cam).

| Emote | What the bean does |
|---|---|
| 6-7 | Hands come up in front at chest height, palms up, and weigh "six… seven" up and down in turn like scales: eight words, snapping to the top and bottom and holding a beat, the body bouncing on every word and tilting to the lower hand, eyes on the hand going up, mouthing the words. Ends in a shrug: hands out to the sides, shoulders up, head cocked, brows up, mouth flat. Cue: a woodblock "six" and "se-ven" on each word, a muted-trumpet "meh" on the shrug. |
| Wave | A little crouch, a hop as the right arm swings up in an arc and stretches, then big waves with the wrist flicking behind the arm, the body swaying along, the left foot kicked up behind, a "hiii" grin with bouncing brows. Cue: slide whistle up, a "hel-lo" whistle. |
| Laugh | Scrunches up with a snort, then jabs a pointing finger at you and rocks back cackling "ha-ha-ha", eyes squeezed shut; doubles over clutching its belly, stamping a foot, tears of joy; comes up with a happy sigh. Cue: a muted-trumpet cackle, a wheezing "hee-hee", a sigh. |
| Taunt | Crouch and pop, thumbs at the temples with the fingers waggling, head tilting side to side, a wink and the tongue out; a half turn to wiggle its bum at you with two slaps; turns back for a smug finish (arms crossed, chin up, one brow raised, side glance). Cue: kazoo "nyah-nyah na-nyah-nyah", two slaps, whooshes on the turns. |
| Cry | Lip wobbles and the eyes go big and wet, a wail with the head thrown back and the arms flung up, then fists rubbing the eyes in turn while the shoulders hitch with every sob, foot stamps, tears running; a big sniff and a slump. Cue: a muted-trumpet "waaah", a sob on every hitch, a sniff. |
| Dance | The disco: on every beat the right hand stabs a finger up to the ceiling and down across to the other hip, snapping there and holding, hips swaying and the knees bouncing; a hop into a full twirl with the arms out; a finger-to-the-sky finish with a wink. Cue: four-on-the-floor kick and bass, a riser into the twirl, a vibes "ta-da". |
| GG | A wind-up and the hand shoots out for a handshake, a step in, three firm pumps with the other hand on top; hand to the belly, the other behind the back, a slow deep bow with the eyes shut; a hop back up with a thumbs up and a wink. Cue: soft pats on the pumps, a warm chord on the bow, a "ding" and coins on the thumbs up. |
| Thumbs up | The fist pulls in, punches out thumb up with a pop and a wink, a confident nod; the other hand joins with a hop and both pump while the brows waggle. Cue: a click and a "ding!", a higher one for the second thumb. |
| Thumbs down | Thumb up first with a hopeful face, then it turns slowly over as the smile sinks into a frown; three "boo" pumps downwards with the other hand joining, head shaking. Cue: a sinking slide whistle, three muted-trumpet "boo"s. |
| Default dance | The Fortnite default dance, a pose on every beat: fists punch down across the hips in turn, then both arms swing up over the head to one side and the other, hips swaying, knees giving, a foot kicking out, a hop at the end of each bar. Cue: kick-and-snare beat with a walking bass at the dance's tempo. |

## Minigames
- **Jackpot Climb** (climb room "towers"): mostly a run, up a 26 m cake of giant casino chips to
  the gold pad under the JACKPOT sign. Three giant-chip tiers (tops at 8.5, 16 and 21.5 m) each
  carry a checkpoint flag. From the apron and from every flag the way up forks into two felt lanes
  that wind round the ring to the next tier: a steady lane (green felt, all running: even ramps of
  6–12°, and on the two upper rings a spiral walkway of 1.25 turns under a wide outer band) and a
  bold lane (burgundy felt, the other way round, about a fifth shorter, with one or two short hops
  of 0.7 m up onto wide chip tops; seven hops in all). The last ring winds round the jackpot stack
  to the pad. Chevron arrows on the felt point up the lane. Nowhere on the course can a bean get
  stuck: every spot leads on uphill or drops far enough to be sent back to the flag, and a player
  who never jumps finishes on the steady lanes. The layout is fixed, so everyone climbs the same
  tower. The server sets each bean's checkpoint when it stands on a tier and puts anyone who
  drops 2.5 m below it back at that flag (before the first flag a fall just lands on the net). Bats
  knock climbers off, shoving is on, grabbing off. 150 s; first to the pad wins, then the order of
  arrival, then the rest by height (never counted below their checkpoint), with a 10 s last call
  once all but one are up.

## Settings and first launch
One settings file per PC (`user://settings.cfg`, never synced): GAME (field of view), VIDEO
(fullscreen, VSync, frame limit), AUDIO, CONTROLS (remappable keys). The game always renders at
the window's full resolution with smooth (linear) filtering, in menus, the match and minigames;
the first launch goes straight to the main menu. **F11** (remappable) toggles fullscreen
anywhere and saves it. The Hot Table's arrow over the table is the same size on screen from
anywhere on the floor and shows through walls.

## Progression
Out-of-match progress (Patrick: "Create a XP level and an ingame currency"), kept per PC in
`user://profile.cfg` by the `ProfileManager` autoload (`PlayerProfile`): XP and level, **Coins**,
owned and preferred cosmetics, lifetime stats (matches, wins, biggest single win). No accounts:
loading clamps every value (level always recomputed from XP, unknown items dropped), no DRM.
- **XP per match**, computed by the server from match data and sent per player in `match_ended`
  (`progress`, with a `match_id`), so every screen shows the same numbers; each client adds only
  its own row, once per match id. Clients never send XP. Data: `data/progression/progression.tres`.
  Match played 100, placement 120 / 80 / 50 / 30 / 20 (5th and below), 30 per minigame won,
  1 per $20 of profit (max 100), 2 per table hand (max 60), at most 2,000. Practice earns half.
  A typical match (2nd, one minigame, +$600, 20 hands) is about 280 XP.
- **Level curve**: level L → L+1 costs 100 + 35 × (L − 1) XP up to level 10 (2,160 XP in all,
  about 8 matches), then 450 + 50 × (L − 10), so levels 10 → 20 take about 24 more matches.
  Level 99 is the cap.
- **Coins** (the gold coin; "chips" are the casino's): a tenth of the match's XP plus 50 per
  level gained. Earned only by playing, never bought, never spendable at the tables: the in-match
  $ is separate and starts fresh every match, and the UI says so wherever Coins show.
- **UI**: the main menu's top-left line (LEVEL n, XP bar, Coins); on the results screen every
  standings row shows "+N XP" and YOUR PROGRESS (bottom corners) lists where the XP came from,
  the Coins (with the level-up bonus) and fills the level bar ("LEVEL 7 → 8"). Nothing new in the
  HUD.

## Cosmetics shop
The bean is the only body (Patrick: "Remove all other skins"; the six poly.pizza character skins
went in 0.9.16); what players choose is its colour.
- **Colours**: 16 (`Cosmetics.COLOR_COUNT`, `Palette.PLAYER_COLORS`). The first 8 are the
  colourblind-safe player colours, free and always owned; Ruby, Mint, Lavender, Teal, Lime, Onyx,
  Silver and Gold cost 150–400 Coins (`data/progression/cosmetics_shop.tres`).
- **Slot colour vs bean colour**: the server still hands every player one of the 8 free colours
  (first free, unique): it marks them on the HUD, the name plates and their ready pedestal. The
  bean wears the player's **preferred colour** (profile, sent in the hello) when no other bean
  wears it; otherwise their slot colour; if even that is worn, the first colour nobody wears. Two
  beans never share a colour. The server checks only the index (ownership is local).
- **The shop**: COSMETICS in the main menu (also the T-shirt button, and COSMETICS on the lobby
  settings tablet's panel). A turning bean previews the picked colour; BUY spends Coins ("Not
  enough Coins: N more to go" otherwise), WEAR makes it the preferred colour (in a lobby it goes on
  the bean at once). One tab per kind of cosmetic in stock: `CosmeticDef` (kind colour | hat | …,
  price, id) in the `CosmeticShop` list, so hats and the like slot in later; only colours exist now.
- **Pedestal colour panel** (Patrick: "under the podest should be a color panel you can click"):
  a brass plaque at the foot of every ready pedestal. Yours shows the colours you own, the one you
  wear framed and the ones other beans wear dimmed; look at a swatch and click (or E) to wear it:
  `set_color` → the server checks it is free → `player_color` recolours your bean for everyone,
  and it becomes your preferred colour. Other players' panels don't work for you. Lobby only.
- The Tab list ("THE TABLE") shows each player's bean in its colour as the portrait.

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
| player_color | pickup pop at the avatar |
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
| emote / player_emote | the emote's own cue `emote_<id>` at the bean (see Emotes), cut off with the emote |
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
| holdem_action | — (the ante and the AA Bonus are chips: bet_placed plays chip_clack; a fold slides the hand into the muck) |
| holdem_showdown | card_deal as the turn, the river and the dealer's two go over (TableCards) |
| sword_pull | stone_grind as the bean heaves; stuck: thud, low, and a dust puff; free: sword_ring (metal ring-out) and a ring of light, plink per lit gem (pitch rising), thud + coin as a multiplier slams down; stone_grind, high and quiet, as the sword sinks back (big win: the round_result fanfare and the golden light column) |
| scratch_card | card_deal as the card slides out of the kiosk's dispenser; scratching plays the scratch rasp per stroke (pitch varied) and a higher one as each cell's foil pops off |
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
