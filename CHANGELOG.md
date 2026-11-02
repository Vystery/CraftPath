# Changelog

## 0.3.0

First public release. Requires CraftProfit. Trainer data ships for Enchanting and Tailoring (plus early Alchemy,
recorded on the Horde side on the beta); every other profession fills in as you visit your trainer.

- **Records your trainers and recipe vendors itself** (no extra addon needed): open your profession trainer or a
  pattern vendor and the route uses those recipes right away, with skill, price and where to get them. Trainers
  show only the next recipes for your skill, so the route reaches further each time you visit at a higher skill.
  Shared by all your characters on the account; ProfessionRecorder's recordings are still used when installed.
- What you own counts as paid: cloth, dyes, thread and leftover bolts in your bags and bank lower the route's cost.
- Route: the cheapest way from your skill to a target skill (up to 300), using recipes you know and recipes you can
  learn, with rank trainings on the way and parts (Bolts of Linen Cloth) crafted first while they give points.
- Skill bar coloured like the recipe list, with recipe icons, step borders, rank caps and your progress.
- Shopping list: this step / next 25 points / whole route; have (bags + bank) and need per row; quantities with a
  safety margin; **Buy next** at the Auction House (buy page with the quantity filled in, you press Buy) and
  **Buy vendor mats** at a merchant.
- **Craft next** button and key binding (Key Bindings > AddOns > CraftPath): crafts the current step's recipe, makes
  its parts first, and says why when it cannot (missing materials, rank to train, recipe to learn).
- **Craft all**: the rest of the current step in one go, capped by what your bags cover.
- Parts first: the route plans a step's parts (Bolts of Linen Cloth) the way they are crafted, all before the bags,
  at their own colours; bolts you already own are not crafted again and make the route cheaper.
- **Pace**: Cheapest / Balanced (default) / Fastest, so the route stops picking many green crafts just because they
  sell to a vendor for more than their mats.
- Now line: what to do this minute. Notice when the route moves to the next recipe.
- Only mats in my bags: plan with what you carry.
- Enchanting: puts back an item from your bags you already enchanted after a recipe switch (never equipped items);
  optional "Skip replace popup" for enchants cast from the profession window.
- Works with any client language (data keyed by profession ID); other-faction trainer data shown as "your trainer".
- Now line also covers buying ("You need 3 more Linen Cloth: Shopping list > Buy next"), rank trainings you are
  too low level for, and tools (rods). Owned parts (leftover bolts) reduce the cloth to buy.
- Targets and progress saved per character. `/cpath debug` for bug reports, `/cpath report` for every price.
