-- CraftPath :: Model
-- Builds the solver's input from the open profession window and prices it with CraftProfit:
--   * usable recipes: learned ones, plus unlearned ones with a recorded trainer / vendor source (Data.lua)
--   * thresholds: colours recorded in Data.lua and by ProfessionRecorder, the colour the window shows now for
--     learned recipes, and the client's maxTrivialLevel as the gray threshold
--   * cost per craft: reagents minus what the made item is worth (setting "outputs"); rods are tools and cost
--     nothing per craft
--   * reagent price: the cheaper of buying it (CraftProfit's price: AH or vendor) and crafting it with any recipe of
--     this profession you know or can train at your skill now (Bolt of Mageweave from cloth), up to three levels
--     deep. An intermediate that needs training is kept only when what it saves over the whole route beats its
--     training price; its training is then added to the route.
-- The plan is rebuilt when the window updates or a skill-up arrives, and kept while the window is closed.

local _, CPa = ...
local Model = {}
CPa.Model = Model

local function T() return C_TradeSkillUI end

local PROF_ICONS = {
	Alchemy = "Interface\\Icons\\Trade_Alchemy", Blacksmithing = "Interface\\Icons\\Trade_BlackSmithing",
	Cooking = "Interface\\Icons\\INV_Misc_Food_15", Enchanting = "Interface\\Icons\\Trade_Engraving",
	Engineering = "Interface\\Icons\\Trade_Engineering", ["First Aid"] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
	Leatherworking = "Interface\\Icons\\Trade_LeatherWorking", Tailoring = "Interface\\Icons\\Trade_Tailoring",
}

local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if ok then return a, b, c end
	return nil
end

-- The player's own open profession: { name, skill, maxSkill, id }; nil for linked / guild / NPC views.
function Model:OpenProfession()
	local t = T()
	if not t then return nil end
	for _, check in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsNPCCrafting" }) do
		if t[check] and Call(t[check]) then return nil end
	end
	local child = Call(t.GetChildProfessionInfo)
	local base = Call(t.GetBaseProfessionInfo)
	local info
	for _, i in ipairs({ child or false, base or false }) do
		if type(i) == "table" and i.professionID and i.professionID ~= 0 and i.skillLevel then info = info or i end
	end
	if not info then return nil end
	-- the child line ("Enchanting" on Forever) and the base line share the name (in the client's language); Data
	-- is filed under the English key of the base line's ID, so every client language finds it
	local name = (type(base) == "table" and base.professionName) or info.professionName
	local K = CPa.Data.PROF_KEYS
	local key = (type(base) == "table" and K[base.professionID]) or K[info.parentProfessionID] or K[info.professionID] or name
	return { name = name, key = key, skill = info.skillLevel, maxSkill = info.maxSkillLevel or info.skillLevel,
		id = info.professionID, parentID = info.parentProfessionID }
end

-- Colour ranges ProfessionRecorder saw for a recipe (any profession record that has it).
local function RecorderSeen(recipeID, into)
	local PR = _G.ProfessionRecorder
	local profs = PR and PR.db and PR.db.profs
	if type(profs) ~= "table" then return end
	for _, p in pairs(profs) do
		local r = p.recipes and p.recipes[recipeID]
		if r and r.diff then
			for colour, range in pairs(r.diff) do
				into[#into + 1] = { colour, range[1], range[2] }
			end
		end
	end
end

local function Requirements(recipeID)
	local t = T()
	local list = Call(t and t.GetRecipeRequirements, recipeID)
	local out = {}
	if type(list) == "table" then
		for _, req in ipairs(list) do
			if type(req) == "table" and req.name then out[#out + 1] = { name = req.name, met = req.met and true or false } end
		end
	end
	return out
end

local function ItemCount(itemID)
	if C_Item and C_Item.GetItemCount then return Call(C_Item.GetItemCount, itemID) or 0 end
	if GetItemCount then return Call(GetItemCount, itemID) or 0 end
	return 0
end

-- Bags + bank (+ reagent bank): what you own for the Shopping list.
local function OwnedCount(itemID)
	if C_Item and C_Item.GetItemCount then return Call(C_Item.GetItemCount, itemID, true, false, true) or 0 end
	if GetItemCount then return Call(GetItemCount, itemID, true) or 0 end
	return 0
end
Model.OwnedCount = OwnedCount
Model.Requirements = Requirements

local function PlayerFaction()
	local ok, f = pcall(function() return UnitFactionGroup("player") end)
	return ok and f or nil
end

---------------------------------------------------------------------------
-- Reagent pricing: buy or craft
---------------------------------------------------------------------------

local MAX_DEPTH = 3

local function BasicType() return (Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic) or 0 end

local function ReadSchematic(recipeID, learned)
	local CP = CPa.CP
	local Calc = CP and CP.Calc
	if not (Calc and Calc.ReadSchematic) then return nil end
	local prev = Calc.skipSchematicCache
	Calc.skipSchematicCache = not learned or nil
	local ok, sch = pcall(Calc.ReadSchematic, recipeID)
	Calc.skipSchematicCache = prev
	return ok and type(sch) == "table" and sch or nil
end

local function BuyPrice(itemID)
	local CP = CPa.CP
	if not (CP and CP.GetReagentCost) then return nil end
	local ok, unit, kind = pcall(CP.GetReagentCost, CP, itemID)
	if ok and unit then return unit, kind end
	return nil
end

-- makers[itemID] = { { recipe = r, schematic = sch, quantity = n }, ... } for recipes you know or can train now
-- banned[recipeID] = true: an intermediate the route decided not to train
function Model:NewPricer(makers, banned)
	-- unchecked[itemID] = { maker = mk, missing = { itemID, ... } }: a craft that could not be priced because one of
	-- its own reagents has no price (Bolt of Mageweave without a Mageweave Cloth price); buying won by default
	local pricer = { makers = makers, banned = banned or {}, memo = {}, unchecked = {} }
	local visiting = {}
	local function Unit(itemID, depth)
		local m = pricer.memo[itemID]
		if m then return m.unit, m.kind, m.maker end
		local best, kind = BuyPrice(itemID)
		local via
		if depth < MAX_DEPTH and not visiting[itemID] then
			visiting[itemID] = true
			for _, mk in ipairs(makers[itemID] or {}) do
				if not pricer.banned[mk.recipe.id] then
					local cost, complete = 0, true
					for _, slot in ipairs(mk.schematic.reagentSlotSchematics or {}) do
						if slot.reagentType == BasicType() and slot.required ~= false then
							local slotBest
							for _, rg in ipairs(slot.reagents or {}) do
								if rg.itemID and not CPa.Data.tools[rg.itemID] then
									local u = Unit(rg.itemID, depth + 1)
									if u and (not slotBest or u < slotBest) then slotBest = u end
								elseif rg.itemID then
									slotBest = slotBest or 0
								end
							end
							if slotBest then
								cost = cost + slotBest * (slot.quantityRequired or 1)
							else
								complete = false
								local first = slot.reagents and slot.reagents[1] and slot.reagents[1].itemID
								if first then
									local u = pricer.unchecked[itemID] or { maker = mk, missing = {} }
									pricer.unchecked[itemID] = u
									local dup = false
									for _, id in ipairs(u.missing) do if id == first then dup = true end end
									if not dup then table.insert(u.missing, first) end
								end
							end
						end
					end
					local unit = complete and cost / mk.quantity or nil
					if unit and (not best or unit < best - 1e-9) then best, kind, via = unit, "craft", mk end
				end
			end
			visiting[itemID] = nil
		end
		if depth == 0 or not visiting[itemID] then pricer.memo[itemID] = { unit = best, kind = kind, maker = via } end
		return best, kind, via
	end
	pricer.Unit = function(itemID) return Unit(itemID, 0) end
	-- what crafting `qty` of an item needs: calls fn(itemID, qty, kind, maker) for it and, when crafted, its reagents
	-- owned[itemID] = crafted parts you already have: they are used first, so only the rest is broken down
	function pricer.Expand(itemID, qty, fn, depth, owned)
		depth = depth or 0
		local unit, kind, maker = Unit(itemID, 0)
		fn(itemID, qty, kind, maker, unit, depth)
		if kind == "craft" and owned then
			local use = math.min(owned[itemID] or 0, qty)
			owned[itemID] = (owned[itemID] or 0) - use
			qty = qty - use
		end
		if kind == "craft" and maker and depth < MAX_DEPTH and qty > 1e-9 then
			for _, slot in ipairs(maker.schematic.reagentSlotSchematics or {}) do
				if slot.reagentType == BasicType() and slot.required ~= false then
					local pick, pickUnit
					for _, rg in ipairs(slot.reagents or {}) do
						if rg.itemID and not CPa.Data.tools[rg.itemID] then
							local u = Unit(rg.itemID, 0)
							if u and (not pickUnit or u < pickUnit) then pick, pickUnit = rg.itemID, u end
						end
					end
					if pick then pricer.Expand(pick, qty * (slot.quantityRequired or 1) / maker.quantity, fn, depth + 1, owned) end
				end
			end
		end
	end
	return pricer
end

-- Cost of one craft: reagents (tools excluded) minus the made item's worth. nil when a reagent has no price.
function Model:CraftCost(recipeID, learned, pricer)
	local CP = CPa.CP
	if not (CP and CP.Calc and CP.Calc.Get) then return nil end
	local Calc = CP.Calc
	local prev = Calc.skipSchematicCache
	Calc.skipSchematicCache = not learned or nil
	local ok, eco = pcall(Calc.Get, Calc, recipeID)
	Calc.skipSchematicCache = prev
	if not ok or type(eco) ~= "table" then return nil end
	local reagents, tools, cost, missing = {}, {}, 0, {}
	for _, r in ipairs(eco.reagents or {}) do
		if r.itemID and CPa.Data.tools[r.itemID] then
			tools[#tools + 1] = { itemID = r.itemID, have = ItemCount(r.itemID) > 0 }
		elseif not r.isCurrency then
			local unit, kind, maker = r.unit, r.kind, nil
			if pricer and r.itemID then
				local u, k, m = pricer.Unit(r.itemID)
				if u then unit, kind, maker = u, k, m end -- else CraftProfit's own price
			end
			reagents[#reagents + 1] = { itemID = r.itemID, qty = r.qty or 1, unit = unit, kind = kind, maker = maker }
			if unit then cost = cost + unit * (r.qty or 1) else missing[#missing + 1] = r.itemID end
		end
	end
	if #reagents == 0 then return nil, { reason = "no reagents" } end
	local worth = 0
	local mode = CPa:Setting("outputs") or "vendor"
	if mode == "ah" and eco.sale then
		worth = eco.sale - (eco.cut or 0)
	elseif mode ~= "none" and eco.vendorSale then
		worth = eco.vendorSale
	end
	local detail = { reagents = reagents, tools = tools, reagentCost = cost, worth = worth, outputItemID = eco.outputItemID,
		quantity = eco.quantity or 1, missing = missing }
	if #missing > 0 then return nil, detail end
	return cost - worth, detail
end

local function RecipeIcon(recipeID, info)
	if info and info.icon then return info.icon end
	if C_Spell and C_Spell.GetSpellTexture then return Call(C_Spell.GetSpellTexture, recipeID) end
	return nil
end

local function CanHelp(th, skill, target)
	return th.gray > skill and target > skill
end

-- One recipe priced with one band's pricer: { cost, solveCost, detail, bonus, pricer }.
--   bonus: intermediates you craft for it give points too (crafts per craft of r); buyDelta (only with "Craft
--   reagents" off) = extra copper per craft of r when that reagent is bought instead, which the route does at every
--   skill where its craft gives no point.
function Model:Variant(r, pricer, bagsOnly)
	local cost, detail = self:CraftCost(r.id, r.learned, pricer)
	local v = { cost = cost, baseCost = cost, detail = detail, pricer = pricer }
	-- a craft is never free and never pays for itself: a profitable craft must not make the route prefer more crafts
	v.solveCost = cost and (math.max(cost, 0) + CPa:CraftTime()) or nil
	if bagsOnly then return v end
	local byMaker = {}
	local buyInstead = not CPa:Setting("craftReagents")
	for _, rg in ipairs(detail and detail.reagents or {}) do
		if rg.kind == "craft" and rg.itemID then
			local top
			pricer.Expand(rg.itemID, rg.qty or 1, function(itemID, qty, kind, maker, unit, depth)
				if kind == "craft" and maker and maker.recipe.th then
					local b = byMaker[maker.recipe.id]
					if not b then
						b = { th = maker.recipe.th, per = 0, recipe = maker.recipe, itemID = itemID, items = 0 }
						byMaker[maker.recipe.id] = b
						v.bonus = v.bonus or {}
						table.insert(v.bonus, b)
						if depth == 0 then
							local buy = BuyPrice(itemID)
							if buyInstead and buy and rg.unit then b.buyDelta = (rg.qty or 1) * (buy - rg.unit) end
							b.buyUnit = buy
							b.unit = rg.unit
						else
							b.parent = top
						end
					end
					if depth == 0 then
						top = b
						b.items = b.items + (rg.qty or 1)
					end
					b.per = b.per + qty / maker.quantity
				end
			end)
		end
	end
	return v
end

-- Credit for crafting a reagent early that a later step needs anyway (Bolts of Linen Cloth crafted at 1-48 while
-- they give points, used by the Linen Bags after them): the cloth is paid for by the later step, so for the fraction
-- f of its crafts that go to later steps this recipe costs only its time.
-- Owned parts: for the fraction g of r's crafts whose parts you already have (leftover bolts), those parts cost
-- nothing more (they are paid): the craft costs its price minus the parts' value.
-- Value per craft of the reagents you own (raw or crafted): plan B prices them at 0.
local ownedForValue = {}
local function OwnedValue(v)
	local value = 0
	for _, rg in ipairs(v.detail and v.detail.reagents or {}) do
		if rg.itemID and rg.unit and (ownedForValue[rg.itemID] or 0) > 0 then value = value + rg.unit * (rg.qty or 1) end
	end
	return value
end

-- A small preference for recipes already in the route (r.sticky), so a few silver do not reshuffle the whole plan.
local STICKY = 0.97
local function SolveCostOf(r, cost)
	return (math.max(cost, 0) + CPa:CraftTime()) * (r.sticky and STICKY or 1)
end

local function SetCredit(r, f, g)
	r.credit = f > 0 and f or nil
	g = g or r.ownedShare or 0
	r.ownedShare = g > 0 and g or nil
	for _, v in ipairs(r.variants or { r }) do
		if v.baseCost == nil and v.cost ~= nil then v.baseCost = v.cost end
		if v.baseCost then
			v.cost = v.baseCost * (1 - f) - g * OwnedValue(v)
			v.solveCost = SolveCostOf(r, v.cost)
		end
	end
	if r.variants then
		for _, v in ipairs(r.variants) do
			if v.cost then r.cost, r.solveCost = v.cost, v.solveCost break end
		end
	end
end
Model.SetCredit = SetCredit

-- Solve, then credit recipes whose output later steps craft as a reagent, and solve again until the credits settle.
-- ownedShare = { [recipe] = g } is held fixed (see SolveWithCredit). Returns the result and { [recipe] = f }.
local function CreditLoop(opts, ownedShare)
	local owned = opts.owned or {}
	local credit, lowered = {}, {}
	for _, r in ipairs(opts.recipes) do SetCredit(r, 0, ownedShare[r] or 0) end
	local result, changed
	local seen, history = {}, {}
	for _ = 1, 12 do
		local snap = {}
		for _, r in ipairs(opts.recipes) do snap[r] = credit[r] or 0 end
		result = CPa.Solver.Solve(opts)
		-- a plan that comes back means the credits swing: keep the cheapest plan of that cycle
		local sig = {}
		for _, st in ipairs(result.steps) do sig[#sig + 1] = tostring(st.recipe.id) .. ":" .. st.from .. "-" .. st.to end
		sig = table.concat(sig, ",")
		if seen[sig] then
			local best
			for k = seen[sig], #history do
				if not best or history[k].total < best.total then best = history[k] end
			end
			for r, f in pairs(best.snap) do
				credit[r] = f > 0 and f or nil
				SetCredit(r, f, ownedShare[r] or 0)
			end
			return CPa.Solver.Solve(opts), credit
		end
		history[#history + 1] = { total = result.total, snap = snap }
		seen[sig] = #history
		local uses = {}
		for _, st in ipairs(result.steps) do
			for _, it in ipairs(st.inter or {}) do
				if it.itemID and (it.crafts or 0) > 0 then
					uses[it.itemID] = uses[it.itemID] or {}
					table.insert(uses[it.itemID], { from = st.from, crafts = it.crafts, recipe = st.recipe })
				end
			end
		end
		changed = false
		for _, r in ipairs(opts.recipes) do
			local d = r.detail
			local out = d and d.outputItemID
			local f = 0
			if out and uses[out] then
				local crafts, first = 0, nil
				for _, st in ipairs(result.steps) do
					if st.recipe == r then
						crafts = crafts + st.crafts
						first = first or st.from
					end
				end
				local need = 0
				for _, u in ipairs(uses[out]) do
					if u.recipe ~= r and (not first or u.from >= first) then need = need + u.crafts end
				end
				-- the ones you already have are not crafted again
				need = math.max(0, need - (owned[out] or 0))
				if need > 0 then f = crafts > 0 and math.min(1, need / crafts) or 1 end
			end
			local old = credit[r] or 0
			-- full credit makes the route craft more than later steps need, less credit fewer: once lowered, a
			-- credit only rises halfway, so it settles instead of swinging
			if f > old and lowered[r] then f = (old + f) / 2 end
			if f < old then lowered[r] = true end
			if math.abs(f - old) > 0.02 then
				changed = true
				credit[r] = f
				SetCredit(r, f, ownedShare[r] or 0)
			end
		end
		if not changed then break end
	end
	-- the costs shown must be the ones the last credits give
	if changed then result = CPa.Solver.Solve(opts) end
	return result, credit
end

-- What a plan really costs you, whatever credits it was solved with. Steps in order, each at its plain price, with the
-- reagents taken from your stock first: what you own (bags + bank, raw mats and parts alike) and what earlier steps
-- made (Bolts of Linen Cloth crafted at 1-48, used by the Linen Bags). A part from stock is not broken down into its
-- mats; a part crafted on the spot is, so wool cloth you own counts for the bolts made inside a bag step.
-- Returns the total and the cost of each step (training not included).
local function TrueSpend(result, owned, opts)
	local stock = setmetatable({}, { __index = function(t, id) local n = owned[id] or 0; rawset(t, id, n); return n end })
	local spend, per = 0, {}
	for i, st in ipairs(result.steps or {}) do
		local v = st.variant or st.recipe
		local base = v.baseCost or v.cost or 0
		local cost = st.cost + st.crafts * (base - (v.cost or base))
		local d = Model.StepDetail(st)
		local pz = Model.StepPricer(st, opts.pricer)
		for _, rg in ipairs(d and d.reagents or {}) do
			if rg.itemID then
				local function Use(itemID, qty, kind, maker, unit)
					local have = stock[itemID]
					if have > 0 and unit then
						local c = math.min(have, qty)
						cost = cost - unit * c
						-- Expand takes owned parts off itself; raw mats are taken off here
						if kind == "craft" and pz and pz.Expand then return end
						stock[itemID] = have - c
					end
				end
				if pz and pz.Expand then
					pz.Expand(rg.itemID, (rg.qty or 1) * st.crafts, Use, 0, stock)
				else
					Use(rg.itemID, (rg.qty or 1) * st.crafts, rg.kind, nil, rg.unit)
				end
			end
		end
		local made = d or st.recipe.detail
		local out = made and made.outputItemID
		-- a craft can make more than one (stock counts items, not crafts)
		if out then stock[out] = stock[out] + st.crafts * (made.quantity or 1) end
		per[i] = cost
		spend = spend + cost + (st.learnCost or 0)
	end
	return spend, per
end

-- opts.owned = { [itemID] = count } (lazy: counted when first asked): what you already have, raw mats and parts. It is
-- paid for, so it is used before anything is bought or crafted. Two plans are solved and the one that really costs
-- less (TrueSpend) is kept: A with everything priced as usual, B with the reagents you own priced at 0 for the crafts
-- that use them. The rows then show what each step still costs you.
function Model:SolveWithCredit(opts)
	local owned = opts.owned or {}
	ownedForValue = owned
	local consumers = {}
	for _, r in ipairs(opts.recipes) do
		for _, v in ipairs(r.variants or { r }) do
			for _, rg in ipairs(v.detail and v.detail.reagents or {}) do
				if rg.itemID and (owned[rg.itemID] or 0) > 0 then consumers[r] = 1 end
			end
		end
	end
	local function Finish(result, credit, share)
		for _, r in ipairs(opts.recipes) do SetCredit(r, credit[r] or 0, share[r] or 0) end
		local spend, per = TrueSpend(result, owned, opts)
		for i, st in ipairs(result.steps) do st.cost = per[i] end
		result.total = spend
		return result, credit
	end
	local resA, creditA = CreditLoop(opts, {})
	if not next(consumers) then return Finish(resA, creditA, {}) end
	local spendA = TrueSpend(resA, owned, opts)
	local resB, creditB = CreditLoop(opts, consumers)
	local spendB = TrueSpend(resB, owned, opts)
	if spendB < spendA - 1e-6 then return Finish(resB, creditB, consumers) end
	return Finish(resA, creditA, {})
end

local function ItemNameOf(itemID)
	if C_Item and C_Item.GetItemNameByID then
		local ok, n = pcall(C_Item.GetItemNameByID, itemID)
		if ok and n then return n end
	end
	return nil
end

-- Reagents the route buys although this profession has a recipe for them that is neither learned nor recorded at a
-- trainer / vendor (Bolt of Silk Cloth on a fresh character before anyone recorded its trainer). Matched by name:
-- the recipe is called like the item. { { itemID, recipeID, name }, ... }
function Model:Unsourced(result, infos, sources)
	local byName = {}
	for id, info in pairs(infos or {}) do
		if type(info.name) == "string" and not info.learned and not sources[id] then byName[info.name] = byName[info.name] or id end
	end
	local out, seen = {}, {}
	for _, st in ipairs(result.steps or {}) do
		local d = Model.StepDetail(st)
		for _, rg in ipairs(d and d.reagents or {}) do
			if rg.itemID and rg.kind ~= "craft" and not seen[rg.itemID] then
				seen[rg.itemID] = true
				local name = ItemNameOf(rg.itemID)
				local id = name and byName[name]
				if id then out[#out + 1] = { itemID = rg.itemID, recipeID = id, name = name } end
			end
		end
	end
	return out
end

-- What a route step uses: its band's detail / pricer (the recipe's own when it has one band).
function Model.StepDetail(st) return (st.variant and st.variant.detail) or st.recipe.detail end
function Model.StepPricer(st, fallback) return (st.variant and st.variant.pricer) or fallback end

local RANK_NAMES = { Apprentice = true, Journeyman = true, Expert = true, Artisan = true, Master = true }

-- Recordings made before ProfessionRecorder 0.2.1 carry no faction: known NPCs get theirs from Data.lua.
local function KnownFaction(name)
	for _, npc in pairs(CPa.Data.npcs) do if npc.name == name then return npc.faction end end
	return nil
end

local function Place(loc)
	if type(loc) ~= "table" then return "" end
	if loc.subzone and loc.subzone ~= "" and loc.zone and loc.subzone ~= loc.zone then return loc.subzone .. ", " .. loc.zone end
	return loc.zone or loc.map or ""
end

-- Sources from recorded visits (any trainer or recipe vendor anyone on the account visited): CraftPath's own
-- recorder (Recorder.lua) first, then ProfessionRecorder's when it is installed. Returns
-- sources[recipeID] = { skill, cost, npc } and ranks[name] = { skill, cost, level, npc }. Trainers list only what
-- the visiting character still lacks, and only part of the way ahead, so the lists grow with every visit.
function Model:RecordedSources(profName, infos)
	local out, ranks = {}, {}
	local dbs = {}
	local own = CPa.Recorder and CPa.Recorder:Store()
	if own then dbs[#dbs + 1] = own end
	local PR = _G.ProfessionRecorder
	if PR and type(PR.db) == "table" then dbs[#dbs + 1] = PR.db end
	if #dbs == 0 then return out, ranks end
	local byName, order = {}, {}
	for id in pairs(infos) do order[#order + 1] = id end
	table.sort(order)
	for _, id in ipairs(order) do
		local name = infos[id].name
		if type(name) == "string" and not byName[name:lower()] then byName[name:lower()] = id end
	end
	for _, db in ipairs(dbs) do
		for _, tr in pairs(db.trainers or {}) do
			local npc = { name = tostring(tr.name or "trainer"), place = Place(tr.loc), kind = "trainer", faction = tr.faction or KnownFaction(tr.name) }
			for _, sv in ipairs(tr.services or {}) do
				if type(sv.name) == "string" and sv.prof == profName and sv.skill then
					local rank = sv.name:match("^(%a+) " .. profName .. "$")
					if not (rank and RANK_NAMES[rank]) and not (sv.tipID and infos[sv.tipID]) and not byName[sv.name:lower()] then
						-- not English: a service that is no recipe and asks for a rank's skill and level is that rank
						rank = nil
						for _, rk in ipairs(CPa.Data.RANKS) do
							if rk.at == sv.skill and rk.level == sv.level then rank = rk.name end
						end
					end
					if rank and RANK_NAMES[rank] then
						ranks[rank] = ranks[rank] or { skill = sv.skill, cost = sv.cost, level = sv.level, npc = npc, faction = tr.faction }
					else
						local id = (sv.tipID and infos[sv.tipID]) and sv.tipID or byName[sv.name:lower()]
						if id and not out[id] then out[id] = { sv.skill, sv.cost or 0, npc } end
					end
				end
			end
		end
		for _, v in pairs(db.vendors or {}) do
			local npc = { name = tostring(v.name or "vendor"), place = Place(v.loc), kind = "vendor", faction = v.faction or KnownFaction(v.name) }
			for _, it in ipairs(v.items or {}) do
				if it.reqProf == profName and type(it.name) == "string" then
					local teaches = it.name:match("^[^:]+:%s*(.+)$") or it.name
					local id = byName[teaches:lower()]
					if id and not out[id] then out[id] = { it.reqSkill or 1, it.price or 0, npc } end
				end
			end
		end
	end
	return out, ranks
end

-- Rank training between the current skill and the target: { { name, rank, by, at, level, cost, npc }, ... }
-- (`by` = the cap you hit without it; cost nil when no trainer visit recorded it).
function Model:RankPlan(prof, target, recordedRanks)
	local out = {}
	local data = CPa.Data.rankSources[prof.key or prof.name] or {}
	local faction = PlayerFaction()
	for _, rk in ipairs(CPa.Data.RANKS) do
		if (prof.maxSkill or 0) < rk.cap and target > rk.from then
			local rec = recordedRanks[rk.name]
			local d = data[rk.name]
			out[#out + 1] = {
				name = rk.name .. " " .. prof.name, rank = rk.name, by = rk.from, cap = rk.cap,
				at = (rec and rec.skill) or rk.at, level = (rec and rec.level) or rk.level,
				cost = (rec and rec.cost) or (d and d[1]) or nil,
				npc = (rec and rec.npc and Model.NpcFor(rec.npc, prof, faction)) or (d and d[2] and Model.NpcFor(CPa.Data.npcs[d[2]], prof, faction)) or nil,
			}
		end
	end
	return out
end

-- A recorded NPC as the player can use it: the same NPC on its own faction (or one without a faction), "your
-- trainer" for the other faction's trainer (they teach the same recipes at the same skill and price), nil for
-- the other faction's vendor (its recipe may not be sold on your side).
function Model.NpcFor(npc, prof, faction)
	if type(npc) ~= "table" or not npc.faction or not faction or npc.faction == faction then return npc end
	if npc.kind == "trainer" then
		return { name = "your " .. tostring(prof.name) .. " trainer", place = "a city guard shows the way", kind = "trainer", generic = true }
	end
	return nil
end

-- Reads the open profession and solves. Returns the plan (also kept in Model.plan) or nil, reason.
function Model:Build()
	local t = T()
	local prof = self:OpenProfession()
	if not prof then return nil, "closed" end
	local ids = Call(t.GetAllRecipeIDs)
	if type(ids) ~= "table" then return nil, "no recipes" end
	self.lastKey = self:StateKey(prof)
	local seenData = CPa.Data.seen[prof.key] or {}
	local target = CPa:GetTarget(prof.key, prof.skill, prof.maxSkill)
	local bagsOnly = CPa:Setting("bagsOnly") and true or false
	local infos = {}
	for _, id in ipairs(ids) do
		local info = Call(t.GetRecipeInfo, id)
		if type(info) == "table" then infos[id] = info end
	end
	-- sources: Data.lua (the other faction's trainers as "your trainer", its vendors left out), then every trainer /
	-- vendor ProfessionRecorder recorded on this account, which wins (the account's alts may be on the other side:
	-- recordings from 0.2.1 on carry the faction and go through the same rule)
	local sources, sourceCount, otherFaction = {}, 0, false
	local faction = PlayerFaction()
	for id, src in pairs(CPa.Data.sources[prof.key] or {}) do
		local npc = CPa.Data.npcs[src[3]]
		local use = Model.NpcFor(npc, prof, faction)
		if use then
			if use ~= npc then otherFaction = true end
			sources[id] = { src[1], src[2], use }
		elseif not npc then
			sources[id] = src
		end
	end
	local recorded, recordedRanks = self:RecordedSources(prof.name, infos)
	for id, src in pairs(recorded) do
		local use = Model.NpcFor(src[3], prof, faction)
		if use then
			if use ~= src[3] then otherFaction = true end
			sources[id] = { src[1], src[2], use }
		end
	end
	for _ in pairs(sources) do sourceCount = sourceCount + 1 end
	-- 1. every usable recipe: learned, or with a recorded trainer / vendor
	local usable = {}
	for _, id in ipairs(ids) do
		local info = infos[id]
		local src = sources[id]
		if type(info) == "table" and (info.learned or src) then
			local seen = {}
			for _, o in ipairs(seenData[id] or {}) do seen[#seen + 1] = o end
			RecorderSeen(id, seen)
			if info.learned and info.relativeDifficulty ~= nil then
				seen[#seen + 1] = { info.relativeDifficulty, prof.skill, prof.skill }
			end
			local trivial = (type(info.maxTrivialLevel) == "number" and info.maxTrivialLevel > 0) and info.maxTrivialLevel or nil
			local learnAt = src and src[1] or nil
			local th = CPa.Solver.Thresholds({ learnAt = learnAt, trivial = trivial, seen = seen,
				step = (CPa.Data.STEPS and CPa.Data.STEPS[prof.key]) or CPa.Data.STEP, span = CPa.Data.FALLBACK_SPAN })
			usable[#usable + 1] = {
				id = id, name = info.name, icon = RecipeIcon(id, info), learned = info.learned and true or false,
				learnAt = (not info.learned) and learnAt or nil,
				learnCost = (not info.learned and src) and src[2] or 0,
				npc = src and (type(src[3]) == "table" and src[3] or CPa.Data.npcs[src[3]]) or nil,
				th = th,
			}
		end
	end

	-- 2. makers of intermediates: recipes you know, or can train before the target (from their learn skill on)
	local makersAll = {}
	for _, r in ipairs(usable) do
		if r.learned or (r.learnAt and r.learnAt < target) then
			local sch = ReadSchematic(r.id, r.learned)
			local out = sch and sch.outputItemID
			if type(out) == "number" and out > 0 then
				local q = ((sch.quantityMin or 1) + (sch.quantityMax or sch.quantityMin or 1)) / 2
				makersAll[out] = makersAll[out] or {}
				table.insert(makersAll[out], { recipe = r, schematic = sch, quantity = q > 0 and q or 1 })
			end
		end
	end
	-- skill bands: a reagent's price can drop where its maker becomes trainable (Bolt of Woolen Cloth from 55)
	local bands, seenBand = { prof.skill }, { [prof.skill] = true }
	for _, list in pairs(makersAll) do
		for _, mk in ipairs(list) do
			local at = mk.recipe.learnAt
			if not mk.recipe.learned and at and at > prof.skill and at < target and not seenBand[at] then
				seenBand[at] = true
				bands[#bands + 1] = at
			end
		end
	end
	table.sort(bands)
	local function MakersAt(skill)
		local m = {}
		for out, list in pairs(makersAll) do
			for _, mk in ipairs(list) do
				if mk.recipe.learned or (mk.recipe.learnAt and mk.recipe.learnAt <= skill) then
					m[out] = m[out] or {}
					table.insert(m[out], mk)
				end
			end
		end
		return m
	end

	-- 3. price per band, solve; drop trainable intermediates whose savings do not pay for their training; again
	local banned = {}
	local result, recipes, unpriced, bagRecipes, bags, pricer, extra
	for _ = 1, 4 do
		local pricers = {}
		for i, at in ipairs(bands) do pricers[i] = self:NewPricer(MakersAt(at), banned) end
		pricer = pricers[1]
		recipes, unpriced, bagRecipes, bags = {}, {}, {}, {}
		for _, r in ipairs(usable) do
			r.cost, r.detail, r.reagents, r.bonus, r.solveCost, r.variants = nil, nil, nil, nil, nil, nil
			-- only recipes that can still give a point before the target are worth pricing
			if CanHelp(r.th, prof.skill, target) then
				local variants, first, firstPriced = {}, nil, nil
				for i, at in ipairs(bands) do
					local v = self:Variant(r, pricers[i], bagsOnly)
					v.from = at
					local last = variants[#variants]
					-- a band that changes nothing for this recipe is merged into the one before
					local same = last and ((last.cost == nil and v.cost == nil) or (last.cost and v.cost and math.abs(last.cost - v.cost) < 1e-6))
						and #(last.bonus or {}) == #(v.bonus or {})
					if not same then variants[#variants + 1] = v end
					first = first or v
					if v.cost and not firstPriced then firstPriced = v end
				end
				local base = firstPriced or first
				r.variants = #variants > 1 and variants or nil
				r.cost, r.detail, r.solveCost, r.bonus = base.cost, base.detail, base.solveCost, base.bonus
				r.baseCost, r.credit = base.cost, nil
				r.requirements = r.requirements or Requirements(r.id)
				if r.cost then recipes[#recipes + 1] = r
				elseif base.detail and #(base.detail.missing or {}) > 0 then unpriced[#unpriced + 1] = r end
				-- bag mode: known or trainable recipes whose tools you carry; mats straight from the bags (no crafting)
				local detail = first.detail
				local toolsOk = true
				for _, tool in ipairs(detail and detail.tools or {}) do if not tool.have then toolsOk = false end end
				if detail and detail.reagents and #detail.reagents > 0 and toolsOk then
					bagRecipes[#bagRecipes + 1] = r
					r.reagents = {}
					for _, rg in ipairs(detail.reagents) do
						r.reagents[#r.reagents + 1] = { itemID = rg.itemID, qty = rg.qty, unit = BuyPrice(rg.itemID) or rg.unit }
						if rg.itemID and bags[rg.itemID] == nil then bags[rg.itemID] = ItemCount(rg.itemID) end
					end
				end
			end
		end
		if bagsOnly then
			result = CPa.Solver.SolveFromBags({ from = prof.skill, to = target, recipes = bagRecipes, bags = bags })
			extra = nil
			break
		end
		local breaks = {}
		-- split steps only where a rank you still have to train stops you (not at caps you already passed)
		for _, rk in ipairs(self:RankPlan(prof, target, recordedRanks)) do breaks[rk.by] = true end
		local credit
		-- parts first (as Craft next / Craft all craft them), with the parts you already own counted
		local owned = setmetatable({}, { __index = function(t, id) local n = OwnedCount(id); rawset(t, id, n); return n end })
		local last = self.lastRoute and self.lastRoute.key == prof.key and self.lastRoute.ids or {}
		for _, r in ipairs(recipes) do
			r.sticky = last[r.id] or nil
			SetCredit(r, 0, 0)
		end
		result, credit = self:SolveWithCredit({ from = prof.skill, to = target, recipes = recipes, breaks = breaks,
			partsFirst = true, owned = owned, pricer = pricer })
		-- steps that craft a reagent for later: how much of it goes to which later steps
		for _, st in ipairs(result.steps) do
			local f = credit[st.recipe]
			local out = st.recipe.detail and st.recipe.detail.outputItemID
			if f and f > 0 and out then
				local names, seenN = {}, {}
				for _, st2 in ipairs(result.steps) do
					for _, it in ipairs(st2.inter or {}) do
						if it.itemID == out and st2.from >= st.from and not seenN[st2.recipe.name] then
							seenN[st2.recipe.name] = true
							names[#names + 1] = tostring(st2.recipe.name)
						end
					end
				end
				st.forLater = { itemID = out, f = f, crafts = st.crafts * f, usedBy = table.concat(names, ", ") }
				result.madeEarlier = result.madeEarlier or {}
				result.madeEarlier[out] = result.madeEarlier[out] or st
			end
		end
		extra = self:Intermediates(result, pricer)
		local drop
		for _, e in pairs(extra.byRecipe) do
			if e.learnCost > 0 and not e.trainedByRoute and e.savings ~= nil and e.savings < e.learnCost then
				banned[e.recipe.id] = true
				drop = true
			end
		end
		if not drop then break end
	end
	local makers = makersAll
	if extra then
		result.extraTraining = extra.training
		result.total = result.total + extra.training
	end
	-- ranks to train on the way (their known prices count in the total)
	local ranks = self:RankPlan(prof, target, recordedRanks)
	local rankCost = 0
	for _, rk in ipairs(ranks) do rankCost = rankCost + (rk.cost or 0) end
	result.rankTraining = rankCost
	result.total = result.total + rankCost
	-- crafts that could not be priced, for reagents the route actually uses
	local unchecked, seenU = {}, {}
	for _, st in ipairs(result.steps or {}) do
		local d, pz = Model.StepDetail(st), Model.StepPricer(st, pricer)
		for _, rg in ipairs(d and d.reagents or {}) do
			local u = rg.itemID and pz and pz.unchecked[rg.itemID]
			if u and not seenU[rg.itemID] and rg.kind ~= "craft" then
				seenU[rg.itemID] = true
				unchecked[#unchecked + 1] = { itemID = rg.itemID, maker = u.maker, missing = u.missing }
			end
		end
	end
	-- how old the AH prices of what the route buys are (seconds, the oldest one)
	local priceAge
	if CPa.CP and CPa.CP.GetPriceAge then
		local seenA = {}
		for _, st in ipairs(result.steps or {}) do
			local d = Model.StepDetail(st)
			for _, rg in ipairs(d and d.reagents or {}) do
				if rg.itemID and not seenA[rg.itemID] and rg.kind ~= "vendor" then
					seenA[rg.itemID] = true
					local ok, age = pcall(CPa.CP.GetPriceAge, CPa.CP, rg.itemID)
					if ok and type(age) == "number" and (not priceAge or age > priceAge) then priceAge = age end
				end
			end
		end
	end
	local plan = { prof = prof.name, key = prof.key, profID = prof.id, icon = PROF_ICONS[prof.key], skill = prof.skill,
		start = CPa:GetStart(prof.key, prof.skill), maxSkill = prof.maxSkill, target = target,
		covered = CPa.Data.COVERED[prof.key] or sourceCount > 0, sourceCount = sourceCount, otherFaction = otherFaction,
		priceAge = priceAge, extra = extra,
		result = result, recipes = bagsOnly and bagRecipes or recipes, unpriced = bagsOnly and {} or unpriced,
		bagsOnly = bagsOnly, bags = bags, built = time and time() or 0, pricer = pricer, makers = makers,
		banned = banned, usable = usable, unchecked = unchecked, ranks = ranks,
		unsourced = self:Unsourced(result, infos, sources) }
	plan.shopping, plan.training = self:Shopping(result, bagsOnly and bags or nil, (not bagsOnly) and pricer or nil, extra)
	for _, rk in ipairs(ranks) do
		table.insert(plan.training, 1, { recipe = { name = rk.name, icon = plan.icon, learnAt = rk.at }, cost = rk.cost or 0,
			unknownCost = rk.cost == nil, npc = rk.npc, rank = rk })
	end
	-- the route the next build gives a small preference to (so a few silver do not reshuffle it)
	local ids = {}
	for _, st in ipairs(result.steps or {}) do ids[st.recipe.id] = true end
	self.lastRoute = { key = prof.key, ids = ids }
	self.plan = plan
	CPa:Fire("PLAN_UPDATED", plan)
	return plan
end

Model.BuyPrice = BuyPrice

-- Other recipes that could give the point at `skill`, cheapest per expected point first:
-- { { recipe, perPoint, chance }, ... } (recipes you can use there: known, or trainable by then).
function Model:Alternatives(plan, skill, exclude)
	local out = {}
	for _, r in ipairs(plan and plan.recipes or {}) do
		local v = CPa.Solver.V(r, skill)
		if r ~= exclude and type(v.cost) == "number" and (not r.learnAt or skill >= r.learnAt) then
			local p = CPa.Solver.Gain(r, skill)
			if p > 0 then out[#out + 1] = { recipe = r, perPoint = v.cost / p, chance = p } end
		end
	end
	table.sort(out, function(a, b) return a.perPoint < b.perPoint end)
	return out
end

-- Crafted intermediates the route uses: per maker recipe how many it makes, what that saves against buying, and
-- the training of the ones you do not know (charged once, unless a route step trains the same recipe).
function Model:Intermediates(result, pricer)
	local out = { byRecipe = {}, training = 0 }
	local stepTrains = {}
	for _, st in ipairs(result.steps or {}) do
		if (st.learnCost or 0) > 0 then stepTrains[st.recipe.id] = true end
	end
	for _, st in ipairs(result.steps or {}) do
		local pz = Model.StepPricer(st, pricer)
		for _, rg in ipairs(Model.StepDetail(st) and Model.StepDetail(st).reagents or {}) do
			if rg.itemID then
				pz.Expand(rg.itemID, rg.qty * st.crafts, function(itemID, qty, kind, maker, unit)
					if kind ~= "craft" or not maker then return end
					local r = maker.recipe
					local e = out.byRecipe[r.id]
					if not e then
						e = { recipe = r, itemID = itemID, made = 0, savings = 0, learnCost = r.learnCost or 0,
							trainedByRoute = stepTrains[r.id] or false }
						out.byRecipe[r.id] = e
					end
					e.made = e.made + qty
					local buy = BuyPrice(itemID)
					if buy and e.savings then e.savings = e.savings + (buy - unit) * qty else e.savings = nil end
				end)
			end
		end
	end
	for _, e in pairs(out.byRecipe) do
		if e.learnCost > 0 and not e.trainedByRoute then out.training = out.training + e.learnCost end
	end
	return out
end

-- What to get for the route up to skill `upTo` (nil = all of it) and the training bill on the way.
-- Quantities carry a safety margin: the expected crafts plus 0.84 standard deviations of the whole range (about
-- an 80% chance that it is enough), spread over the steps by their share of the crafts.
-- Crafted reagents are listed as "craft" rows and broken down into what they are made of.
-- In bag mode (bags given) each entry also says how many you have.
local MARGIN_Z = 0.84
function Model:Shopping(result, bags, pricer, extra, upTo)
	local byItem, list, training = {}, {}, {}
	-- share of each step inside the range, and the margin factor over all of them
	local share, sumCrafts, sumVar = {}, 0, 0
	for i, st in ipairs(result.steps or {}) do
		local f = 1
		if upTo then f = math.max(0, math.min(1, (upTo - st.from) / math.max(st.to - st.from, 1))) end
		share[i] = f
		sumCrafts = sumCrafts + st.crafts * f
		sumVar = sumVar + (st.var or 0) * f
	end
	local factor = sumCrafts > 0 and (1 + MARGIN_Z * math.sqrt(math.max(sumVar, 0)) / sumCrafts) or 1
	-- crafted parts you already own (leftover bolts) cut the mats to buy for them
	local owned = not bags and setmetatable({}, { __index = function(t, id) local n = OwnedCount(id); rawset(t, id, n); return n end }) or nil
	local function Add(itemID, qty, kind, unit, maker)
		if qty <= 1e-9 then return end
		-- a reagent can be crafted for one step and bought for another: one row each
		local key = tostring(itemID) .. (kind == "craft" and ":craft" or "")
		local e = byItem[key]
		if not e then
			e = { itemID = itemID, qty = 0, unit = unit, kind = kind, maker = maker, have = bags and bags[itemID] or nil }
			byItem[key] = e
			list[#list + 1] = e
		end
		e.qty = e.qty + qty
	end
	for i, st in ipairs(result.steps or {}) do
		local n = st.crafts * share[i] * factor
		if not upTo then st.craftsUp = math.ceil(n - 1e-9) end
		-- reagents crafted early for later steps: their mats are counted where they are used, unless those steps
		-- are outside the scope (then this step buys them)
		local laterInScope = false
		if st.forLater then
			for j, st2 in ipairs(result.steps) do
				if j > i and share[j] > 0 then
					for _, it in ipairs(st2.inter or {}) do if it.itemID == st.forLater.itemID then laterInScope = true end end
				end
			end
		end
		local nMats = (st.forLater and laterInScope) and n * (1 - st.forLater.f) or n
		local pz = pricer and Model.StepPricer(st, pricer)
		local sd = Model.StepDetail(st)
		for _, rg in ipairs(sd and sd.reagents or {}) do
			if pz and rg.itemID then
				-- bought instead of crafted ("Craft reagents" off, where its craft gives no point)
				local bought = 0
				for _, it in ipairs(st.inter or {}) do
					if it.top and it.itemID == rg.itemID and (it.bought or 0) > 0 then bought = it.bought * nMats / math.max(st.crafts, 1e-9) end
				end
				bought = math.min(bought, rg.qty * nMats)
				if bought > 0 then Add(rg.itemID, bought, "ah", BuyPrice(rg.itemID), nil) end
				pz.Expand(rg.itemID, rg.qty * nMats - bought, function(itemID, qty, kind, maker, unit) Add(itemID, qty, kind, unit, maker) end, 0, owned)
			else
				Add(rg.itemID, rg.qty * nMats, rg.kind, rg.unit, nil)
			end
		end
		-- a tool the step needs and you do not carry (a rod): one, kept
		for _, tool in ipairs(sd and sd.tools or {}) do
			if share[i] > 0 and tool.itemID and not tool.have and not byItem[tostring(tool.itemID) .. ":tool"] then
				local e = { itemID = tool.itemID, qty = 1, unit = BuyPrice(tool.itemID), kind = "tool" }
				byItem[tostring(tool.itemID) .. ":tool"] = e
				list[#list + 1] = e
			end
		end
		if (st.learnCost or 0) > 0 and share[i] > 0 then
			training[#training + 1] = { recipe = st.recipe, cost = st.learnCost, npc = st.recipe.npc }
		end
	end
	for _, e in ipairs(list) do
		e.qty = math.ceil(e.qty - 1e-9)
		if not bags then
			e.have = OwnedCount(e.itemID)
			e.bags = ItemCount(e.itemID)
			e.need = math.max(0, e.qty - e.have)
		end
	end
	for _, e in pairs(extra and extra.byRecipe or {}) do
		if e.learnCost > 0 and not e.trainedByRoute then
			training[#training + 1] = { recipe = e.recipe, cost = e.learnCost, npc = e.recipe.npc, reagent = e.itemID }
		end
	end
	-- what you still need first; then crafted rows (what to make), then what to buy, dearest first
	table.sort(list, function(a, b)
		local ca, cb = (a.need or 1) > 0, (b.need or 1) > 0
		if ca ~= cb then return ca end
		if (a.kind == "craft") ~= (b.kind == "craft") then return a.kind == "craft" end
		return (a.unit or 0) * a.qty > (b.unit or 0) * b.qty
	end)
	return list, training
end

-- What you own changes while you shop: have / need counted again (bags + bank).
local function Recount(list)
	for _, e in ipairs(list or {}) do
		if e.itemID then
			e.have = OwnedCount(e.itemID)
			e.bags = ItemCount(e.itemID)
			e.need = math.max(0, e.qty - e.have)
		end
	end
	return list
end

-- The Shopping list for a scope: "step" (the current step), "25" (the next 25 points) or "all".
function Model:ShoppingFor(plan, scope)
	if not plan then return {}, {} end
	if plan.bagsOnly then return plan.shopping or {}, plan.training or {} end
	local upTo
	local steps = plan.result.steps or {}
	if scope == "step" then
		upTo = steps[1] and steps[1].to or plan.skill
	elseif scope ~= "all" then
		upTo = plan.skill + 25
	end
	if not upTo or upTo >= plan.target then return Recount(plan.shopping or {}), plan.training or {} end
	local list, training = self:Shopping(plan.result, nil, plan.pricer, plan.extra, upTo)
	for _, rk in ipairs(plan.ranks or {}) do
		if rk.by < upTo then
			table.insert(training, 1, { recipe = { name = rk.name, icon = plan.icon, learnAt = rk.at }, cost = rk.cost or 0,
				unknownCost = rk.cost == nil, npc = rk.npc, rank = rk })
		end
	end
	return list, training
end

---------------------------------------------------------------------------
-- Rebuild triggers (throttled: the window fires several updates per change)
---------------------------------------------------------------------------

-- The plan is rebuilt only when something it depends on changed: profession, skill, cap, target, or a change
-- counted in Model.dirty (settings, prices, learned recipes, bag contents in bag mode). It is rebuilt while the
-- profession window is open even with the CraftPath window closed, so Craft next (button, key binding, macro)
-- never works from an old plan.
Model.dirty = 0

function Model:StateKey(prof)
	prof = prof or self:OpenProfession()
	if not prof then return nil end
	return table.concat({ tostring(prof.key), tostring(prof.id), tostring(prof.skill), tostring(prof.maxSkill),
		tostring(CPa:GetTarget(prof.key, prof.skill, prof.maxSkill)), tostring(self.dirty) }, "|")
end

function Model:IsStale()
	local key = self:StateKey()
	return key ~= nil and (key ~= self.lastKey or not self.plan)
end

-- Rebuild now when stale (Craft next calls this before it acts).
function Model:EnsureFresh()
	if self:IsStale() then self:Build() end
	return self.plan
end

local pending = false
function Model:Queue()
	if pending then return end
	pending = true
	local function Run()
		pending = false
		if Model:IsStale() then Model:Build() end
	end
	if C_Timer and C_Timer.After then C_Timer.After(0.3, Run) else Run() end
end

local function Dirty() Model.dirty = Model.dirty + 1; Model:Queue() end
CPa:RegisterEvent("TRADE_SKILL_SHOW", Dirty)
CPa:RegisterEvent("NEW_RECIPE_LEARNED", Dirty)
CPa:RegisterEvent("TRADE_SKILL_LIST_UPDATE", function() Model:Queue() end)
CPa:RegisterEvent("CHAT_MSG_SKILL", function() Model:Queue() end)
-- bag mode: every craft changes the bags; plan again once they settle (1.5 s), not on every key press
local bagTimer = false
CPa:RegisterEvent("BAG_UPDATE_DELAYED", function()
	if not CPa:Setting("bagsOnly") or bagTimer then return end
	bagTimer = true
	local function Run() bagTimer = false; Dirty() end
	if C_Timer and C_Timer.After then C_Timer.After(1.5, Run) else Run() end
end)
CPa:On("SETTINGS_CHANGED", Dirty)
if CPa.CP and CPa.CP.On then
	CPa.CP:On("PRICES_UPDATED", Dirty)
end
