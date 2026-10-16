# Item ideas from Patrick (2026-10-05)

Status: **built in 0.5.1** (Patrick, 2026-10-05: "implement the new items"; jail stays a todo).
All 15 items and the Gift Shop follow the "Proposed version" column below, with the changes listed
under "As built". Money never depends on physics (§ master prompt), so physical effects only stun,
drop chips or move players.

| # | Idea (Patrick's words, short) | Proposed version | Notes |
|---|---|---|---|
| 1 | **Beer**: better luck, blurry screen, auto-move, inverted controls, money hidden, reveal later; then an empty bottle to hit someone (15 s stun) | Luck +1 for 40 s. Screen wobble + light blur, slight drift (not full auto-move), inverted look only (not movement). HUD money shows "$???" and the round results reveal after the effect ends. Leaves an **Empty Bottle** item: a melee hit that stuns **4 s** and drops chips like a knockout | 15 s stun is a quarter of a casino segment and unfun; full inverted movement makes players walk into guards. Hidden money must still be correct on the server. |
| 2 | **Baseball Bat**: hit = knockout + chips drop around | One swing, close range: instant knockout (same as 3 shoves), drops the usual knockout chips. Bodyguard blocks it | Same payout as existing knockout so it can't print money. |
| 3 | **Scratch Ticket**: random item or money | 60% random common item, 25% rare item, 10% $50–200 (×limits), 5% $500 (×limits) | Cash paid by the house; ~101% target means expected value small. |
| 4 | **Shop**: everyone may buy one item per round | A shop counter during REWARDS (or a kiosk in the casino): one purchase per segment, prices ~ $150 common / $400 rare / $900 legendary × limits | Prices tie items to money, so they must stay above the item's expected gain. Not an item itself; a feature. |
| 5 | **White powder** (not cocaine; call it **Energy Drink** / "Espresso Shot"): speed buff, skip dealer wait at tables where you sit alone | +40% walk speed for 30 s; at a table where you are the only player, betting windows and dealer pauses are halved | Name kept harmless for the store page. |
| 6 | **Credit Card**: get money now, pay back with interest | Borrow $300 × limits now; after 90 s the bank takes back $360 × limits (or everything you have if less, never negative) | Balance can't go below 0 (economy rule), so the debt is capped by what you hold. |
| 7 | **Rock Paper Scissors wager** on someone, winner gets the amount set by the user | Target must accept within 5 s or it's cancelled; stake picked by the user, max 15% of the poorer player's money; both choose in 5 s, ties replay once then refund | A forced wager on someone else's money is griefing, so it needs consent or a cap. |
| 8 | **Early VIP Pass**: one-time VIP entrance for 3 min | VIP access for 120 s regardless of money; you're thrown out (gently) when it ends | 3 min is most of a segment at 5-minute matches. |
| 9 | **Sunglasses**: see the dealer's next hand at blackjack (single use) | Already exists as Hot Hands' `peek_dealer`; Sunglasses = peek the hole card for **one** round, rare | Seeing the *next* hand isn't possible with per-round shuffling; the hole card is the same idea. |
| 10 | **Fake Cash**: use on your next bet, 50/50 the bouncer catches you | Next bet up to $200 × limits is free. 50% caught: the bet is void, you lose the same amount as a fine and a guard throws you out | Expected value ~0 with a fun chaos moment. |
| 11 | **Game Disabler**: disable certain games for the round | "Out of Order" sign: one station closes for 30 s (open bets settle normally first) | Disabling a whole game type for a segment would lock out everyone; keep it local and short. |
| 12 | **Bad Luck Monkey**: give to someone, drastic debuff | Luck −3 for 25 s on a target, legendary. Passes to whoever the target shoves first (hot potato) | Black Cat is −2 for 45 s; the monkey is stronger but shorter and can be passed on. |
| 13 | **Scissors**: cut away one card at blackjack | Remove your last drawn card once per hand (before standing), rare | Big edge; limit to once per hand and not after doubling. |
| 14 | **Dog collar** (Hundehalsband): 20% of the "dog's" wins go to you for one round | Target's winnings for 30 s: 15% goes to you (from their win, not the house), Bodyguard/Mirror apply | Transfers only, so it can't create money. |
| 15 | **Pickpocket**: steal money, bouncer doesn't notice, bigger amount = worse odds | Current Pickpocket stays (12%, $50–$500). Add a **Greedy** choice: pick 10/20/30% with 90/65/40% success; a failure costs you the same amount to the victim | Patrick's twist on the existing item. |
| 16 | **Russian Roulette**: multi-use, 1 in 6; each use +20%, lose and you drop to 20% of your money | Each pull: +20% of current money (paid by the house); chance of losing starts at 1/6 and rises by 1/6 per pull; losing leaves you 20% of your money (the rest goes to the jackpot, not deleted) | Expected value per pull is negative from the second pull on; money "lost" feeds the jackpot so the ledger balances. |

## Jail (Patrick, 2026-10-05): TODO only, not part of the item build (docs/TODO.md "Later")
Getting caught by security (guards, a failed Fake Cash, a botched Greedy Pickpocket) sends you to
a **jail cell** instead of straight back to the entrance: a timeout that grows each time you're
caught this match. Proposed: 8 s, then 15 s, then 25 s (cap), shown as a countdown over the cell;
your table bets stay in and settle normally, items can't be used inside. New item **Get Out of
Jail Free** (rare): leave jail at once *and* reset your caught counter to zero; can be used
pre-emptively only to reset the counter. Replaces the current "thrown out + respawn" for offences;
knockouts and falls keep the plain respawn.

## As built (0.5.1)
- **Controls:** Pickpocket and Rock Paper Scissors open the target picker; **R** cycles the greed
  tier / the stake (5, 10 or 15% of the poorer player's money, minimum $10). A challenged player
  answers with **Y / N** (6 s, silence declines), then both pick with **1 / 2 / 3** (6 s, no pick =
  random). One tie replays, a second tie calls it off. Bots accept 70% of challenges.
- **Out of Order:** hangs on the nearest table or machine within 4 m for 30 s; nobody can sit or
  bet there, rounds already running finish. A red sign and the prompt show the countdown.
- **Gift Shop:** a kiosk on the east wall next to the bar, open in the casino. Four offers per
  segment (two common, one rare, one rare or legendary), the same for everyone, $150 / $400 / $900
  × table limits; one buy per player per segment. Restocks when each casino segment starts.
- **Scissors** is a CUT button [C] at blackjack; **Beer** wobbles the camera only (movement stays
  normal) and leaves an Empty Bottle (4 s stun, never in drafts or the shop).

## Order to build (proposal, done)
1. Cheap, data-only on existing systems: Sunglasses, Bad Luck Monkey (without hot potato first),
   Early VIP Pass, Scratch Ticket, Energy Drink.
2. New small mechanics: Baseball Bat + Empty Bottle (melee item hit), Credit Card (delayed
   repayment), Dog Collar (win split), Fake Cash, Scissors, Greedy Pickpocket.
3. Bigger features: Shop, Beer (screen effects + hidden money), Rock Paper Scissors (consent UI),
   Russian Roulette, Game Disabler.

## 0.8.19: held items, forced duels, tip jar and the last six items (Patrick, 2026-10-10)
- **Hold it in your hand:** the wheel or 1/2/3 put a slot's item in the bean's hand (its 3D model,
  `ItemModels`; first person shows it at the bottom right of the view). Picking a slot flashes the
  name and the first sentence of the description over the bar for 2 s; **I** still opens the full
  card. **Left click / E** uses it (pressing the held slot's key again does too), **right click**
  puts it away. Items aimed at a player hit whoever you look at: the nearest other player inside a
  30° cone (half-angle) and the item's reach (15 m for items without a range); a gold ring and an
  outline mark them, "No one in reach" otherwise. No target picker, no cycling, no timer.
  Seated: Shift+1/2/3 picks, the same key again uses. Gamepad: d-pad picks, shoulder buttons switch
  while holding, **X** (interact) uses, **B** puts away (A stays jump).
- **Choices before the use:** Pickpocket (SAFE 12% / GREEDY 20% at 65%) and Rock Paper Scissors
  (LOW 5% / HIGH 15% stake) ask with two buttons on the item bar: left click or E for the first,
  right click or R for the second. The very greedy 30% tier and the 10% stake are no longer offered
  from the client (the server still accepts them).
- **Rock Paper Scissors is forced:** no accept step; both players are pulled straight into a duel
  screen (stake, countdown, ROCK/PAPER/SCISSORS buttons or keys 1–3, result). 8 s to pick, no pick
  = random, one tie replays.
- **Sunglasses** did work on the server when used before sitting down (the effect waits for the
  next blackjack hand), but the client only wrote the peeked card into a hidden label. The hole card
  now shows through its back in a green x-ray look for the wearer.
- **Tip jar:** removed again (Patrick, 2026-10-16): no TIP button, no `tip_dealer` intent.
- **Bouncer** (rare): aim at a seated player; they are stood up at once (open bets handled as if
  they left) and can't sit anywhere for 12 s. Simplest reading: no NPC walk-up, a 1 s knockdown.
- **Robin Hood** (legendary): 8% of the richest other player's money (max $800) split equally among
  everyone else, you included; refused when you lead. Leftover dollars stay with the leader.
- **Jackpot Magnet** (legendary): for 30 s every other player's win pays you 10% of their profit,
  paid by the house.
- **Wild Card** (common): turns into a random item (60/30/10 common/rare/legendary, never itself).
- **Butter Fingers** (`grease`, common, 6 m): for 20 s the target drops anyone they grab, and the
  next time they're shaken for chips the same amount spills again.
- **Bribe the Guard** (rare): for 30 s your knockouts, throws and shakes never reach security.
