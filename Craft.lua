-- CraftPath :: Craft
-- "Craft next": crafts one of the route's current step (the recipe for your skill now), so the route is followed
-- even when the step changes. Uses Blizzard's own crafting path (verified in the Forever source,
-- Blizzard_ProfessionsCrafting.lua): the recipe is selected in the list, then CraftingPage:CreateInternal(recipeID,
-- 1, level) crafts it; enchants go through the transaction's enchant allocation (the "Optional Target" slot).
--
-- Enchant targets: switching recipes empties Blizzard's target slot. The button puts back an item you already
-- enchanted (remembered by GUID whenever an enchant is cast through the profession window) when the new enchant
-- accepts it (C_TradeSkillUI.GetEnchantItems, the list Blizzard's own slot flyout uses). It never picks an item
-- you have not enchanted before; then it asks you to fill the slot once. Equipped items are never remembered or
-- filled in: the button only enchants items in your bags.
--
-- Craft:Now(plan) says what to do this minute (craft, make a part first, learn, train a rank, why nothing); the
-- window's Now line, the button and its tooltip all use it, and the button always says why it did not craft.
-- Also: a notice when the route moves on to a new recipe (on-screen and in chat).

local _, CPa = ...
local Craft = {}
CPa.Craft = Craft

local MAX_TARGETS = 10

local function Page() return ProfessionsFrame and ProfessionsFrame.CraftingPage end

local function ItemCount(itemID)
	if C_Item and C_Item.GetItemCount then
		local ok, n = pcall(C_Item.GetItemCount, itemID)
		if ok and n then return n end
	end
	return 0
end

local function Notice(msg, r, g, b)
	if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(msg, r or 1, g or 0.82, b or 0) end
	CPa:Print(msg)
end
Craft.Notice = Notice

-- Spamming the key must not flood chat: on screen every time, in chat at most one line every 3 seconds (a new
-- message gets through at once).
local function Say(msg)
	local now = GetTime and GetTime() or 0
	if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(msg, 1, 0.82, 0) end
	if Craft.lastSay == msg and now - (Craft.lastSayAt or 0) < 3 then return end
	if Craft.lastSay ~= msg and now - (Craft.lastSayAt or 0) < 1 then return end
	Craft.lastSay, Craft.lastSayAt = msg, now
	CPa:Print(msg)
end

-- GUIDs of what you wear (never an enchant target for Craft next)
local function EquippedGUIDs()
	local out = {}
	if not (ItemLocation and ItemLocation.CreateFromEquipmentSlot and C_Item and C_Item.GetItemGUID) then return out end
	for slot = 1, 19 do
		local ok, guid = pcall(function()
			local loc = ItemLocation:CreateFromEquipmentSlot(slot)
			if C_Item.DoesItemExist and not C_Item.DoesItemExist(loc) then return nil end
			return C_Item.GetItemGUID(loc)
		end)
		if ok and guid then out[guid] = true end
	end
	return out
end
Craft.EquippedGUIDs = EquippedGUIDs

---------------------------------------------------------------------------
-- Remembered enchant targets (item GUIDs, newest first, capped)
---------------------------------------------------------------------------

function Craft:Targets()
	if not CPa.db then return {} end
	CPa.db.enchantTargets = CPa.db.enchantTargets or {}
	return CPa.db.enchantTargets
end

function Craft:Remember(guid)
	if type(guid) ~= "string" or guid == "" or EquippedGUIDs()[guid] then return end
	local list = self:Targets()
	for i = #list, 1, -1 do if list[i] == guid then table.remove(list, i) end end
	table.insert(list, 1, guid)
	while #list > MAX_TARGETS do table.remove(list) end
end

local function AllocationGUID(transaction)
	local item = transaction and transaction.GetEnchantAllocation and transaction:GetEnchantAllocation()
	return item and item.GetItemGUID and item:GetItemGUID() or nil
end

-- Every craft through the profession window (Blizzard's button or ours) remembers its enchant target. Hooks the
-- CraftingPage frame instance (no event carries the target item).
function Craft:HookPage()
	local page = Page()
	if self.hooked or not (page and page.CreateInternal and hooksecurefunc) then return end
	self.hooked = true
	hooksecurefunc(page, "CreateInternal", function(p)
		Craft.lastCraft = GetTime and GetTime() or 0 -- the replace popup is answered only right after a craft here
		local form = p.SchematicForm
		local ok, transaction = pcall(function() return form:GetTransaction() end)
		if ok then Craft:Remember(AllocationGUID(transaction)) end
	end)
end

---------------------------------------------------------------------------
-- Select + craft
---------------------------------------------------------------------------

-- Select a recipe in the profession window's list (or its pane when the list hides it). True when shown.
function Craft:Select(recipeID)
	local page = Page()
	local list = page and page.RecipeList
	if not (ProfessionsFrame and ProfessionsFrame:IsShown() and list and C_TradeSkillUI) then return false end
	local okInfo, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
	if not okInfo or type(info) ~= "table" then return false end
	if list.SelectRecipe then
		local ok, elementData = pcall(list.SelectRecipe, list, info, true)
		if ok and elementData then return true end
	end
	if page.SelectRecipe then
		local skipSelectInList = true
		return (pcall(page.SelectRecipe, page, info, skipSelectInList))
	end
	return false
end

local function SelectedRecipeID(form)
	local ok, info = pcall(function() return form:GetRecipeInfo() end)
	return ok and type(info) == "table" and info.recipeID or nil
end

local function IsEnchant(form)
	local sch = form and form.recipeSchematic
	local enchantType = Enum and Enum.TradeskillRecipeType and Enum.TradeskillRecipeType.Enchant
	return sch and enchantType ~= nil and sch.recipeType == enchantType
end

-- Put a remembered item into the enchant slot when the recipe accepts it. Returns true when the slot is filled.
function Craft:FillTarget(form, transaction, recipeID)
	if AllocationGUID(transaction) then return true end
	if not (C_TradeSkillUI and C_TradeSkillUI.GetEnchantItems and Item and Item.CreateFromItemGUID) then return false end
	local reagents
	if transaction.CreateCraftingReagentInfoTbl then
		local ok, tbl = pcall(transaction.CreateCraftingReagentInfoTbl, transaction)
		if ok then reagents = tbl end
	end
	local ok, guids = pcall(C_TradeSkillUI.GetEnchantItems, recipeID, reagents)
	if not ok or type(guids) ~= "table" then return false end
	local valid = {}
	for _, g in ipairs(guids) do valid[g] = true end
	local worn = EquippedGUIDs()
	for _, guid in ipairs(self:Targets()) do
		if valid[guid] and not worn[guid] then
			local item = Item:CreateFromItemGUID(guid)
			transaction:SetEnchantAllocation(item)
			if form.enchantSlot and form.enchantSlot.SetItem then pcall(form.enchantSlot.SetItem, form.enchantSlot, item) end
			local event = ProfessionsRecipeSchematicFormMixin and ProfessionsRecipeSchematicFormMixin.Event
			if form.TriggerEvent and event and event.AllocationsModified then
				pcall(form.TriggerEvent, form, event.AllocationsModified)
			end
			return true
		end
	end
	return false
end

local function BasicType() return (Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic) or 0 end

-- The first material you are short of for one craft: itemID, how many more, or nil (tools count: a rod is a slot).
function Craft:Missing(recipeID)
	if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic) then return nil end
	local ok, sch = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
	if not ok or type(sch) ~= "table" then return nil end
	for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
		if slot.reagentType == BasicType() and slot.required ~= false then
			local have, first = 0, nil
			for _, rg in ipairs(slot.reagents or {}) do
				if rg.itemID then
					first = first or rg.itemID
					have = have + ItemCount(rg.itemID)
				end
			end
			local need = slot.quantityRequired or 1
			if first and have < need then return first, need - have end
		end
	end
	return nil
end

-- How many crafts your bags cover (the client's own count), or nil.
function Craft:Available(recipeID)
	if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo) then return nil end
	local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
	return ok and type(info) == "table" and info.numAvailable or nil
end

local function Name(itemID)
	return (CPa.UI and CPa.UI.ItemName and CPa.UI.ItemName(itemID)) or ("item " .. tostring(itemID))
end

local function Where(npc)
	if not npc then return " at your trainer" end
	if npc.place and npc.place ~= "" then return string.format(" at %s (%s)", npc.name, npc.place) end
	return " at " .. tostring(npc.name)
end

local function PlayerLevel()
	local ok, l = pcall(function() return UnitLevel("player") end)
	return ok and type(l) == "number" and l or nil
end

-- What to do now. { kind, text, recipe, step, rank }:
--   none (no plan) | done | rank (train the next rank first) | level (the next rank needs a higher character level) |
--   gap / bags / noprice (no step, and why) | learn (the step's recipe is not learned) |
--   buy (short of a material for the next craft) | part (craft a part the step needs first) | craft
function Craft:Now(plan)
	plan = plan or (CPa.Model and CPa.Model.plan)
	if not plan then return { kind = "none", text = "Open the profession you want to level." } end
	if plan.target <= plan.skill then
		return { kind = "done", text = "Target reached. Raise the target to plan further." }
	end
	-- at the rank cap the next point needs the next rank, whatever the route says
	if (plan.maxSkill or 0) <= plan.skill then
		for _, rk in ipairs(plan.ranks or {}) do
			if rk.by <= plan.skill then
				local level = PlayerLevel()
				if level and rk.level and level < rk.level then
					return { kind = "level", rank = rk, text = string.format("Reach character level %d to train %s (skill stops at %d).",
						rk.level, rk.name, rk.by) }
				end
				return { kind = "rank", rank = rk, text = string.format("Train %s first%s%s.", rk.name, Where(rk.npc),
					rk.cost and (", " .. CPa:Money(rk.cost, { compact = true })) or "") }
			end
		end
	end
	local step = plan.result.steps[1]
	if not step then
		if plan.bagsOnly then
			return { kind = "bags", text = "Your bags make nothing that gives points. Untick \"Only mats in my bags\"." }
		elseif plan.result.gap then
			return { kind = "gap", text = string.format("No known recipe gives a point at %d. Hover \"Some data missing\".", plan.result.gap) }
		end
		return { kind = "noprice", text = "No prices yet: at the Auction House click CraftProfit Scan (bottom left)." }
	end
	local r = step.recipe
	-- a part the step crafts itself (Bolt of Linen Cloth for Linen Bag) comes first while short in the bags
	local band = step.variant or r
	local function Bought(itemID)
		for _, bo in ipairs(band.bonus or {}) do
			if bo.itemID == itemID and CPa.Solver.Bought(bo, plan.skill) then return true end
		end
		return false
	end
	for _, rg in ipairs(band.detail and band.detail.reagents or {}) do
		if rg.kind == "craft" and rg.maker and rg.itemID and ItemCount(rg.itemID) < (rg.qty or 1) and not Bought(rg.itemID) then
			-- enough of them in the bank: fetch them instead of making more
			local owned = (CPa.Model.OwnedCount and CPa.Model.OwnedCount(rg.itemID)) or 0
			if owned >= (rg.qty or 1) then
				return { kind = "bank", recipe = r, step = step, itemID = rg.itemID,
					text = string.format("Take %s from your bank (you have %d there) for %s.", Name(rg.itemID), owned - ItemCount(rg.itemID), tostring(r.name)) }
			end
			local mr = rg.maker.recipe
			if not mr.learned then
				return { kind = "learn", recipe = mr, step = step,
					text = string.format("Learn %s%s (skill %s) to make %s.", tostring(mr.name), Where(mr.npc), tostring(mr.learnAt or "?"), Name(rg.itemID)) }
			end
			return self:ShortOf(mr, step) or { kind = "part", recipe = mr, step = step, itemID = rg.itemID,
				text = string.format("Make %s first (for %s).", Name(rg.itemID), tostring(r.name)) }
		end
	end
	if not r.learned then
		return { kind = "learn", recipe = r, step = step,
			text = string.format("Learn %s%s (skill %s%s).", tostring(r.name), Where(r.npc), tostring(r.learnAt or "?"),
				(step.learnCost or 0) > 0 and (", " .. CPa:Money(step.learnCost, { compact = true })) or "") }
	end
	return self:ShortOf(r, step) or { kind = "craft", recipe = r, step = step,
		text = string.format("Craft %s, ~%d more (%d-%d).", tostring(r.name), math.ceil((step.crafts or 0) - 1e-9), step.from, step.to) }
end

-- "buy" when the bags are short of a material (or the tool) for the next craft of r
function Craft:ShortOf(r, step)
	local short, count = self:Missing(r.id)
	if not short then return nil end
	if CPa.Data.tools[short] then
		return { kind = "buy", recipe = r, step = step, itemID = short,
			text = string.format("Get a %s for %s: a tool, kept. Make it yourself or buy it.", Name(short), tostring(r.name)) }
	end
	return { kind = "buy", recipe = r, step = step, itemID = short, count = count,
		text = string.format("You need %d more %s for %s: Shopping list > Buy next.", count, Name(short), tostring(r.name)) }
end

-- A bag item the enchant accepts (its link), to name in the "fill the slot" message.
function Craft:FittingItem(transaction, recipeID)
	if not (C_TradeSkillUI and C_TradeSkillUI.GetEnchantItems and C_Item and C_Item.GetItemLinkByGUID) then return nil end
	local reagents
	if transaction and transaction.CreateCraftingReagentInfoTbl then
		local ok, tbl = pcall(transaction.CreateCraftingReagentInfoTbl, transaction)
		if ok then reagents = tbl end
	end
	local ok, guids = pcall(C_TradeSkillUI.GetEnchantItems, recipeID, reagents)
	if not ok or type(guids) ~= "table" then return nil end
	local worn = EquippedGUIDs()
	for _, g in ipairs(guids) do
		if not worn[g] then
			local okL, link = pcall(C_Item.GetItemLinkByGUID, g)
			if okL and link then return link end
		end
	end
	return nil
end

-- "Get mats first": open the Shopping list tab (the window too); at the Auction House press Buy next as well.
function Craft:GoShopping()
	local UI = CPa.UI
	if UI then
		if not UI:IsShown() then UI:Open() end
		if UI.view ~= "shop" then UI:SetView("shop") end
	end
	if CPa.Shop and CPa.Shop:AtAuctionHouse() and UI and UI.plan then
		CPa.Shop:BuyNext((UI:ShopList(UI.plan)))
	elseif CPa.Shop and CPa.Shop:AtMerchant() and UI and UI.plan then
		Say("CraftPath: Shopping list open. Press Buy vendor mats for what this merchant sells.")
	else
		Say("CraftPath: Shopping list open. At the Auction House press Buy next; at a trade goods vendor, Buy vendor mats.")
	end
end

-- The route step for the current skill, or nil.
function Craft:CurrentStep()
	local plan = CPa.Model and CPa.Model.plan
	if not plan or plan.target <= plan.skill then return nil, plan end
	return plan.result.steps[1], plan
end

-- How many Craft all makes now: what the current step still needs (its expected crafts, or for a part the ones
-- the step uses minus those you own), capped by what your bags cover. 0 when Craft all does not apply.
function Craft:BatchCount(now, plan)
	now = now or self:Now(plan)
	if not (now.recipe and now.step and (now.kind == "craft" or now.kind == "part")) then return 0 end
	local want
	if now.kind == "part" then
		want = 0
		for _, it in ipairs(now.step.inter or {}) do
			if it.itemID == now.itemID then want = want + math.ceil((it.crafts or 0) - 1e-9) end
		end
		local owned = (CPa.Model.OwnedCount and CPa.Model.OwnedCount(now.itemID)) or ItemCount(now.itemID)
		want = math.max(1, want - owned)
	else
		want = math.max(1, math.ceil((now.step.crafts or 1) - 1e-9))
	end
	local avail = self:Available(now.recipe.id)
	local page = Page()
	if page and page.GetCraftableCount and page.SchematicForm and SelectedRecipeID(page.SchematicForm) == now.recipe.id then
		local ok, n = pcall(page.GetCraftableCount, page)
		if ok and type(n) == "number" then avail = n end
	end
	if not avail then return want end
	return math.max(0, math.min(want, avail))
end

function Craft:CraftAll() return self:CraftNext(true) end

function Craft:CraftNext(all)
	if UnitCastingInfo and UnitCastingInfo("player") then return end -- still casting the last one: nothing to do
	-- a skill-up, another profession or a new target since the last build: plan again first
	local plan = CPa.Model and CPa.Model.EnsureFresh and CPa.Model:EnsureFresh() or (CPa.Model and CPa.Model.plan)
	-- a linked / guild / NPC crafting view, or no profession open: never craft from another profession's plan
	local open = CPa.Model and CPa.Model.OpenProfession and CPa.Model:OpenProfession()
	if plan and not (open and open.key == plan.key) then
		Say("CraftPath: open the " .. tostring(plan.prof) .. " profession window to craft.")
		return
	end
	local now = self:Now(plan)
	if now.kind == "buy" then
		-- short of materials: the button takes you to them (Buy next at the AH, else the Shopping list tab)
		self:GoShopping()
		return
	end
	if now.kind ~= "craft" and now.kind ~= "part" then
		Say("CraftPath: " .. now.text)
		return
	end
	local r = now.recipe
	local page = Page()
	local form = page and page.SchematicForm
	if not (ProfessionsFrame and ProfessionsFrame:IsShown() and form and page.CreateInternal) then
		Say("CraftPath: open the profession window to craft.")
		return
	end
	if UnitCastingInfo and UnitCastingInfo("player") then return end -- still casting the last one
	if InCombatLockdown and InCombatLockdown() then
		Say("CraftPath: not in combat.")
		return
	end
	local short, count = self:Missing(r.id)
	if short then
		Say(string.format("CraftPath: you need %d more %s for %s%s.", count, Name(short), tostring(r.name),
			CPa.Data.tools[short] and " (a tool, kept)" or " (Shopping list tab)"))
		return
	end
	for _, req in ipairs((CPa.Model.Requirements and CPa.Model.Requirements(r.id)) or {}) do
		if not req.met then
			Say(string.format("CraftPath: %s needs %s.", tostring(r.name), tostring(req.name)))
			return
		end
	end
	self:HookPage()

	if SelectedRecipeID(form) ~= r.id then
		-- keep the item you were enchanting so it can go into the new recipe's slot
		local okT, oldTransaction = pcall(function() return form:GetTransaction() end)
		if okT then self:Remember(AllocationGUID(oldTransaction)) end
		if not self:Select(r.id) or SelectedRecipeID(form) ~= r.id then
			Say("CraftPath: could not select " .. tostring(r.name) .. " (clear the profession window's search box).")
			return
		end
	end

	local okT, transaction = pcall(function() return form:GetTransaction() end)
	if not okT or not transaction then return end
	if IsEnchant(form) and not self:FillTarget(form, transaction, r.id) then
		local example = self:FittingItem(transaction, r.id)
		Say("CraftPath: put an item from your bags in the recipe's target slot once" .. (example and (" (e.g. " .. example .. ")") or "")
			.. ", then press Craft next again.")
		return
	end
	local level
	if form.GetCurrentRecipeLevel then
		local okL, l = pcall(form.GetCurrentRecipeLevel, form)
		if okL then level = l end
	end
	self.lastCraft = GetTime and GetTime() or 0
	local count = 1
	if all then
		count = self:BatchCount(now, plan)
		if count < 1 then
			Say("CraftPath: your bags cover none of " .. tostring(r.name) .. " yet.")
			return
		end
		-- the replace popup of an enchant batch is answered for its whole length
		self.batchUntil = self.lastCraft + count * 4 + 5
		CPa:Print("crafting %d %s (what this step needs; your bags cover it).", count, tostring(r.name))
	end
	local ok, err = pcall(page.CreateInternal, page, r.id, count, level)
	if not ok then CPa:Print("craft failed: %s", tostring(err)) end
end

---------------------------------------------------------------------------
-- "Next up" notice when the route's current recipe changes after a skill-up
---------------------------------------------------------------------------

Craft.greeted = {}
CPa:On("PLAN_UPDATED", function(plan)
	local now = Craft:Now(plan)
	local id = now.recipe and now.recipe.id or (now.rank and now.rank.name) or now.kind
	local last = Craft.last
	Craft.last = { prof = plan and plan.key, skill = plan and plan.skill, id = id }
	-- the first plan of a session for a profession: one chat line with where you are and what is next
	if plan and plan.key and not Craft.greeted[plan.key] then
		Craft.greeted[plan.key] = true
		if plan.target > plan.skill then
			CPa:Print("%s %d/%d, target %d. Now: %s", tostring(plan.prof), plan.skill, plan.maxSkill or plan.skill, plan.target, now.text)
		end
		return
	end
	if not (last and plan and last.prof == plan.key and last.id ~= id and plan.skill > (last.skill or 0)) then return end
	if now.kind == "craft" or now.kind == "learn" or now.kind == "rank" or now.kind == "done" then
		Notice("CraftPath: " .. now.text)
		if PlaySound and SOUNDKIT and SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01 then pcall(PlaySound, SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01) end
	end
end)

CPa:RegisterEvent("TRADE_SKILL_SHOW", function() Craft:HookPage() end)
