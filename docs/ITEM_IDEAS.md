# Item ideas from Patrick (2026-10-05)

Status: **noted, not implemented.** Patrick: "Just note these and rework if unbalanced. Don't
implement yet, implement with the other fixes later." They get built together with the playtest
fixes after M5. Each idea has a proposed balanced version below; numbers are first guesses for
tuning in `BalanceConfig`/item `params`. Money never depends on physics (§ master prompt), so physical
effects only stun, drop chips or move players.

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

## Jail (Patrick, 2026-10-05, idea only)
Getting caught by security (guards, a failed Fake Cash, a botched Greedy Pickpocket) sends you to
a **jail cell** instead of straight back to the entrance: a timeout that grows each time you're
caught this match. Proposed: 8 s, then 15 s, then 25 s (cap), shown as a countdown over the cell;
your table bets stay in and settle normally, items can't be used inside. New item **Get Out of
Jail Free** (rare): leave jail at once *and* reset your caught counter to zero; can be used
pre-emptively only to reset the counter. Replaces the current "thrown out + respawn" for offences;
knockouts and falls keep the plain respawn.

## Order to build (proposal)
1. Cheap, data-only on existing systems: Sunglasses, Bad Luck Monkey (without hot potato first),
   Early VIP Pass, Scratch Ticket, Energy Drink.
2. New small mechanics: Baseball Bat + Empty Bottle (melee item hit), Credit Card (delayed
   repayment), Dog Collar (win split), Fake Cash, Scissors, Greedy Pickpocket.
3. Bigger features: Jail + Get Out of Jail Free, Shop, Beer (screen effects + hidden money), Rock Paper Scissors (consent UI),
   Russian Roulette, Game Disabler.
