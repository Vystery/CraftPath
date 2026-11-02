# CraftPath

**The cheapest way to level a profession on WoW Forever.** Pick a target skill: CraftPath plans the cheapest recipes
to get there (including recipes you have not learned yet), prices them from your Auction House scan, tells you what
to buy, and crafts the right recipe for you at every skill.

**Requires CraftProfit** (free). Trainer data ships for **Enchanting and Tailoring** (plus early Alchemy, recorded
on the Horde side); every other profession fills in by itself: CraftPath records the trainers and recipe vendors you
visit, for all your characters.

## What you get

- **A route from your skill to the target**, cheapest first: which recipe at which skill, how many crafts, what it
  costs, where to learn it, and the rank trainings (Journeyman, Expert, Artisan) on the way.
- **A skill bar** coloured like the recipe list (orange: every craft gives a point; yellow: most do; green: fewer
  than half), with a recipe icon per step and your progress since you set the target.
- **A Shopping list you can act on**: this step / the next 25 points / the whole route, what you already have (bags +
  bank), what you still need, where to get it. At the Auction House **Buy next** opens the next item with the
  quantity filled in (you press Buy); at a merchant **Buy vendor mats** buys what that merchant sells.
- **Craft all** next to it crafts the rest of the current step in one go (as far as your bags cover it).
- **Craft next**: one button (or one key) crafts the current step's recipe, makes the parts it needs first (Bolts
  of Linen Cloth before Linen Bags), and says plainly why when it cannot ("you need 3 more Linen Cloth", "Train
  Expert Tailoring first").
- **A Now line** that always says what to do this minute, and a notice when the route moves to the next recipe.
- **Only mats in my bags**: level with what you carry; only training costs gold.
- **Pace**: Cheapest (gold only), Balanced (default: a craft is worth 50c of your time, so orange and yellow recipes
  beat green ones that are only a little cheaper) or Fastest (fewest crafts).

Free addon, no paid parts.

## Get started

1. Install **CraftProfit** (required, free, on CurseForge) and scan the Auction House with it once.
2. Open your profession window and click the **book button** at the top (or type `/cpath`).
3. Type a target skill. Follow the route: press **Craft next**, buy from the **Shopping list** tab.
4. Visit your profession trainer (and recipe vendors) now and then: CraftPath records the recipes they teach, and the
   route can use them from then on.

Tip: bind **Craft next** to a key in Key Bindings > AddOns > CraftPath (or a macro: `/click CraftPathCraftButton`).

## Requirements

- WoW Forever (Interface 16001).
- **CraftProfit** (required): AH scan and prices.
- **ProfessionRecorder** (optional): no longer needed (CraftPath records trainers and vendors itself); its
  recordings are still read when it is installed.

## Known limits

- **Trainer data**: recorded for **Enchanting and Tailoring** (and Alchemy 20-50) on the beta, **Horde** side. Alliance players get the
  same trainer recipes (same skill, same price) shown as "your trainer"; vendor-only recipes of the other faction are
  left out. Other professions use the recipes you already know until you open your trainer. A trainer lists only
  the next recipes for your skill (about 50 points ahead) and never the ones you know, so open it again as you
  level and the route goes further.
- Prices are the lowest AH listing per unit (not the 60th unit), from your last CraftProfit scan; the window tells
  you when they are more than a day old.
- Crafts are expected values: luck moves them. Shopping quantities carry a margin (about 80% chance to be enough).
- Tools and workstations (anvil, forge, campfire) are not planned for; Craft next tells you when one is missing.
- Tested on the English client; the data is keyed by profession ID, so other languages find it too. Vendor patterns
  are read with the client's own "Requires %s (%d)" text, so they work in any language.
- **Some data missing** (amber, right of the checkboxes) appears when the route had to do without data; hover it for
  what is missing and how to fill it in.

## Commands

`/cpath` (window), `/cpath target 200`, `/cpath pace cheapest|balanced|fastest`, `/cpath outputs vendor|ah|none` (what the items you make count as),
`/cpath report` (every candidate recipe and price, to copy), `/cpath forget` (forget remembered enchant targets),
`/cpath debug` (versions and data coverage for bug reports).

**Enchanting**: after a recipe switch Blizzard empties the target slot. Craft next puts back an item from your bags
that you already enchanted when the new enchant fits it; it never picks equipped items or items you have not
enchanted. **Skip replace popup** (checkbox, Enchanting only) answers "Do you want to replace this enchant?" with yes
for enchants cast from the profession window in the last few seconds.

Targets and progress are saved per character.

## How the route is worked out

Skill-up chance of a craft at skill `s`: 1 below yellow, `(gray - s) / (gray - yellow)` from yellow to gray,
0 at gray. This fits the crafts recorded on the beta (20 points in 20 orange crafts of Enchant Chest - Stamina;
9 points in 10 yellow crafts of Minor Agility at 115-123, predicted 8.9).

Where the colours change, per recipe, best source first:

1. colours seen on the beta: `Data.lua` (ProfessionRecorder exports of 2026-10-15 and 2026-10-17), ProfessionRecorder's own
   data if it is installed, and the colour the profession window shows right now for learned recipes;
2. gray: the client's `maxTrivialLevel`;
3. yellow and green: 40 and 20 under gray. Every recipe in the recording with two colour changes has them
   exactly 20 points apart. Estimated values are marked `*`.

Reagents are priced by CraftPath itself: the cheaper of buying (CraftProfit's AH or vendor price) and crafting
with any recipe of the profession you know **or can train by the skill the step happens at** (Bolt of Woolen Cloth
from 55 on, Bolt of Mageweave from 140), up to three levels deep. A recipe's price is worked out per skill band
(the bands start where a reagent's recipe becomes trainable), and steps split where it changes. An intermediate recipe that needs training is kept only when what it saves over
the whole route beats its training price; its training is then added to the route total and the training bill.
The Shopping list shows crafted reagents as "craft" rows and lists the mats they are made of. When a craft cannot
be priced because one of its own mats has no price (Bolt of Mageweave without a Mageweave Cloth price), the
reagent is bought and the **Some data missing** marker lists it.

**Sources** are Data.lua plus every trainer and recipe vendor visited on the account: CraftPath's own recorder
(`Recorder.lua`, saved in `CraftPathDB.recorded`, 40 trainers and 40 vendors at most) and ProfessionRecorder's when it
is installed. Trainer lists show only what the visiting character lacks and only part of the way ahead (verified on
the last beta day: no Tailoring at Snang = recipes 1-55; Alchemy 15 at Whuut = 20-50), so visits are merged per
recipe and the lists grow as you level. The list is read at `TRAINER_UPDATE` (it is empty when the window opens);
the service tooltip's ID is the recipe ID. Patterns are matched to recipes by name ("Pattern: X" -> X).
Learn skills are never estimated from the gray level: gray minus learn skill varies (Alchemy 5 to 80).
**Ranks**: the target goes up to 300; Journeyman (skill 50, level 10), Expert (125, 20) and Artisan (200, 35) appear
as "Train:" rows where the old cap (75 / 150 / 225) would stop you, with the price from a recorded visit ("price ?"
until then), and a gold tick on the bar.
**Parts first**: a step's own reagents (3 Bolts of Linen Cloth per Linen Bag) are planned the way Craft next and Craft
all make them: all the bolts first, at their own colours (orange, yellow, green), then the bags. So the route usually
opens with a Bolt of Linen Cloth step (1-48, "make ~54 extra for Linen Bag") and the bags follow ("needs ~54 Bolt of
Linen Cloth (made at 1-48)"). **What you own counts as paid** (bags + bank, raw mats and parts alike: silk cloth,
wool cloth, dyes, thread, leftover bolts): each plan is priced step by step with your stock used first, and bolts made
by an earlier step count as stock for the later ones, so every row shows what that step still costs you. The route is
solved once with everything priced as usual and once with the mats you own priced at 0 for the crafts that use them,
and the plan that really costs less is kept. Recipes already in your route get a 3% preference, so a few silver (a
recipe you just bought, a price that moved) do not reshuffle the whole plan. Parts a step still makes itself get their own part of the skill bar, walked in craft
order minus the ones you own, so the bar is used up from the left. **Craft reagents** (checkbox, on): unticked,
reagents are bought wherever their crafts give no skill-up (faster, more gold; "buys ~252 ..." in the step line,
bought rows in the Shopping list); reagents that still give points are crafted either way. Steps are split at rank caps, so a "Train:" row
sits between 35-75 and 75-93. **Profitable crafts** (vendor price above the mats) never make the route
take more crafts: the route decides by cost floored at 0 plus 10c of time per craft, and shows profit as "+44s".

**Reagents for later, crafted early**: when a later step crafts a reagent anyway (348 Bolts of Woolen Cloth for
the Red Woolen Bags at 105+, long gray by then), crafting them earlier as their own step, while they still give
points, costs only time: the cloth is paid by the later step. The route gets that credit for up to the number the
later steps need (solved again until it settles), shows "make ~N extra for Red Woolen Bag" on the early step and "needs ~N
Bolt of Woolen Cloth (made at 55-96)" on the later one, and the Shopping list counts the cloth once.

The route is a shortest path over skill levels: an edge "recipe r from skill a to b" costs r's training once plus
the expected crafts times the cost per craft (reagents minus what the made item is worth; rods are tools and
cost nothing). Recipes count when they are learned or have a recorded trainer / vendor (`Data.lua`); a recipe
being in the client's list does not mean it can be learned (Season of Discovery leftovers are listed too).

**Shopping quantities** add 0.84 standard deviations of the scope's crafts to the expected crafts (each craft's
wait for a point is geometric: variance (1-p)/p^2), so the list is enough about 80% of the time. The plan is rebuilt
when your skill, cap, target, settings, prices or learned recipes change, also while only the profession window is
open, so Craft next never works from an old plan.

Limits: reagent prices are the price of one unit, not the 60th; a level that no known recipe can raise ends the
route there ("No known recipe gives a point at 187"); trainer lists start where the recording character was,
so early recipes the recorder never saw unlearned are missing until someone records them.

## Help, bugs and ideas

Join the **Vystery Addons** Discord: https://discord.gg/hbJXz7qqpJ
Bugs in #bug-reports (please add the output of `/cpath debug`), questions in #addon-help.

## License

All rights reserved, see [LICENSE](LICENSE). Made by Vystery.
