# Art & Audio Direction (binding)

Adopted 2026-10-04 at Patrick's request. **This document governs everything visual and audio**: style,
palette, characters, cosmetics, environment, menu, logo, HUD, betting presentation, quiz / Last Call /
results presentation, icons and sound. **Gameplay rules stay as defined in
[`MASTER_PROMPT.md`](MASTER_PROMPT.md)**. Where the text below mentions gameplay (item names, VIP
threshold, quiz answer count), it is only an example of *presentation*; the master prompt's rules win.

Concept image: [`concept_main_menu.png`](concept_main_menu.png). It shows the target mood for the
main menu (blackjack table in the foreground, fountain with gold bean statue, red-carpet staircase to a
VIP balcony, slots, revolving door, guard chasing a player, knocked-out bean on the carpet).

## How this maps onto the master prompt (decisions)

| Topic | Master prompt said | Now |
|---|---|---|
| UI theme | Art-deco gold + neon magenta/teal on deep purple | **Palette below** (black/charcoal, cream, casino red, felt green, gold). No neon magenta/teal, no purple. |
| Lighting | bloom/glow on neon signs | Warm lamps and chandeliers, dark corners, gold reflections. Glow only on bulbs and signage (marquee bulbs, JACKPOT sign), never cyberpunk neon. Cold blue only for special moments. |
| Characters | bean, googly eyes, mitten hands | Bean torso, almost no neck, tiny legs, **long floppy arms, oversized simple hands, small dot eyes**, mouth `-` / `o` / `O` by voice volume. |
| Hats | 6 placeholder hats | Head / face / body attachment slots (lists below). Same cosmetic-only, no-randomness rules. |
| Main menu | 2D menu | **3D casino scene as the background** (lobby + blackjack table), menu on the left: PLAY, JOIN FRIENDS, CUSTOMIZE, SETTINGS, QUIT. Ambient chaos events loop in the background. PLAY opens Create Party / Practice vs Bots / Tutorial; JOIN FRIENDS opens Join by Code / Rejoin (Steam invites arrive automatically). |
| Betting UI | shared 2D bet panel for all games | **Physical first**: roulette chips placed on the 3D table, slots via a pulled lever, Plinko dropped into the visible machine. Blackjack uses the simple overlay shown below. The 2D bet panel remains as the keyboard/gamepad/accessibility path. |
| VIP | ≥ $2,000 (× limits multiplier) | Rule unchanged; the sign displays the live threshold in the "VIP ACCESS — $X+" style. |
| Results | podium scene | Podium **in the casino lobby**, players keep ragdoll physics and can shove each other off it while stats show. |
| Fonts | Lilita One / Nunito | **Barlow Condensed** (Black/ExtraBold for logo and headings, SemiBold/Medium for body), OFL. |
| Shaders | toon ramp + rim | Keep shaders simple: lightly stylised lit materials (soft toon ramp allowed), no complicated effects. |

---

## The direction (as provided)

### Overall art style
Stylized low-poly 3D casino look with simple geometry that is realistic enough to feel like a casino,
but exaggerated and comedic enough to fit a chaotic multiplayer party game.

Main design principle: **"A casino that tries to look luxurious, but everything happening inside it is
stupid and chaotic."**

The environment should feel expensive at first glance: red carpet, gold trims, chandeliers, marble
floors, velvet ropes, dark wood, green blackjack felt, warm lighting, VIP balconies.

But the characters and gameplay constantly undermine that seriousness: someone stuck in the revolving
door, someone unconscious next to a gambling table, security guards chasing players, money flying
through the room, characters fighting near expensive furniture, someone falling into a fountain.

Do NOT use a cyberpunk casino style. Avoid excessive neon, futuristic holograms, realistic human
characters, or overly detailed assets. Visuals must stay feasible for a small indie team in Godot 4.

### Color palette
| Name | Hex |
|---|---|
| Casino Black | `#151414` |
| Warm Charcoal | `#24211F` |
| Cream | `#F2E6C9` |
| Casino Red | `#C83D3D` |
| Felt Green | `#275E49` |
| Warm Gold | `#D6A84B` |
| VIP Burgundy | `#681F2C` |
| VIP Gold | `#E3B95C` |
| Money Green | `#68C26F` |
| Loss Red | `#E55353` |

Lighting is warm and cinematic: yellow/orange lamps, warm chandeliers, dark corners, gold reflections,
soft ambient light. Avoid cold blue lighting except for special gameplay/UI moments.

### Characters
Simple bean-shaped ragdolls (inspiration: Gang Beasts, PEAK, Human Fall Flat): rounded bean torso,
almost no neck, tiny legs, long floppy arms, oversized simple hands, small dot eyes, very simple face,
soft rounded silhouette. They should look funny even when standing still.

Physics animation is extremely important. They stumble, wobble, flop when knocked out, drag behind
slightly when running, struggle when carrying another player, fall dramatically when thrown.

Mouth animates with microphone volume: closed `-`, talking `o`, loud `O`.

### Cosmetics (simple attachments, not new models; funny rather than cool)
- Head: cowboy hat, casino visor, tiny top hat, crown, dealer hat, lampshade, propeller hat
- Face: sunglasses, moustache, monocle, clown nose
- Body: bow tie, tie, Hawaiian shirt, suspenders, gold chain

### Casino layout (presentation)
Compact, so players constantly run into each other.
- **Entrance lobby** (also the main-menu location): large revolving entrance door (a usable hazard:
  players get stuck, pushed, thrown into it), central fountain, reception desk, chandelier, velvet
  ropes, casino logo sign, staircase toward the main casino.
- **Main floor:** strong sightlines so players see what others do. Blackjack and roulette central
  (most social), slots lining the walls, Plinko as a large physical machine visible from far away.
  Different carpet/floor accents identify game areas.
- **VIP floor:** visible from the main floor; players look up and see richer players gambling. Access
  sign in the style `VIP ACCESS — $X+`. Exaggerated luxury: gold statues, darker red carpet, expensive
  furniture, better lighting, private tables, balconies overlooking the lower floor. Intentionally
  excessive.

### Main menu
The casino itself is the background (no flat menu screen). Camera looks across a blackjack table; a
bean sits opposite holding cards; another player lies unconscious nearby. Background: security chasing
somebody, a player stuck in the revolving door, slot machines running, the fountain, the VIP staircase,
other players causing chaos. Menu on the left: logo, then PLAY, JOIN FRIENDS, CUSTOMIZE, SETTINGS, QUIT.
Small background events happen automatically now and then: someone falls down the stairs, security runs
past, a player falls into the fountain, someone wins a jackpot, chips fly across the room, someone gets
thrown through frame. The menu communicates the game's personality before Play is pressed.

### Logo
Reads BETTER / AT / GAMBLING in large condensed uppercase (Barlow Condensed Black / ExtraBold).
`BETTER` large, `AT` smaller, `GAMBLING` largest and strongest. Cream, red, gold accents; slightly
distressed or imperfect, like an old casino sign. A small spade, dice or decorative gold line is fine;
typography stays dominant.

### UI / HUD
Minimal while walking around:
- Top left: large money value (`$2,840`); changes pop as `+$450` / `-$450` (Money Green / Loss Red).
- Top right: match timer (`08:42`).
- Bottom right: ranking (`2nd / 8`).
- Bottom center: item slots (`[1] Clover [2] Shield [3] …`).

Use cream, gold, black, red, green. Avoid modern mobile-casino UI; it should feel like physical casino
signage, cards, chips, scoreboards and printed signs.

### Betting presentation
Whenever possible, gambling interactions happen physically in the world instead of a separate menu.
Roulette: click/place chips directly on the 3D table. Slots: pull the lever. Plinko: interact with the
machine and watch the ball drop. Blackjack may use a simple overlay:

```
BLACKJACK
YOUR HAND
K♠ 7♥
17
[ HIT ] [ STAND ]
BET
[-] $250 [+]
```
Large, readable buttons.

### Quiz
Gambling pauses for a shared quiz; casino lights change or dim; a game-show UI appears
(`CASINO BREAK!`, question, lettered answers, big countdown). Exaggerated casino game show. After the
questions: `QUIZ RESULTS` ranking, then `PICK YOUR REWARD`.

### Item icons
Simple, bold, readable at small sizes: thick silhouettes, very little internal detail, a strong symbol
on a simple coloured background.

### Last Call
The final 60 seconds feel dramatically different: `LAST CALL`, big timer, `x1.5 PAYOUTS`. Timer grows,
music speeds up, lighting shifts slightly red, casino signs flash. Players immediately understand the
final chaotic phase has started.

### Results
No sterile scoreboard: all players stand physically on a podium in the casino lobby, winner in the
centre, with place, name and money (`1st PLAYER 1 $9,420`). Funny stats: Biggest Win, Biggest Loss,
Most Shoves, Most Knockouts, Luckiest Player, Worst Gambler (alongside the master prompt's awards).
Ragdoll physics stays on: players shove each other, fall off the podium and attack the winner.

### Audio
- Casino music: lounge jazz, upright bass, brushed drums, muted trumpet, vibraphone, slightly cheesy
  casino elevator-music feel. Menu music relaxed but slightly suspicious. Quiz music like a game show.
  Last Call reuses the casino theme, faster and more intense.
- SFX: chips = sharp satisfying clacks; big win = bells + coins + short celebration; loss = short sad
  casino sting; ragdoll impact = comedic BONK; VIP access denied = loud buzzer; security = whistles,
  shouting, footsteps. Audio amplifies the comedy.

### Core visual rules
1. Readable from a distance: large shapes, clean silhouettes, simple colours.
2. Physical before UI: if it can reasonably exist in the 3D casino, prefer that over another menu.
3. Luxury vs stupidity: the casino takes itself seriously; the players absolutely do not.
4. Low-poly and achievable: no huge unique-asset counts, high-detail textures, complicated shaders or
   AAA production values.
5. Gameplay readability beats realism.
6. The casino itself should be memorable enough to become part of the game's identity.
