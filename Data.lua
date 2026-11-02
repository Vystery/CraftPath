-- CraftPath :: Data
-- Where recipes are learned and which difficulty colours were seen at which skill, recorded on the Forever beta
-- with ProfessionRecorder (exports of 2026-10-15, build 1.60.1.70374, and 2026-10-17, build 70450) and the
-- CraftPathVerify probe (2026-10-23, last beta day: Snang matched the 10-17 list exactly; Whuut's Alchemy added).
-- Nothing here is copied from Classic.
-- Costs are the base price (Orgrimmar). The Undercity NPCs charged the recording character 10% less (1305 vs 1450
-- for the same slippers, 135 vs 150 for the same pattern), so their recorded prices are divided by 0.9 here.
--
--   sources[profession][recipeID] = { skill, cost in copper, npc key }
--     skill = the skill the trainer / pattern asks for (the recipe is orange from there)
--   npcs[key] = { name, place, kind }
--   seen[profession][recipeID] = { { colour, fromSkill, toSkill }, ... }
--     colour 0 orange, 1 yellow, 2 green, 3 gray (Enum.TradeskillRelativeDifficulty)
--
-- Trainers never list recipes the visiting character already learned, so the lists start where that character
-- was; learned recipes need no source. Add visits from low-skill characters to fill in the early recipes.

local _, CPa = ...
local Data = {}
CPa.Data = Data

-- faction: who can use the NPC. On the other faction a trainer recipe is still used (trainers of both factions
-- teach it at the same skill and price) but shown as "your trainer"; vendor recipes are left out.
Data.npcs = {
	godan   = { name = "Godan", place = "Orgrimmar, The Drag", kind = "trainer", faction = "Horde" },
	hgarth  = { name = "Hgarth", place = "Sun Rock Retreat, Stonetalon Mountains", kind = "trainer", faction = "Horde" },
	kithas  = { name = "Kithas", place = "Orgrimmar, The Drag", kind = "vendor", faction = "Horde" },
	josef   = { name = "Josef Gregorian", place = "Undercity, Magic Quarter", kind = "trainer", faction = "Horde" },
	rhiannon = { name = "Rhiannon Davis", place = "Undercity, Magic Quarter", kind = "trainer", faction = "Horde" },
	millie  = { name = "Millie Gregorian", place = "Undercity, Magic Quarter", kind = "vendor", faction = "Horde" },
	snang   = { name = "Snang", place = "Orgrimmar, The Drag", kind = "trainer", faction = "Horde" },
	magar   = { name = "Magar", place = "Orgrimmar, The Drag", kind = "trainer", faction = "Horde" },
	borya   = { name = "Borya", place = "Orgrimmar, The Drag", kind = "vendor", faction = "Horde" },
	whuut   = { name = "Whuut", place = "Orgrimmar", kind = "trainer", faction = "Horde" },
}

-- Profession line IDs -> the key Data is filed under (English, so every client language finds the data).
-- Base lines from GetAllProfessionTradeSkillLines on Forever; the Forever child line (2940 Enchanting) carries
-- its base line as parentProfessionID.
Data.PROF_KEYS = {
	[171] = "Alchemy", [164] = "Blacksmithing", [185] = "Cooking", [333] = "Enchanting", [202] = "Engineering",
	[129] = "First Aid", [356] = "Fishing", [182] = "Herbalism", [165] = "Leatherworking", [186] = "Mining",
	[393] = "Skinning", [197] = "Tailoring",
}
-- what has recorded trainer data (shown when a profession has none)
Data.COVERED = { Enchanting = true, Tailoring = true }

Data.sources = {
	Enchanting = {
		-- Godan (seen at Enchanting 140)
		[13501] = { 130, 1500, "godan" },  -- Enchant Bracer - Lesser Stamina
		[13485] = { 130, 1500, "godan" },  -- Enchant Shield - Lesser Spirit
		[13503] = { 140, 2000, "godan" },  -- Enchant Weapon - Lesser Striking
		[13538] = { 140, 2500, "godan" },  -- Enchant Chest - Lesser Absorption
		-- Hgarth (seen at Enchanting 145, Expert); Godan also teaches the 145-150 ones
		[13529] = { 145, 2400, "hgarth" }, -- Enchant 2H Weapon - Lesser Impact
		[13607] = { 145, 2400, "hgarth" }, -- Enchant Chest - Intellect
		[13622] = { 150, 2500, "hgarth" }, -- Enchant Bracer - Lesser Intellect
		[13626] = { 150, 2500, "hgarth" }, -- Enchant Chest - Minor Stats
		[13628] = { 150, 2500, "hgarth" }, -- Runed Golden Rod
		[13635] = { 155, 2600, "hgarth" }, -- Enchant Cloak - Defense
		[13631] = { 155, 2600, "hgarth" }, -- Enchant Shield - Lesser Stamina
		[14809] = { 155, 2600, "hgarth" }, -- Lesser Mystic Wand
		[13640] = { 160, 2700, "hgarth" }, -- Enchant Chest - Greater Stamina
		[13637] = { 160, 2800, "hgarth" }, -- Enchant Boots - Lesser Agility
		[13642] = { 165, 2800, "hgarth" }, -- Enchant Bracer - Spirit
		[13644] = { 170, 2800, "hgarth" }, -- Enchant Boots - Lesser Stamina
		[13648] = { 170, 2800, "hgarth" }, -- Enchant Bracer - Stamina
		[13657] = { 175, 3000, "hgarth" }, -- Enchant Cloak - Fire Resistance
		[14810] = { 175, 3000, "hgarth" }, -- Greater Mystic Wand (439134 is the Season of Discovery copy)
		[13659] = { 180, 3200, "hgarth" }, -- Enchant Shield - Spirit
		[13661] = { 180, 3600, "hgarth" }, -- Enchant Bracer - Strength
		[13663] = { 185, 3800, "hgarth" }, -- Enchant Chest - Greater Intellect
		[13693] = { 195, 4000, "hgarth" }, -- Enchant Weapon - Striking
		[13695] = { 200, 4000, "hgarth" }, -- Enchant 2H Weapon - Impact
		[13700] = { 200, 4000, "hgarth" }, -- Enchant Chest - Lesser Stats
		[13702] = { 200, 4000, "hgarth" }, -- Runed Truesilver Rod
		[13746] = { 205, 4200, "hgarth" }, -- Enchant Cloak - Greater Defense
		[13794] = { 205, 4200, "hgarth" }, -- Enchant Cloak - Resistance
		[13822] = { 210, 4400, "hgarth" }, -- Enchant Bracer - Intellect
		[13815] = { 210, 4400, "hgarth" }, -- Enchant Gloves - Agility
		[13836] = { 215, 4600, "hgarth" }, -- Enchant Boots - Stamina
		[13858] = { 220, 4800, "hgarth" }, -- Enchant Chest - Superior Stamina
		[13890] = { 225, 5000, "hgarth" }, -- Enchant Boots - Minor Speed
		[13887] = { 225, 5000, "hgarth" }, -- Enchant Gloves - Strength
		-- Kithas (formulas; "Requires Enchanting (n)" from the tooltip)
		[7443]  = { 20, 300, "kithas" },   -- Enchant Chest - Minor Intellect
		[25124] = { 5, 500, "kithas" },    -- Minor Wizard Oil
		[7793]  = { 100, 500, "kithas" },  -- Enchant 2H Weapon - Lesser Intellect
		[25125] = { 150, 3000, "kithas" }, -- Minor Mana Oil
		[25126] = { 200, 4000, "kithas" }, -- Lesser Wizard Oil
	},
	Tailoring = {
		-- Magar, Journeyman trainer (seen at Tailoring 50, export 2026-10-17); Snang (Apprentice) teaches the same
		-- recipes up to 55 at the same prices
		[2393]  = { 1, 25, "magar" },    -- White Linen Shirt
		[3755]  = { 5, 100, "snang" },   -- Linen Bag (only Snang listed it)
		[2385]  = { 10, 50, "magar" },   -- Brown Linen Vest
		[8776]  = { 15, 50, "magar" },   -- Linen Belt
		[12045] = { 20, 50, "magar" },   -- Simple Linen Boots
		[1229504] = { 20, 100, "magar" }, -- Faction Banner
		[2394]  = { 25, 50, "magar" },   -- Blue Linen Shirt
		[3914]  = { 25, 50, "magar" },   -- Brown Linen Pants
		[7623]  = { 25, 50, "magar" },   -- Brown Linen Robe
		[2392]  = { 25, 50, "magar" },   -- Red Linen Shirt
		[8465]  = { 25, 50, "magar" },   -- Simple Dress
		[7624]  = { 25, 50, "magar" },   -- White Linen Robe
		[3840]  = { 25, 100, "magar" },  -- Heavy Linen Gloves
		[3841]  = { 35, 200, "magar" },  -- Green Linen Bracers
		[2397]  = { 35, 200, "magar" },  -- Reinforced Linen Cape
		[1257368] = { 35, 500, "magar" }, -- Novice Arcanist's Sash
		[1257369] = { 35, 500, "magar" }, -- Novice Ardent's Sash
		[2396]  = { 40, 200, "magar" },  -- Green Linen Shirt
		[2386]  = { 40, 200, "magar" },  -- Linen Boots
		[2395]  = { 40, 300, "magar" },  -- Barbaric Linen Vest
		[3842]  = { 45, 300, "magar" },  -- Handstitched Linen Britches
		[3757]  = { 50, 200, "magar" },  -- Woolen Bag
		[12046] = { 50, 300, "magar" },  -- Simple Kilt
		[2964]  = { 55, 100, "magar" },  -- Bolt of Woolen Cloth
		[2402]  = { 55, 250, "magar" },  -- Woolen Cape
		[3845]  = { 55, 300, "magar" },  -- Soft-soled Linen Boots
		[2399]  = { 60, 300, "magar" },  -- Green Woolen Vest
		[3843]  = { 60, 400, "magar" },  -- Heavy Woolen Gloves
		[2401]  = { 70, 300, "magar" },  -- Woolen Boots
		[6521]  = { 70, 400, "magar" },  -- Pearl-clasped Cloak
		[2406]  = { 80, 200, "magar" },  -- Gray Woolen Shirt
		[3866]  = { 85, 250, "magar" },  -- Stylish Red Shirt
		[8467]  = { 85, 250, "magar" },  -- White Woolen Dress
		[3848]  = { 85, 500, "magar" },  -- Double-stitched Woolen Shoulders
		[3850]  = { 85, 500, "magar" },  -- Heavy Woolen Pants
		[3839]  = { 100, 500, "magar" }, -- Bolt of Silk Cloth
		[3855]  = { 100, 750, "magar" }, -- Spidersilk Boots
		[3852]  = { 105, 750, "magar" }, -- Gloves of Meditation
		[6690]  = { 110, 1000, "magar" }, -- Lesser Wizard's Robe
		[8758]  = { 115, 600, "magar" }, -- Azure Silk Pants
		[8760]  = { 120, 600, "magar" }, -- Azure Silk Hood
		[3859]  = { 125, 750, "magar" }, -- Azure Silk Vest
		[3813]  = { 125, 800, "magar" }, -- Small Silk Pack
		-- Forever's new slippers (Magar; Josef and Rhiannon Davis in Undercity too)
		[1257429] = { 150, 1450, "magar" }, -- Black Slippers
		[1257428] = { 150, 1450, "magar" }, -- Fiery Slippers
		[1257427] = { 150, 1450, "magar" }, -- Frothing Slippers
		[1257426] = { 150, 1450, "magar" }, -- Gilded Slippers
		[1257430] = { 150, 1450, "magar" }, -- Golden Slippers
		[1257431] = { 150, 1450, "magar" }, -- Radiant Slippers
		-- Josef Gregorian, Expert trainer (seen at Tailoring 150; recorded price / 0.9)
		[8483]  = { 125, 500, "josef" },   -- White Swashbuckler's Shirt
		[8762]  = { 125, 750, "josef" },   -- Silk Headband
		[3871]  = { 135, 500, "josef" },   -- Formal White Shirt
		[8764]  = { 135, 900, "josef" },   -- Earthen Vest
		[8489]  = { 140, 750, "josef" },   -- Red Swashbuckler's Shirt
		[8766]  = { 140, 1000, "josef" },  -- Azure Silk Belt
		[3865]  = { 140, 1000, "josef" },  -- Bolt of Mageweave
		[8772]  = { 140, 1000, "josef" },  -- Crimson Silk Belt
		[8774]  = { 145, 1000, "josef" },  -- Green Silken Shoulders
		[3861]  = { 150, 1000, "josef" },  -- Long Silken Cloak
		[8791]  = { 150, 2500, "josef" },  -- Crimson Silk Vest
		[8770]  = { 155, 1000, "josef" },  -- Robe of Power
		[8799]  = { 160, 3000, "josef" },  -- Crimson Silk Pantaloons
		[12049] = { 170, 4000, "josef" },  -- Black Mageweave Leggings
		[12048] = { 170, 4000, "josef" },  -- Black Mageweave Vest
		[12050] = { 175, 4000, "josef" },  -- Black Mageweave Robe
		[8804]  = { 175, 5000, "josef" },  -- Crimson Silk Gloves
		[12061] = { 180, 2500, "josef" },  -- Orange Mageweave Shirt
		[12053] = { 180, 5000, "josef" },  -- Black Mageweave Gloves
		[12069] = { 190, 5000, "josef" },  -- Cindercloth Robe
		[12067] = { 190, 5000, "josef" },  -- Dreamweave Gloves
		[12070] = { 190, 5000, "josef" },  -- Dreamweave Vest
		[12065] = { 190, 5000, "josef" },  -- Mageweave Bag
		-- Borya (patterns, Orgrimmar)
		[1257013] = { 5, 150, "borya" },  -- Linen Reagent Bag
		[7630]  = { 35, 200, "borya" },   -- Blue Linen Vest
		[1257017] = { 70, 250, "borya" }, -- Woolen Reagent Bag
		[7639]  = { 75, 400, "borya" },   -- Blue Overalls
		[6688]  = { 90, 500, "borya" },   -- Red Woolen Bag
		[12075] = { 190, 4000, "borya" }, -- Lavender Mageweave Shirt
		[12080] = { 195, 4000, "borya" }, -- Pink Mageweave Shirt
		-- Millie Gregorian (patterns, Undercity; recorded price / 0.9)
		[7643]  = { 90, 800, "millie" },   -- Greater Adept's Robe
		[12093] = { 140, 5000, "millie" }, -- Tuxedo Jacket
		[12089] = { 140, 4500, "millie" }, -- Tuxedo Pants
		[12085] = { 200, 4500, "millie" }, -- Tuxedo Shirt
		-- Kithas (the enchanting supplies vendor sells this one)
		[27658] = { 190, 6000, "kithas" }, -- Enchanted Mageweave Pouch
	},
	Alchemy = {
		-- Whuut (seen at Alchemy 15, 2026-10-23, CraftPathVerify): a visit lists only the next recipes, so this is
		-- 20-50; the rest fills in from players' own trainer visits
		[1230564] = { 20, 100, "whuut" }, -- Mana Well
		[2331]    = { 25, 100, "whuut" }, -- Minor Mana Potion
		[1249630] = { 40, 150, "whuut" }, -- Cerulean Dye
		[2332]    = { 40, 150, "whuut" }, -- Minor Rejuvenation Potion
		[1249633] = { 40, 150, "whuut" }, -- Sulfuric Acid
		[2334]    = { 50, 250, "whuut" }, -- Elixir of Minor Fortitude
	},
}

Data.seen = {
	-- exports of 2026-10-15 14:00 (v0.1) and 19:32 (v0.2), Enchanting 105-204, base and child line merged
	Enchanting = {
		[7418]  = { { 3, 105, 204 } },
		[7420]  = { { 2, 105, 109 }, { 3, 110, 204 } },
		[7421]  = { { 3, 105, 204 } },
		[7426]  = { { 1, 105, 109 }, { 2, 110, 129 }, { 3, 130, 204 } },
		[7428]  = { { 2, 105, 119 }, { 3, 120, 204 } },
		[7443]  = { { 3, 140, 204 } },
		[7454]  = { { 1, 105, 114 }, { 2, 115, 134 }, { 3, 135, 204 } },
		[7457]  = { { 1, 105, 119 }, { 2, 120, 139 }, { 3, 140, 204 } },
		[7745]  = { { 0, 105, 129 }, { 1, 130, 149 }, { 2, 150, 169 }, { 3, 170, 204 } },
		[7748]  = { { 1, 105, 124 }, { 2, 125, 144 }, { 3, 145, 204 } },
		[7771]  = { { 0, 105, 109 }, { 1, 110, 129 }, { 2, 130, 149 }, { 3, 150, 204 } },
		[7779]  = { { 0, 105, 114 }, { 1, 115, 134 }, { 2, 135, 154 }, { 3, 155, 204 } },
		[7782]  = { { 0, 105, 114 }, { 1, 115, 134 }, { 2, 135, 154 }, { 3, 155, 204 } },
		[7788]  = { { 0, 105, 119 }, { 1, 120, 139 }, { 2, 140, 159 }, { 3, 160, 204 } },
		[7793]  = { { 1, 140, 149 }, { 2, 150, 169 }, { 3, 170, 204 } },
		[7795]  = { { 0, 105, 129 }, { 1, 130, 149 }, { 2, 150, 169 }, { 3, 170, 204 } },
		[7857]  = { { 0, 125, 144 }, { 1, 145, 164 }, { 2, 165, 184 }, { 3, 185, 204 } },
		[7861]  = { { 0, 125, 149 }, { 1, 150, 169 }, { 2, 170, 189 }, { 3, 190, 204 } },
		[7863]  = { { 0, 125, 149 }, { 1, 150, 169 }, { 2, 170, 189 }, { 3, 190, 204 } },
		[13378] = { { 0, 105, 129 }, { 1, 130, 149 }, { 2, 150, 169 }, { 3, 170, 204 } },
		[13421] = { { 0, 125, 139 }, { 1, 140, 159 }, { 2, 160, 179 }, { 3, 180, 204 } },
		[13485] = { { 0, 140, 154 }, { 1, 155, 174 }, { 2, 175, 194 }, { 3, 195, 204 } },
		[13501] = { { 0, 140, 154 }, { 1, 155, 174 }, { 2, 175, 194 }, { 3, 195, 204 } },
		[13503] = { { 0, 140, 164 }, { 1, 165, 184 }, { 2, 185, 204 } },
		[13529] = { { 0, 145, 169 }, { 1, 170, 189 }, { 2, 190, 204 } },
		[13538] = { { 0, 140, 164 }, { 1, 165, 184 }, { 2, 185, 204 } },
		[13607] = { { 0, 145, 169 }, { 1, 170, 189 }, { 2, 190, 204 } },
		[13622] = { { 0, 154, 174 }, { 1, 175, 194 }, { 2, 195, 204 } },
		[13626] = { { 0, 154, 174 }, { 1, 175, 194 }, { 2, 195, 204 } },
		[13628] = { { 0, 154, 174 }, { 1, 175, 194 }, { 2, 195, 204 } },
		[13631] = { { 0, 166, 174 }, { 1, 175, 194 }, { 2, 195, 204 } },
		[13635] = { { 0, 166, 174 }, { 1, 175, 194 }, { 2, 195, 204 } },
		[13637] = { { 0, 166, 179 }, { 1, 180, 199 }, { 2, 200, 204 } },
		[13640] = { { 0, 166, 179 }, { 1, 180, 199 }, { 2, 200, 204 } },
		[13642] = { { 0, 166, 184 }, { 1, 185, 204 } },
		[13644] = { { 0, 185, 189 }, { 1, 190, 204 } },
		[13648] = { { 0, 185, 189 }, { 1, 190, 204 } },
		[13657] = { { 0, 185, 194 }, { 1, 195, 204 } },
		[13659] = { { 0, 185, 199 }, { 1, 200, 204 } },
		[13661] = { { 0, 185, 199 }, { 1, 200, 204 } },
		[13663] = { { 0, 185, 204 } },
		[13693] = { { 0, 203, 204 } },
		[13695] = { { 0, 203, 204 } },
		[13700] = { { 0, 203, 204 } },
		[13702] = { { 0, 203, 204 } },
		[14293] = { { 2, 105, 114 }, { 3, 115, 204 } },
		[14807] = { { 0, 105, 109 }, { 1, 110, 129 }, { 2, 130, 149 }, { 3, 150, 204 } },
		[14809] = { { 0, 166, 174 }, { 1, 175, 194 }, { 2, 195, 204 } },
		[14810] = { { 0, 185, 194 }, { 1, 195, 204 } },
		[25124] = { { 3, 105, 204 } },
		-- Forever's own recipe: the one exception to the 20-point spacing (green 142, gray 145)
		[1263056] = { { 1, 140, 141 }, { 2, 142, 144 }, { 3, 145, 204 } },
	},
	Tailoring = {
		-- export of 2026-10-17 13:55 (Tailoring 1-50): low recipes do NOT keep the 20-point spacing
		-- export of 2026-10-17 14:51 (Tailoring 50-100): full colour ranges
		[2385]   = { { 1, 50, 56 }, { 2, 57, 69 }, { 3, 70, 150 } },
		[2386]   = { { 0, 50, 64 }, { 1, 65, 81 }, { 2, 82, 99 }, { 3, 100, 150 } },
		[2392]   = { { 1, 50, 66 }, { 2, 67, 84 }, { 3, 85, 150 } },
		[2394]   = { { 1, 50, 66 }, { 2, 67, 84 }, { 3, 85, 150 } },
		[2395]   = { { 0, 50, 64 }, { 1, 65, 81 }, { 2, 82, 99 }, { 3, 100, 150 } },
		[2396]   = { { 0, 50, 64 }, { 1, 65, 81 }, { 2, 82, 99 }, { 3, 100, 150 } },
		[2397]   = { { 0, 50, 59 }, { 1, 60, 76 }, { 2, 77, 94 }, { 3, 95, 150 } },
		[2402]   = { { 0, 55, 79 }, { 1, 80, 96 }, { 2, 97, 100 } },
		[2406]   = { { 1, 98, 99 }, { 2, 100, 100 } },
		[3840]   = { { 1, 50, 66 }, { 2, 67, 84 }, { 3, 85, 150 } },
		[3841]   = { { 0, 50, 59 }, { 1, 60, 76 }, { 2, 77, 94 }, { 3, 95, 150 } },
		[3842]   = { { 0, 50, 69 }, { 1, 70, 86 }, { 2, 87, 100 } },
		[3914]   = { { 1, 50, 66 }, { 2, 67, 84 }, { 3, 85, 150 } },
		[7623]   = { { 1, 50, 66 }, { 2, 67, 84 }, { 3, 85, 150 } },
		[7624]   = { { 1, 50, 66 }, { 2, 67, 84 }, { 3, 85, 150 } },
		[8465]   = { { 1, 50, 66 }, { 2, 67, 84 }, { 3, 85, 150 } },
		[8776]   = { { 1, 50, 66 }, { 2, 67, 84 }, { 3, 85, 150 } },
		[12045]  = { { 1, 50, 66 }, { 2, 67, 84 }, { 3, 85, 150 } },
		[12046]  = { { 0, 50, 74 }, { 1, 75, 91 }, { 2, 92, 100 } },
		[2387]   = { { 0, 1, 34 }, { 1, 35, 46 }, { 2, 47, 59 }, { 3, 60, 150 } }, -- Linen Cloak
		[2963]  = { { 0, 1, 24 }, { 1, 25, 36 }, { 2, 37, 49 }, { 3, 50, 150 } }, -- Bolt of Linen Cloth
		[2964]   = { { 0, 55, 69 }, { 1, 70, 76 }, { 2, 77, 84 }, { 3, 85, 150 } }, -- Bolt of Woolen Cloth (seen in game 2026-10-17)
		[3755]   = { { 0, 1, 29 }, { 1, 30, 46 }, { 2, 47, 64 }, { 3, 65, 150 } }, -- Linen Bag
		[3915]   = { { 0, 1, 34 }, { 1, 35, 46 }, { 2, 47, 59 }, { 3, 60, 150 } }, -- Brown Linen Shirt
		[12044]  = { { 0, 1, 39 }, { 1, 40, 49 }, { 2, 50, 59 }, { 3, 60, 150 } }, -- Simple Linen Pants
		[3813]  = { { 1, 150, 150 } },
		[3849]  = { { 2, 150, 150 } },
		[3851]  = { { 2, 150, 150 } },
		[3852]  = { { 2, 150, 150 } },
		[3855]  = { { 2, 150, 150 } },
		[3859]  = { { 1, 150, 150 } },
		[3868]  = { { 2, 150, 150 } },
		[6690]  = { { 2, 150, 150 } },
		[8758]  = { { 2, 150, 150 } },
		[12089] = { { 0, 150, 150 } },
		[12093] = { { 0, 150, 150 } },
	},
}

-- Rods are tools: an enchant that lists one does not use it up.
Data.tools = {
	[6218] = true,  -- Runed Copper Rod
	[6339] = true,  -- Runed Silver Rod
	[11130] = true, -- Runed Golden Rod
	[11145] = true, -- Runed Truesilver Rod
	[16207] = true, -- Runed Arcanite Rod
}

-- Every Classic recipe in the recording has its colour changes exactly 20 skill apart (yellow -> green -> gray),
-- e.g. Minor Impact 130 / 150 / 170, Bracer - Lesser Intellect 175 / 195 / 215; maxTrivialLevel equalled the
-- recorded gray on all ~25 recipes that turned gray (export 2026-10-15 19:32). Exception: Arcane Salvager.
Data.STEP = 20
-- Per profession: yellow starts 2 * step under gray when not recorded (green halfway between). Tailoring gear goes
-- yellow 35 under gray (export 2026-10-17: Linen Boots 65/82/100, Reinforced Linen Cape 60/77/95, Simple Kilt
-- 75/92/110, Woolen Cape 80/97/115, Handstitched Linen Britches 70/87/105, Linen Bag 30/47/65).
Data.STEPS = { Tailoring = 17.5 }
-- Gray when the client gives no maxTrivialLevel: this far above the learn skill (rough; marked as a guess).
Data.FALLBACK_SPAN = 75

-- Ranks: the skill cap rises only by training the next rank. `at` = skill the trainer asks for, `level` = character
-- level, `cap` = the new maximum. Journeyman (50, level 10, 5s) and Expert Tailoring (125, level 20, 50s) are
-- recorded; the rest follow the trainer's usual steps and get their price from a recorded trainer visit (Recorder.lua or ProfessionRecorder) when there is one.
Data.MAX_SKILL = 300
Data.RANKS = {
	{ name = "Journeyman", at = 50, level = 10, from = 75, cap = 150 },
	{ name = "Expert", at = 125, level = 20, from = 150, cap = 225 },
	{ name = "Artisan", at = 200, level = 35, from = 225, cap = 300 },
}
Data.rankSources = {
	Tailoring = { Journeyman = { 500, "magar" }, Expert = { 5000, "josef" } },
	Enchanting = { Expert = { nil, "hgarth" } },
}

-- Every craft costs this much on top of its mats (copper; stands for the time it takes). A craft that sells for
-- more than its mats would otherwise make the route prefer MORE crafts (low chances) to collect the profit.
Data.CRAFT_TIME = 10
-- Pace: what one craft of your time is worth in copper when the route weighs gold against crafts.
--   cheapest: gold only (a profitable craft is nearly free, so 14 green crafts can beat 5 orange ones)
--   balanced: a craft is worth 50c (an orange recipe beats a green one that is only a little cheaper)
--   fastest:  fewest crafts (orange and yellow first, gold matters little)
Data.PACE = { cheapest = 10, balanced = 50, fastest = 300 }
