-- CraftPath :: Report
-- /cpath report: everything the route was chosen from, as plain text in a copy window (Ctrl+A, Ctrl+C):
-- the route, every candidate recipe (source, colour levels, cost per craft, reagents with their price and whether
-- it is bought or crafted), the recipes left out and every reagent's buy price against its craft price.

local _, CPa = ...
local Report = {}
CPa.Report = Report

local function Name(itemID)
	if CPa.UI and CPa.UI.ItemName then return CPa.UI.ItemName(itemID) end
	return "item " .. tostring(itemID)
end

-- Plain copper text: links and coin icons do not survive a copy.
local function C(copper)
	if not copper then return "-" end
	copper = math.floor(copper + 0.5)
	local neg = copper < 0
	copper = math.abs(copper)
	local g, s, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
	local t = (g > 0 and (g .. "g") or "") .. ((g > 0 or s > 0) and (s .. "s") or "") .. c .. "c"
	return (neg and "-" or "") .. t
end
Report.Copper = C

local function Thresholds(th)
	local function k(v, known) return tostring(v) .. (known and "" or "*") end
	return string.format("y%s g%s x%s", k(th.yellow, th.yellowKnown), k(th.green, th.greenKnown), k(th.gray, th.grayKnown))
end

function Report:Build(plan)
	plan = plan or (CPa.Model and CPa.Model.plan)
	local out = {}
	local function L(fmt, ...) out[#out + 1] = select("#", ...) > 0 and string.format(fmt, ...) or fmt end
	if not plan then
		L("CraftPath report: no plan (open a profession window first)")
		return table.concat(out, "\n")
	end
	local res = plan.result
	L("CraftPath %s report · %s %d -> %d (max %s) · outputs %s · bags only %s · %s", tostring(CPa.version), plan.prof,
		plan.skill, plan.target, tostring(plan.maxSkill), tostring(CPa:Setting("outputs")), tostring(plan.bagsOnly),
		date and date("%Y-%m-%d %H:%M") or "")
	local stepTraining = 0
	for _, st in ipairs(res.steps) do stepTraining = stepTraining + (st.learnCost or 0) end
	L("total %s · crafts %.1f · training %s (+ reagent recipes %s) · reached %s%s", C(res.total), res.crafts or 0,
		C(stepTraining), C(res.extraTraining or 0), tostring(res.reached), res.gap and (" · gap at " .. res.gap) or "")

	L("== ranks to train (%d)", #(plan.ranks or {}))
	for _, rk in ipairs(plan.ranks or {}) do
		L("  %s | before %d | skill %d, level %d | %s | %s", rk.name, rk.by, rk.at, rk.level, rk.cost and C(rk.cost) or "price ?",
			rk.npc and rk.npc.name or "trainer not recorded")
	end
	L("== route (%d steps)", #res.steps)
	L("  from-to | recipe | crafts | cost | training | per craft")
	for _, st in ipairs(res.steps) do
		local bonus = {}
		if st.forLater then bonus[#bonus + 1] = string.format("keeps %.0f for %s", st.forLater.crafts, st.forLater.usedBy) end
		for _, it in ipairs(st.inter or {}) do
			bonus[#bonus + 1] = string.format("%.0f x %s first (%.1f points)", it.crafts, tostring(it.recipe.name), it.points)
		end
		L("  %d-%d | %s %s | %.1f | %s | %s | %s%s", st.from, st.to, tostring(st.recipe.name), tostring(st.recipe.id),
			st.crafts, C(st.cost), C(st.learnCost), C(CPa.Solver.V(st.recipe, st.from).cost), #bonus > 0 and (" | crafts " .. table.concat(bonus, ", ")) or "")
	end

	local list = {}
	for _, r in ipairs(plan.recipes or {}) do list[#list + 1] = r end
	table.sort(list, function(a, b) return (a.th.yellow or 0) < (b.th.yellow or 0) end)
	L("== candidates (%d) · y/g/x = yellow/green/gray, * = estimated", #list)
	L("  id | name | source | levels | per craft (reagents - worth) | reagents")
	for _, r in ipairs(list) do
		local d = r.detail or {}
		local parts = {}
		for _, rg in ipairs(d.reagents or {}) do
			parts[#parts + 1] = string.format("%dx %s @%s %s", rg.qty, Name(rg.itemID), C(rg.unit), tostring(rg.kind))
		end
		for _, tool in ipairs(d.tools or {}) do parts[#parts + 1] = "tool " .. Name(tool.itemID) .. (tool.have and "" or " MISSING") end
		local source = r.learned and "known" or string.format("learn %s %s %s", tostring(r.learnAt), C(r.learnCost), r.npc and r.npc.name or "")
		L("  %s | %s | %s | %s | %s (%s - %s) | %s", tostring(r.id), tostring(r.name), source, Thresholds(r.th), C(r.cost),
			C(d.reagentCost), C(d.worth), table.concat(parts, "; "))
	end

	L("== bought, recipe not recorded at a trainer (%d)", #(plan.unsourced or {}))
	for _, un in ipairs(plan.unsourced or {}) do L("  %s %d | recipe %d", un.name, un.itemID, un.recipeID) end
	L("== crafting not checked: a reagent of the craft has no price (%d)", #(plan.unchecked or {}))
	for _, u in ipairs(plan.unchecked or {}) do
		local names = {}
		for _, id in ipairs(u.missing) do names[#names + 1] = Name(id) .. " " .. tostring(id) end
		L("  %s %d bought; %s needs %s", Name(u.itemID), u.itemID, tostring(u.maker.recipe.name), table.concat(names, ", "))
	end

	L("== left out: a reagent has no price (%d)", #(plan.unpriced or {}))
	for _, r in ipairs(plan.unpriced or {}) do
		local names = {}
		for _, id in ipairs(r.detail and r.detail.missing or {}) do names[#names + 1] = Name(id) .. " " .. tostring(id) end
		L("  %s %s | %s", tostring(r.id), tostring(r.name), table.concat(names, ", "))
	end

	-- every reagent seen, buy against craft
	local items, order = {}, {}
	for _, r in ipairs(plan.recipes or {}) do
		for _, rg in ipairs(r.detail and r.detail.reagents or {}) do
			if rg.itemID and not items[rg.itemID] then items[rg.itemID] = true; order[#order + 1] = rg.itemID end
		end
	end
	table.sort(order)
	L("== reagent prices (%d) · buy = CraftProfit AH/vendor, used = what the route paid", #order)
	L("  item | buy | used | made by (recipes you know or can train now)")
	local buyFn = CPa.Model.BuyPrice
	for _, id in ipairs(order) do
		local buy, kind = nil, nil
		if buyFn then buy, kind = buyFn(id) end
		local used, usedKind = nil, nil
		if plan.pricer then used, usedKind = plan.pricer.Unit(id) end
		local makers = {}
		for _, mk in ipairs(plan.makers and plan.makers[id] or {}) do
			local mats = {}
			for _, slot in ipairs(mk.schematic and mk.schematic.reagentSlotSchematics or {}) do
				local rg = slot.reagents and slot.reagents[1]
				if rg and rg.itemID then
					local u = plan.pricer and plan.pricer.Unit(rg.itemID)
					mats[#mats + 1] = string.format("%dx %s @%s", slot.quantityRequired or 1, Name(rg.itemID), C(u))
				end
			end
			makers[#makers + 1] = tostring(mk.recipe.name) .. (mk.recipe.learned and "" or (" (learn " .. C(mk.recipe.learnCost) .. ")"))
				.. (#mats > 0 and (" from " .. table.concat(mats, ", ")) or "")
				.. ((plan.banned and plan.banned[mk.recipe.id]) and " dropped: saves less than its training" or "")
		end
		L("  %s %d | %s %s | %s %s | %s", Name(id), id, C(buy), tostring(kind or ""), C(used), tostring(usedKind or ""),
			#makers > 0 and table.concat(makers, ", ") or "-")
	end
	return table.concat(out, "\n"), #out
end

local function CreateWindow()
	local f
	for _, template in ipairs({ "BasicFrameTemplateWithInset", "ButtonFrameTemplate" }) do
		local ok, frame = pcall(CreateFrame, "Frame", "CraftPathReport", UIParent, template)
		if ok and frame then f = frame break end
	end
	f = f or CreateFrame("Frame", "CraftPathReport", UIParent)
	f:SetSize(640, 460)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOP", f, "TOP", 0, -5)
	title:SetText("CraftPath report: Ctrl+A, Ctrl+C")
	local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -30)
	scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 12)
	local box = CreateFrame("EditBox", nil, scroll)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetFontObject(ChatFontNormal)
	box:SetWidth(590)
	box:SetMaxLetters(0)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
	-- typing would only spoil the paste
	box:SetScript("OnTextChanged", function(self, user) if user then self:SetText(f.text or ""); self:HighlightText() end end)
	scroll:SetScrollChild(box)
	f.box = box
	if UISpecialFrames then table.insert(UISpecialFrames, "CraftPathReport") end
	return f
end

function Report:Show()
	if CPa.Model and CPa.UI and CPa.Model.OpenProfession and CPa.Model:OpenProfession() then CPa.Model:Build() end
	local text, lines = self:Build()
	self.frame = self.frame or CreateWindow()
	self.frame.text = text
	self.frame.box:SetText(text)
	self.frame:Show()
	self.frame.box:SetFocus()
	self.frame.box:HighlightText()
	CPa:Print("report ready (%d lines): Ctrl+A, Ctrl+C in the window.", lines or 0)
	return text
end
