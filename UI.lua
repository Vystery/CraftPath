-- CraftPath :: UI
-- The route window, default UI parts only (PortraitFrameTemplate, InsetFrameTemplate, panel tabs, Blizzard fonts):
--   header   target skill box, "outputs count at" button, summary (skill range, total, crafts)
--   bar      one slice per skill point coloured by the chance of a point there (orange / yellow / green, like the
--            recipe list), step borders, recipe icons, start / step / target labels; hover a slice for its step
--   Route    one row per step: recipe, skill range, expected crafts, cost, where to train it
--   Shopping materials for this step / the next 25 points / the whole route, with what you own (bags + bank),
--            what is still needed, and Buy next (AH) / Buy vendor mats (merchant)
--   footer   the Now line (what to do this minute, from Craft:Now) and the Craft next button

local _, CPa = ...
local UI = {}
CPa.UI = UI

local NAME = "CraftPathFrame"
local WIDTH, HEIGHT = 600, 540
local PAD = 16
local BAR_TOP, BAR_H = -104, 22
local LIST_TOP = -176
local CHECK_Y = -144
local LIST_BOTTOM = 30
local ROW_H = 40
local SHOPBAR_H = 28
-- as many rows as the list area holds (4px inset at the top, 4 at the bottom), so none hangs over the border
local ROWS = math.floor((HEIGHT + LIST_TOP - LIST_BOTTOM - 8) / ROW_H)
UI.ROWS, UI.ROW_H, UI.LIST_H = ROWS, ROW_H, HEIGHT + LIST_TOP - LIST_BOTTOM
local ICON_SIZE = 16
-- the game font has no arrow glyph (U+2192 shows as a box), so ranges use a hyphen; the middle dot works
local DOT = " \194\183 "

local C = {
	gold = "ffd100", white = "ffffff", muted = "8a7d64", label = "c8b78a", loss = "ff5b4b", good = "4cd137",
}

local function Text(parent, font, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	if justify then fs:SetJustifyH(justify) end
	if fs.SetWordWrap then fs:SetWordWrap(false) end
	return fs
end

local function Money(copper, opts) return CPa:Money(copper, opts) end
local function Col(hex, text) return CPa:Color(hex, text) end
local C_GOOD = "4cd137"
-- a cost below zero is a profit (crafts that sell to a vendor for more than their mats): "+44s" in green
local function Net(copper)
	if copper and copper < -0.5 then return CPa:Color(C_GOOD, "+" .. CPa:Money(-copper, { compact = true })) end
	return CPa:Money(copper or 0, { compact = true })
end

-- Item names the client has not loaded yet are asked for; the window redraws once they arrive.
local function ItemName(itemID)
	local name
	if C_Item and C_Item.GetItemNameByID then
		local ok, n = pcall(C_Item.GetItemNameByID, itemID)
		if ok then name = n end
	end
	if not name and itemID and C_Item and C_Item.RequestLoadItemDataByID then
		pcall(C_Item.RequestLoadItemDataByID, itemID)
		UI.waitingItems = true
	end
	return name or ("item " .. tostring(itemID))
end
UI.ItemName = ItemName

local function ItemIcon(itemID)
	if C_Item and C_Item.GetItemIconByID then
		local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
		if ok then return icon end
	end
	return nil
end

local function PlaySoundKit(name)
	if PlaySound and SOUNDKIT and SOUNDKIT[name] then pcall(PlaySound, SOUNDKIT[name]) end
end

local function Crafts(n)
	if n >= 9.5 then return string.format("~%d crafts", math.floor(n + 0.5)) end
	return (string.format("~%.1f crafts", n):gsub("%.0 ", " "))
end

-- chance -> colour index like the recipe list: 1 orange, >= 0.5 yellow, below green
local function ChanceColour(p)
	if p >= 0.999 then return 0 end
	if p >= 0.5 then return 1 end
	return 2
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function CreateTabs(f)
	local specs = { { "route", "Route" }, { "shop", "Shopping list" } }
	local panelTabs = PanelTemplates_SetNumTabs and PanelTemplates_SetTab and true or false
	local tabs = {}
	for i, spec in ipairs(specs) do
		local tab
		if panelTabs then
			local ok, t = pcall(CreateFrame, "Button", NAME .. "Tab" .. i, f, "PanelTabButtonTemplate")
			if ok and t then tab = t end
		end
		if not tab then
			tab = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
			tab:SetSize(110, 22)
			panelTabs = false
		end
		tab:SetID(i)
		tab:SetText(spec[2])
		tab.view = spec[1]
		tab:SetScript("OnClick", function(self)
			PlaySoundKit("IG_CHARACTER_INFO_TAB")
			UI:SetView(self.view)
		end)
		if i == 1 then
			tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, panelTabs and 2 or -2)
		else
			tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", panelTabs and -15 or 4, 0)
		end
		if panelTabs and PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 0) end
		tabs[i] = tab
	end
	if panelTabs then
		f.numTabs = #tabs
		pcall(PanelTemplates_SetNumTabs, f, #tabs)
	end
	f.panelTabs = panelTabs
	return tabs
end

local function CreateRow(parent, i)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -4 - (i - 1) * ROW_H)
	row:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.08)
	row.Stripe = row:CreateTexture(nil, "BACKGROUND")
	row.Stripe:SetAllPoints()
	row.Stripe:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0)
	row.Band = row:CreateTexture(nil, "ARTWORK")
	row.Band:SetSize(4, ROW_H - 8)
	row.Band:SetPoint("LEFT", row, "LEFT", 2, 0)
	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(32, 32)
	row.Icon:SetPoint("LEFT", row, "LEFT", 10, 0)
	row.Num = Text(row, "GameFontNormalSmall", "CENTER")
	row.Num:SetPoint("BOTTOMRIGHT", row.Icon, "BOTTOMRIGHT", 2, -2)
	-- white name, so the gold "Learn:" stands out
	row.Name = Text(row, "GameFontHighlight", "LEFT")
	row.Name:SetPoint("TOPLEFT", row.Icon, "TOPRIGHT", 8, 0)
	row.Sub = Text(row, "GameFontHighlightSmall", "LEFT")
	row.Sub:SetPoint("BOTTOMLEFT", row.Icon, "BOTTOMRIGHT", 8, 0)
	row.Value = Text(row, "GameFontHighlight", "RIGHT")
	row.Value:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -6)
	row.Note = Text(row, "GameFontDisableSmall", "RIGHT")
	row.Note:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 6)
	row.Name:SetPoint("RIGHT", row.Value, "LEFT", -8, 0)
	row.Sub:SetPoint("RIGHT", row.Note, "LEFT", -8, 0)
	row:SetScript("OnEnter", function(self) UI:RowTooltip(self) end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:SetScript("OnClick", function(self) UI:RowClick(self) end)
	return row
end

-- A step split into what you craft in order: first the intermediates whose crafts give points (Bolts of Linen
-- Cloth, crafted first, so they take the first ~24 points), then the step's own recipe for the rest.
-- { { st, it = intermediate or nil, from, to }, ... }
-- Points that `crafts` crafts give when made one after another from skill `from` (the chance falls as the skill
-- rises: orange, then yellow, then green), stopping at `cap`. Returns the points and the crafts that go unused.
local function SimPoints(th, from, crafts, cap)
	local s, left = from, crafts
	while left > 1e-9 and s < cap do
		local p = CPa.Solver.Chance(th, s)
		if p <= 0 then break end
		local need = 1 / p
		if left < need then
			if left >= need / 2 then s = s + 1 end
			left = 0
			break
		end
		left = left - need
		s = s + 1
	end
	return s - from, left
end
UI.SimPoints = SimPoints

-- How Craft next and Craft all actually go: all the parts a step makes itself (Bolts of Linen Cloth for Linen
-- Bags) first, minus the ones you already own, then the step's own recipe. Each part covers the points its crafts
-- give in that order, so the bar is used up from the left as you craft. { { st, it = part or nil, from, to,
-- crafts = still to make }, ... }
local function Parts(st)
	local out, cursor = {}, st.from
	local keepOwn = (st.own or 0) >= 0.5 and 1 or 0
	local earlier = UI.plan and UI.plan.result and UI.plan.result.madeEarlier
	for _, it in ipairs(st.inter or {}) do
		local th = it.recipe and it.recipe.th
		local madeBefore = earlier and it.itemID and earlier[it.itemID] and earlier[it.itemID] ~= st
		if th and (it.crafts or 0) > 0 and not madeBefore then
			local owned = (it.itemID and CPa.Model.OwnedCount and CPa.Model.OwnedCount(it.itemID)) or 0
			local left = math.max(0, it.crafts - owned)
			local len = left >= 0.5 and SimPoints(th, cursor, left, st.to - keepOwn) or 0
			if len >= 1 then
				out[#out + 1] = { st = st, it = it, from = cursor, to = cursor + len, crafts = left }
				cursor = cursor + len
			end
		end
	end
	if cursor < st.to then out[#out + 1] = { st = st, from = cursor, to = st.to } end
	return out
end
UI.Parts = Parts

local function CreateBar(f)
	local bar = CreateFrame("Frame", nil, f)
	bar:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 6, BAR_TOP)
	bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD - 6, BAR_TOP)
	bar:SetHeight(BAR_H)
	local ok, border = pcall(CreateFrame, "Frame", nil, bar, "InsetFrameTemplate")
	if ok and border then
		border:SetPoint("TOPLEFT", bar, "TOPLEFT", -4, 4)
		border:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 4, -4)
		border:SetFrameLevel(bar:GetFrameLevel())
	end
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetColorTexture(0, 0, 0, 0.5)
	bar.slices, bar.dividers, bar.icons, bar.labels = {}, {}, {}, {}
	-- the step under the mouse, lightened
	bar.hl = bar:CreateTexture(nil, "OVERLAY")
	bar.hl:SetColorTexture(1, 1, 1, 0.18)
	bar.hl:Hide()
	bar:EnableMouse(true)
	-- the tooltip follows the skill under the cursor; leaving forgets it, so coming back always shows it again
	local function Forget(self)
		self.hoverSkill = nil
		self.hl:Hide()
		if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end
	local Update
	-- the hover code runs only while the mouse is over the bar
	bar:SetScript("OnEnter", function(self) self:SetScript("OnUpdate", Update) end)
	bar:SetScript("OnLeave", function(self) Forget(self); self:SetScript("OnUpdate", nil) end)
	bar:SetScript("OnHide", function(self) Forget(self); self:SetScript("OnUpdate", nil) end)
	Update = function(self)
		local plan = UI.plan
		if not (self:IsMouseOver() and UI.barSteps and plan and self.span and self.span > 0) then
			if self.hoverSkill then Forget(self) end
			return
		end
		local x = (GetCursorPosition and select(1, GetCursorPosition()) or 0) / (self:GetEffectiveScale() or 1)
		local width = self:GetWidth() or 0
		if width <= 0 then return end
		local unit = width / self.span
		local origin = plan.start or plan.skill
		local skill = origin + math.floor((x - (self:GetLeft() or 0)) / unit)
		if skill == self.hoverSkill and GameTooltip:IsOwned(self) then return end
		self.hoverSkill = skill
		if skill < plan.skill then
			-- the part already done since the target was set
			self.hl:ClearAllPoints()
			self.hl:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
			self.hl:SetSize((math.min(plan.skill, plan.target) - origin) * unit, BAR_H)
			self.hl:Show()
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:AddLine("Done")
			GameTooltip:AddLine(string.format("%d - %d since you set the target, %d to go", origin, plan.skill,
				math.max(0, plan.target - plan.skill)), 1, 1, 1)
			GameTooltip:Show()
			return
		end
		local seg
		for _, sg in ipairs(UI.barSteps) do
			if skill >= sg.from and skill < sg.to then seg = sg end
		end
		if not seg then
			self.hl:Hide()
			if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
			return
		end
		self.hl:ClearAllPoints()
		self.hl:SetPoint("TOPLEFT", self, "TOPLEFT", (seg.from - origin) * unit, 0)
		self.hl:SetSize((seg.to - seg.from) * unit, BAR_H)
		self.hl:Show()
		if seg.it then UI:InterTooltip(self, seg.st, seg.it, skill, seg) else UI:StepTooltip(self, seg.st, skill, seg) end
	end
	bar.Update = Update
	return bar
end

local function CreateWindow()
	local f
	for _, template in ipairs({ "PortraitFrameTemplate", "ButtonFrameTemplate", "BasicFrameTemplateWithInset" }) do
		local ok, frame = pcall(CreateFrame, "Frame", NAME, UIParent, template)
		if ok and frame then f = frame break end
	end
	if not f then
		f = CreateFrame("Frame", NAME, UIParent)
		f.TitleText = Text(f, "GameFontNormal", "CENTER")
		f.TitleText:SetPoint("TOP", 0, -8)
		f.CloseButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
		f.CloseButton:SetPoint("TOPRIGHT", -4, -4)
	end
	if f.Inset and f.Inset.Hide then f.Inset:Hide() end
	f:SetSize(WIDTH, HEIGHT)
	f:SetPoint("CENTER")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		if CPa.db then CPa.db.pos = { point, relPoint, x, y } end
	end)
	-- MEDIUM like the profession window, raised on click; it opens beside that window (UI:Open), not over it
	f:SetFrameStrata("MEDIUM")
	if f.SetToplevel then f:SetToplevel(true) end
	f:Hide()
	f:SetScript("OnShow", function() PlaySoundKit("IG_CHARACTER_INFO_OPEN") end)
	f:SetScript("OnHide", function() PlaySoundKit("IG_CHARACTER_INFO_CLOSE") end)
	local portrait = (f.PortraitContainer and f.PortraitContainer.portrait) or f.portrait
	f.portraitTex = portrait
	local x0 = portrait and 64 or PAD
	if UISpecialFrames then table.insert(UISpecialFrames, NAME) end

	-- toolbar: Target [200]   Outputs count at: [Vendor price]
	f.TargetLabel = Text(f, "GameFontNormal", "LEFT")
	f.TargetLabel:SetPoint("TOPLEFT", f, "TOPLEFT", x0, -34)
	f.TargetLabel:SetText("Target skill")
	local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	box:SetSize(44, 20)
	box:SetPoint("LEFT", f.TargetLabel, "RIGHT", 10, 0)
	box:SetAutoFocus(false)
	box:SetNumeric(true)
	box:SetMaxLetters(3)
	box:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		local n = tonumber(self:GetText())
		local plan = UI.plan
		if n and plan then CPa:SetTarget(plan.key or plan.prof, n, plan.skill) end
	end)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); UI:Refresh() end)
	f.TargetBox = box

	-- Pace and Made items: the default UI's dropdown (WowStyle1DropdownTemplate with radio entries, the same as
	-- CraftShuffle's pickers); a panel button that steps through the choices on clients without it
	local function Dropdown(key, width, choices, tipTitle, tipText)
		local function Current() return CPa:Setting(key) or choices[1][1] end
		local function Build(_, root)
			for _, c in ipairs(choices) do
				root:CreateRadio(c[2], function() return Current() == c[1] end, function() CPa:SetSetting(key, c[1]) end)
			end
		end
		local ok, dd = pcall(CreateFrame, "DropdownButton", nil, f, "WowStyle1DropdownTemplate")
		local w
		if ok and dd and type(dd.SetupMenu) == "function" then
			w = dd
			w:SetSize(width, 22)
			pcall(w.SetupMenu, w, Build)
			w.isDropdown = true
		else
			w = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
			w:SetSize(width, 22)
			w:SetScript("OnClick", function()
				for n, c in ipairs(choices) do
					if c[1] == Current() then CPa:SetSetting(key, choices[n % #choices + 1][1]) return end
				end
				CPa:SetSetting(key, choices[1][1])
			end)
		end
		w.cpBuild, w.cpChoices, w.cpKey = Build, choices, key
		local function Tip(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(tipTitle)
			GameTooltip:AddLine(tipText, 1, 1, 1, true)
			GameTooltip:Show()
		end
		if w.HookScript then w:HookScript("OnEnter", Tip); w:HookScript("OnLeave", function() GameTooltip:Hide() end)
		else w:SetScript("OnEnter", Tip); w:SetScript("OnLeave", function() GameTooltip:Hide() end) end
		-- the shown text: the dropdown shows the picked radio; the fallback button gets it from Refresh
		function w:CPRefresh()
			if self.isDropdown then
				if self.GenerateMenu then pcall(self.GenerateMenu, self) end
			else
				for _, c in ipairs(choices) do if c[1] == Current() then self:SetText(c[2]) end end
			end
		end
		return w
	end

	f.OutputsLabel = Text(f, "GameFontNormalSmall", "RIGHT")
	f.OutputsButton = Dropdown("outputs", 120, { { "vendor", "Vendor price" }, { "ah", "AH price" }, { "none", "Worth 0" } },
		"What the items you make are worth",
		"Taken off the cost of each craft. Vendor price is the safe choice; AH price if you will sell them; worth 0 to ignore it. Enchants make no item, so for enchanting this only changes wands, rods and oils.")
	f.OutputsButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -32)
	f.OutputsLabel:SetPoint("RIGHT", f.OutputsButton, "LEFT", -4, 0)
	f.OutputsLabel:SetText("Made items")

	f.PaceLabel = Text(f, "GameFontNormalSmall", "LEFT")
	f.PaceLabel:SetPoint("LEFT", box, "RIGHT", 14, 0)
	f.PaceLabel:SetText("Pace")
	f.PaceButton = Dropdown("pace", 104, { { "cheapest", "Cheapest" }, { "balanced", "Balanced" }, { "fastest", "Fastest" } },
		"Pace",
		"Cheapest: gold only. Balanced: a craft is worth 50c of your time, so orange and yellow recipes win over green ones that are only a little cheaper. Fastest: fewest crafts.")
	f.PaceButton:SetPoint("LEFT", f.PaceLabel, "RIGHT", 4, 0)

	-- "?": what CraftPath does and how to use it, always one hover away
	f.HelpButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.HelpButton:SetSize(24, 22)
	f.HelpButton:SetPoint("RIGHT", f.OutputsLabel, "LEFT", -8, 0)
	f.HelpButton:SetText("?")
	f.HelpButton:SetScript("OnEnter", function(self) UI:HelpTooltip(self) end)
	f.HelpButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.HelpButton:SetScript("OnClick", function(self) UI:HelpTooltip(self) end)

	f.Range = Text(f, "GameFontHighlightLarge", "LEFT")
	f.Range:SetPoint("TOPLEFT", f, "TOPLEFT", x0, -64)
	f.Total = Text(f, "GameFontHighlightLarge", "RIGHT")
	f.Total:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -64)
	f.Summary = Text(f, "GameFontHighlightSmall", "LEFT")
	f.Summary:SetPoint("TOPLEFT", f.Range, "BOTTOMLEFT", 0, -4)
	f.Summary:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)

	f.Bar = CreateBar(f)

	-- options under the bar
	local function Check(key, label, tip, x)
		local ok, cb = pcall(CreateFrame, "CheckButton", nil, f, "UICheckButtonTemplate")
		if not ok or not cb then return nil end
		cb:SetSize(24, 24)
		cb:SetPoint("TOPLEFT", f, "TOPLEFT", x, CHECK_Y)
		cb.label = Text(cb, "GameFontHighlightSmall", "LEFT")
		cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
		cb.label:SetText(label)
		cb:SetScript("OnClick", function(self) CPa:SetSetting(key, self:GetChecked() and true or false) end)
		cb:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(label)
			GameTooltip:AddLine(tip, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
		cb.key = key
		return cb
	end
	f.BagsCheck = Check("bagsOnly", "Only mats in my bags",
		"Plan with what you carry: nothing is bought, only training costs gold. Shows how far your bags get you.",
		PAD)
	f.CraftCheck = Check("craftReagents", "Craft reagents",
		"Ticked: you make parts like Bolts of Linen Cloth when that is cheaper. Unticked: you buy them where making them gives no points (faster, more gold).",
		PAD + 175)
	f.ReplaceCheck = Check("autoReplace", "Skip replace popup",
		"Answers yes to \"Do you want to replace this enchant?\" for enchants you cast from the profession window, so you can enchant one bag item over and over. Craft next never uses equipped items.",
		PAD + 290)

	local area = CreateFrame("Frame", nil, f)
	area:SetPoint("TOPLEFT", f, "TOPLEFT", PAD - 4, LIST_TOP)
	area:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD + 4, LIST_BOTTOM)
	local okBox, inset = pcall(CreateFrame, "Frame", nil, area, "InsetFrameTemplate")
	if okBox and inset then
		inset:SetAllPoints()
		inset:SetFrameLevel(area:GetFrameLevel())
	end
	f.ListArea = area
	-- Shopping tab: scope buttons, what is left to buy, Buy next / Buy vendor mats
	local sb = CreateFrame("Frame", nil, area)
	sb:SetPoint("TOPLEFT", area, "TOPLEFT", 6, -4)
	sb:SetPoint("TOPRIGHT", area, "TOPRIGHT", -6, -4)
	sb:SetHeight(SHOPBAR_H - 4)
	sb.Scopes = {}
	local scopes = { { "step", "This step" }, { "25", "Next 25" }, { "all", "Whole route" } }
	for i, spec in ipairs(scopes) do
		local b = CreateFrame("Button", nil, sb, "UIPanelButtonTemplate")
		b:SetSize(84, 20)
		b:SetPoint("LEFT", sb, "LEFT", (i - 1) * 86, 0)
		b:SetText(spec[2])
		b.scope = spec[1]
		b:SetScript("OnClick", function(self)
			PlaySoundKit("IG_CHARACTER_INFO_TAB")
			if CPa.db then CPa.db.shopScope = self.scope end
			CPa.Shop:Reset()
			UI.offset = 0
			UI:Refresh()
		end)
		sb.Scopes[i] = b
	end
	sb.Buy = CreateFrame("Button", nil, sb, "UIPanelButtonTemplate")
	sb.Buy:SetSize(130, 20)
	sb.Buy:SetPoint("RIGHT", sb, "RIGHT", 0, 0)
	sb.Buy:SetScript("OnClick", function() UI:BuyClick() end)
	sb.Buy:SetScript("OnEnter", function(self) UI:BuyTooltip(self) end)
	sb.Buy:SetScript("OnLeave", function() GameTooltip:Hide() end)
	sb.Info = Text(sb, "GameFontHighlightSmall", "RIGHT")
	sb.Info:SetPoint("RIGHT", sb.Buy, "LEFT", -8, 0)
	sb.Info:SetPoint("LEFT", sb.Scopes[#scopes], "RIGHT", 8, 0)
	sb:Hide()
	f.ShopBar = sb
	f.Rows = {}
	for i = 1, ROWS do f.Rows[i] = CreateRow(area, i) end
	f.Empty = Text(area, "GameFontDisable", "LEFT")
	f.Empty:SetPoint("TOPLEFT", area, "TOPLEFT", 14, -14)
	f.Empty:SetPoint("RIGHT", area, "RIGHT", -14, 0)
	if f.Empty.SetWordWrap then f.Empty:SetWordWrap(true) end
	if f.EnableMouseWheel then f:EnableMouseWheel(true) end
	f:SetScript("OnMouseWheel", function(_, delta) UI:Scroll(-delta) end)

	-- named so a macro can press it: /click CraftPathCraftButton
	f.CraftButton = CreateFrame("Button", "CraftPathCraftButton", f, "UIPanelButtonTemplate")
	f.CraftButton:SetSize(140, 22)
	f.CraftButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD + 4, 5)
	f.CraftButton:SetText("Craft next")
	-- key bindings and /click send a down or an up click depending on the "cast on key down" option, the mouse
	-- sends both: listen to both and act once per press
	if f.CraftButton.RegisterForClicks then f.CraftButton:RegisterForClicks("LeftButtonUp", "LeftButtonDown") end
	f.CraftButton:SetScript("OnClick", function(self)
		local now = GetTime and GetTime() or 0
		if self.lastPress and now - self.lastPress < 0.35 then return end
		self.lastPress = now
		CPa.Craft:CraftNext()
	end)
	f.CraftButton:SetScript("OnEnter", function(self) UI:CraftTooltip(self) end)
	f.CraftButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- the Now line: what to do this minute (hover for the why and how)
	-- up to two lines, so long advice is never cut off
	f.Foot = Text(f, "GameFontHighlightSmall", "LEFT")
	f.Foot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 5)
	-- Craft all: the rest of the current step in one go (Blizzard's crafting with a count)
	f.CraftAllButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.CraftAllButton:SetSize(104, 22)
	f.CraftAllButton:SetPoint("RIGHT", f.CraftButton, "LEFT", -4, 0)
	f.CraftAllButton:SetText("Craft all")
	f.CraftAllButton:SetScript("OnClick", function() CPa.Craft:CraftAll() end)
	f.CraftAllButton:SetScript("OnEnter", function(self)
		local plan = UI.plan
		local now = CPa.Craft:Now(plan)
		local n = CPa.Craft:BatchCount(now, plan)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Craft all")
		GameTooltip:AddLine(now.recipe and string.format("Crafts %d %s: what this step still needs, as far as your bags cover it.", n, tostring(now.recipe.name))
			or now.text, 1, 1, 1, true)
		GameTooltip:AddLine("Craft next stays for one at a time. Luck can end the step a few crafts early; the rest still count.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	f.CraftAllButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.Foot:SetPoint("RIGHT", f.CraftAllButton, "LEFT", -8, 0)
	f.Foot:SetHeight(24)
	if f.Foot.SetWordWrap then f.Foot:SetWordWrap(true) end
	if f.Foot.SetMaxLines then f.Foot:SetMaxLines(2) end
	if f.Foot.SetJustifyV then f.Foot:SetJustifyV("MIDDLE") end
	f.FootHit = CreateFrame("Frame", nil, f)
	f.FootHit:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 4)
	f.FootHit:SetPoint("TOPRIGHT", f.CraftAllButton, "TOPLEFT", -8, 2)
	f.FootHit:EnableMouse(true)
	f.FootHit:SetScript("OnEnter", function(self) UI:CraftTooltip(self) end)
	f.FootHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
	-- "Some data missing": data the route had to do without (hover for what and how to fill it in)
	local miss = CreateFrame("Frame", nil, f)
	miss:SetSize(150, 22)
	miss:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, CHECK_Y)
	miss.Icon = miss:CreateTexture(nil, "ARTWORK")
	miss.Icon:SetSize(18, 18)
	miss.Icon:SetPoint("RIGHT", miss, "RIGHT", 0, 0)
	miss.Icon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
	miss.Text = Text(miss, "GameFontNormal", "RIGHT")
	miss.Text:SetPoint("RIGHT", miss.Icon, "LEFT", -3, 0)
	miss.Text:SetText(Col(C.gold, "Some data missing"))
	miss:EnableMouse(true)
	miss:SetScript("OnEnter", function(self) UI:IssuesTooltip(self) end)
	miss:SetScript("OnLeave", function() GameTooltip:Hide() end)
	miss:Hide()
	f.Missing = miss

	f.Tabs = CreateTabs(f)
	return f
end

function UI:GetFrame()
	if not self.frame then
		self.frame = CreateWindow()
		local pos = CPa.db and CPa.db.pos
		if pos then
			self.frame:ClearAllPoints()
			self.frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
		end
	end
	return self.frame
end

function UI:IsShown() return self.frame and self.frame:IsShown() or false end

-- First open (no dragged position): beside the profession window, so the recipe list stays visible.
function UI:Dock()
	local f = self.frame
	if not f or (CPa.db and CPa.db.pos) then return end
	f:ClearAllPoints()
	local pf = ProfessionsFrame
	local screen = UIParent and UIParent.GetRight and UIParent:GetRight()
	local right = pf and pf:IsShown() and pf.GetRight and pf:GetRight()
	local left = pf and pf:IsShown() and pf.GetLeft and pf:GetLeft()
	local w = WIDTH * ((f.GetScale and f:GetScale()) or 1)
	if right and screen and right + 4 + w <= screen then
		f:SetPoint("TOPLEFT", pf, "TOPRIGHT", 4, 0)
	elseif left and left - 4 - w >= 0 then
		f:SetPoint("TOPRIGHT", pf, "TOPLEFT", -4, 0)
	elseif pf and pf:IsShown() and not (right and screen) then
		f:SetPoint("TOPLEFT", pf, "TOPRIGHT", 4, 0) -- sizes unknown: beside it
	else
		f:SetPoint("CENTER")
		if pf and pf:IsShown() and not UI.dragHinted then
			UI.dragHinted = true
			CPa:Print("drag the CraftPath window by its title to where it suits your screen; it remembers the spot.")
		end
	end
end

function UI:Open()
	local f = self:GetFrame()
	self:Dock()
	f:Show()
	self.view = self.view or "route"
	self.offset = 0
	if not (CPa.Model.plan and not CPa.Model:IsStale()) then CPa.Model:Build() end
	self:Refresh()
end

function UI:Toggle()
	if self:IsShown() then self.frame:Hide() else self:Open() end
end

function UI:SetView(view)
	self.view = view
	self.offset = 0
	self:Refresh()
end

-- rows the list shows (the Shopping tab gives the top one to its bar)
function UI:HasShopBar()
	local plan = CPa.Model and CPa.Model.plan
	return self.view == "shop" and plan ~= nil and not plan.bagsOnly
end
function UI:VisibleRows() return self:HasShopBar() and ROWS - 1 or ROWS end

function UI:Scroll(delta)
	self.offset = math.max(0, math.min((self.offset or 0) + delta, math.max(0, (self.rowCount or 0) - self:VisibleRows())))
	self:Refresh()
end

-- rows sit under the shopping bar on the Shopping tab
function UI:LayoutRows()
	local top = self:HasShopBar() and SHOPBAR_H or 0
	if self.rowTop == top then return end
	self.rowTop = top
	for i, row in ipairs(self.frame.Rows) do
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", self.frame.ListArea, "TOPLEFT", 4, -4 - top - (i - 1) * ROW_H)
		row:SetPoint("RIGHT", self.frame.ListArea, "RIGHT", -4, 0)
	end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function StepColourRange(st)
	local th = st.recipe.th
	local a = CPa.Solver.Colour(th, st.from)
	local b = CPa.Solver.Colour(th, st.to - 1)
	local function name(c) return Col(CPa.DIFF[c].hex, CPa.DIFF[c].name) end
	if a == b then return name(a) end
	return name(a) .. " to " .. name(b)
end

local function Estimated(th)
	return not (th.yellowKnown and th.grayKnown)
end

function UI:DrawBar(plan)
	local bar = self.frame.Bar
	for _, t in ipairs(bar.slices) do t:Hide() end
	for _, t in ipairs(bar.dividers) do t:Hide() end
	for _, t in ipairs(bar.icons) do t:Hide() end
	for _, t in ipairs(bar.labels) do t:Hide() end
	bar.hl:Hide()
	bar.hoverSkill = nil
	if bar.done then bar.done:Hide() end
	if bar.marker then bar.marker:Hide() end
	self.barSteps = nil
	if not plan then return end
	local origin = plan.start or plan.skill
	local span = plan.target - origin
	if span <= 0 then return end
	bar.span = span
	local width = bar:GetWidth()
	if not width or width <= 0 then width = WIDTH - 2 * (PAD + 6) end
	local unit = width / span
	local steps = plan.target > plan.skill and plan.result.steps or {}
	local segs = {}
	for _, st in ipairs(steps) do
		for _, sg in ipairs(Parts(st)) do segs[#segs + 1] = sg end
	end
	self.barSteps = segs

	-- done since the target was set: dimmed, with a gold marker at the current skill
	local doneTo = math.min(plan.skill, plan.target)
	if doneTo > origin then
		if not bar.done then
			bar.done = bar:CreateTexture(nil, "ARTWORK")
			bar.done:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
			bar.marker = bar:CreateTexture(nil, "OVERLAY", nil, 2)
		end
		bar.done:ClearAllPoints()
		bar.done:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
		bar.done:SetSize((doneTo - origin) * unit, BAR_H)
		bar.done:SetVertexColor(0.35, 0.35, 0.35, 1)
		bar.done:Show()
		bar.marker:ClearAllPoints()
		bar.marker:SetPoint("TOPLEFT", bar, "TOPLEFT", (doneTo - origin) * unit - 1, 3)
		bar.marker:SetSize(2, BAR_H + 6)
		bar.marker:SetColorTexture(1, 0.82, 0, 1)
		bar.marker:Show()
	end

	-- one run per colour inside a step, drawn with the status-bar texture (XP bar look), no gaps between points
	local function Run(i)
		local t = bar.slices[i]
		if not t then
			t = bar:CreateTexture(nil, "ARTWORK")
			t:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
			bar.slices[i] = t
		end
		return t
	end
	local n = 0
	for _, sg in ipairs(segs) do
		-- an intermediate's part is coloured by its own chance, the step's part by the recipe's
		local th = sg.it and sg.it.recipe.th or sg.st.recipe.th
		-- the recipe's colour at that skill, as the recipe list shows it (not the chance: the first yellow point
		-- still has a 100% chance and would be drawn orange)
		local function Col0(x)
			if not th then return 0 end
			local c = CPa.Solver.Colour(th, x)
			return c > 2 and 2 or c
		end
		local s = sg.from
		while s < sg.to do
			local c = Col0(s)
			local e = s + 1
			while e < sg.to and Col0(e) == c do e = e + 1 end
			n = n + 1
			local rgb = CPa.DIFF[c]
			local t = Run(n)
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", bar, "TOPLEFT", (s - origin) * unit, 0)
			t:SetSize((e - s) * unit, BAR_H)
			t:SetVertexColor(rgb[1], rgb[2], rgb[3], 1)
			t:Show()
			s = e
		end
	end
	-- rank caps: a gold tick where the next rank has to be trained
	bar.caps = bar.caps or {}
	for _, t in ipairs(bar.caps) do t:Hide() end
	for i, rk in ipairs(plan.ranks or {}) do
		if rk.by > origin and rk.by < plan.target then
			local tick = bar.caps[i]
			if not tick then
				tick = bar:CreateTexture(nil, "OVERLAY", nil, 3)
				bar.caps[i] = tick
			end
			tick:ClearAllPoints()
			tick:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", (rk.by - origin) * unit - 1, -BAR_H - 2)
			tick:SetSize(2, BAR_H + 6)
			tick:SetColorTexture(1, 0.82, 0, 0.9)
			tick:Show()
		end
	end
	-- what is left after a gap stays dark

	local function Label(i, text, x, anchor)
		local fs = bar.labels[i]
		if not fs then
			fs = Text(bar, "GameFontDisableSmall", "CENTER")
			bar.labels[i] = fs
		end
		fs:ClearAllPoints()
		fs:SetPoint(anchor or "TOP", bar, "BOTTOMLEFT", x, -6)
		fs:SetText(text)
		fs:Show()
		return fs
	end
	local labels = 0
	labels = labels + 1
	Label(labels, tostring(origin), 0, "TOPLEFT")
	local lastX = 0
	if doneTo > origin then
		-- current skill in gold under the marker
		local x = (doneTo - origin) * unit
		labels = labels + 1
		local fs = Label(labels, Col(C.gold, tostring(plan.skill)), x)
		if x < 26 or (width - x) < 26 then fs:Hide() else lastX = x end
	end
	for i, sg in ipairs(segs) do
		local x = (sg.from - origin) * unit
		if i > 1 or sg.from > origin then
			local d = bar.dividers[i]
			if not d then
				d = bar:CreateTexture(nil, "OVERLAY")
				bar.dividers[i] = d
			end
			d:ClearAllPoints()
			d:SetPoint("TOPLEFT", bar, "TOPLEFT", x - 1, 0)
			d:SetSize(2, BAR_H)
			d:SetColorTexture(0, 0, 0, 0.85)
			d:Show()
			if i > 1 and x - lastX >= 26 and (width - x) >= 26 then
				labels = labels + 1
				Label(labels, tostring(sg.from), x)
				lastX = x
			end
		end
		local segW = (sg.to - sg.from) * unit
		local icon = sg.it and ((sg.it.itemID and ItemIcon(sg.it.itemID)) or sg.it.recipe.icon) or sg.st.recipe.icon
		if segW >= ICON_SIZE + 2 and icon then
			local ic = bar.icons[i]
			if not ic then
				ic = bar:CreateTexture(nil, "OVERLAY")
				ic:SetSize(ICON_SIZE, ICON_SIZE)
				bar.icons[i] = ic
			end
			ic:ClearAllPoints()
			ic:SetPoint("CENTER", bar, "LEFT", x + segW / 2, 0)
			ic:SetTexture(icon)
			ic:Show()
		end
	end
	labels = labels + 1
	local endSkill = (plan.target > plan.skill and plan.result.reached) or plan.target
	Label(labels, tostring(plan.target), width, "TOPRIGHT")
	if endSkill < plan.target then
		labels = labels + 1
		local fs = Label(labels, Col(C.loss, (plan.bagsOnly and "bags end at " or "stops at ") .. endSkill), (endSkill - origin) * unit)
		fs:SetFontObject("GameFontNormalSmall")
	end
end

function UI:Refresh()
	local f = self.frame
	if not f or not f:IsShown() then return end
	local plan = CPa.Model.plan
	self.plan = plan
	if f.panelTabs and PanelTemplates_SetTab then
		pcall(PanelTemplates_SetTab, f, self.view == "shop" and 2 or 1)
	end
	if f.BagsCheck then f.BagsCheck:SetChecked(CPa:Setting("bagsOnly") and true or false) end
	if f.CraftCheck then
		f.CraftCheck:SetChecked(CPa:Setting("craftReagents") ~= false)
		f.CraftCheck:SetShown(not (plan and plan.bagsOnly))
	end
	if f.ReplaceCheck then
		f.ReplaceCheck:SetChecked(CPa:Setting("autoReplace") and true or false)
		-- only enchanting has the replace popup (the setting keeps working while another profession is shown)
		f.ReplaceCheck:SetShown(plan ~= nil and plan.key == "Enchanting")
	end
	f.PaceButton:CPRefresh()
	f.OutputsButton:CPRefresh()
	self:LayoutRows()

	local title = "CraftPath" .. (plan and (DOT .. plan.prof) or "")
	if f.SetTitle then pcall(f.SetTitle, f, title) elseif f.TitleText then f.TitleText:SetText(title) end
	local icon = plan and plan.icon or "Interface\\Icons\\INV_Misc_Book_11"
	if f.SetPortraitToAsset then pcall(f.SetPortraitToAsset, f, icon)
	elseif f.portraitTex and SetPortraitToTexture then pcall(SetPortraitToTexture, f.portraitTex, icon) end

	for _, row in ipairs(f.Rows) do row:Hide() end
	f.Empty:SetText("")
	f.ShopBar:SetShown(self:HasShopBar())
	f.Empty:SetPoint("TOPLEFT", f.ListArea, "TOPLEFT", 14, -14)
	if not plan then
		f.Range:SetText("")
		f.Total:SetText("")
		f.Summary:SetText("")
		if not f.TargetBox:HasFocus() then f.TargetBox:SetText("") end
		self:DrawBar(nil)
		f.Empty:SetText("How to use CraftPath:\n\n1. At the Auction House click CraftProfit Scan (prices).\n2. Open the profession you want to level.\n3. Type a target skill. CraftPath shows the cheapest route; press Craft next to follow it.")
		f.Foot:SetText("")
		f.Missing:Hide()
		return
	end
	if not f.TargetBox:HasFocus() then f.TargetBox:SetText(tostring(plan.target)) end
	local now = CPa.Craft:Now(plan)
	f.CraftButton:SetText(now.kind == "learn" and "Learn next" or now.kind == "rank" and "Train first"
		or now.kind == "buy" and "Get mats first" or "Craft next")
	local batch = CPa.Craft:BatchCount(now, plan)
	f.CraftAllButton:SetShown(now.kind == "craft" or now.kind == "part")
	f.CraftAllButton:SetText(batch > 1 and string.format("Craft all (%d)", batch) or "Craft all")
	if f.CraftAllButton.SetEnabled then f.CraftAllButton:SetEnabled(batch >= 1) end
	-- an action you cannot do from here yet (level, gap, buy) still shows on the button's tooltip and the Now line

	local res = plan.result
	local reagents, training = 0, (res.extraTraining or 0) + (res.rankTraining or 0)
	for _, st in ipairs(res.steps) do
		reagents = reagents + st.cost
		training = training + st.learnCost
	end
	f.Range:SetText(string.format("%s %d - %d", plan.prof, plan.skill, plan.target))
	local partCrafts = 0
	for _, st in ipairs(res.steps) do
		for _, it in ipairs(st.inter or {}) do partCrafts = partCrafts + (it.crafts or 0) end
	end
	local function CraftsText(n)
		local t = Crafts(n)
		if partCrafts >= 0.5 then t = t .. string.format(" (+%d for parts)", math.floor(partCrafts + 0.5)) end
		return t
	end
	if plan.target <= plan.skill then
		f.Total:SetText(Col(C.good, "Target reached"))
		f.Summary:SetText(string.format("Raise the target to plan further (up to %d).", CPa.Data.MAX_SKILL or 300))
	elseif plan.bagsOnly then
		local trainGold = res.training or 0
		f.Total:SetText(trainGold > 0 and Money(trainGold, { compact = true }) or Col(C.good, "no gold"))
		local parts = { CraftsText(res.crafts), string.format("%d steps", #res.steps),
			"uses mats worth " .. Money(res.mats or res.total, { compact = true }) }
		if trainGold > 0 then parts[#parts + 1] = "training " .. Money(trainGold, { compact = true }) .. " (the only gold)" end
		if (res.reached or plan.target) < plan.target then
			parts[#parts + 1] = Col(C.loss, "your bags get you to " .. res.reached)
		end
		f.Summary:SetText(table.concat(parts, DOT))
	else
		f.Total:SetText(Net(res.total))
		local parts = { CraftsText(res.crafts), string.format("%d steps", #res.steps), "materials " .. Net(reagents) }
		if training > 0 then parts[#parts + 1] = "training " .. Money(training, { compact = true }) end
		local unknown = 0
		for _, rk in ipairs(plan.ranks or {}) do if not rk.cost then unknown = unknown + 1 end end
		if unknown > 0 then parts[#parts + 1] = Col(C.muted, string.format("%d rank price%s unknown", unknown, unknown > 1 and "s" or "")) end
		f.Summary:SetText(table.concat(parts, DOT))
	end
	self:DrawBar(plan)

	if self.view == "shop" then
		self:DrawShopping(plan)
	else
		self:DrawRoute(plan)
	end

	f.Foot:SetText(Col(C.gold, "Now: ") .. now.text)
	f.Missing:SetShown(self:IssueCount(plan) > 0)
	-- keep the scroll inside the list after it got shorter
	local maxOffset = math.max(0, (self.rowCount or 0) - self:VisibleRows())
	if (self.offset or 0) > maxOffset then
		self.offset = maxOffset
		self:Refresh()
	end
end

local STALE_PRICES = 24 * 3600

-- How many kinds of missing data the plan has (the "Some data missing" marker shows when > 0).
function UI:IssueCount(plan)
	if not plan then return 0 end
	local n = 0
	if plan.result and plan.result.gap and plan.target > plan.skill then n = n + 1 end
	if #(plan.unsourced or {}) > 0 then n = n + 1 end
	if #(plan.unchecked or {}) > 0 then n = n + 1 end
	if #(plan.unpriced or {}) > 0 then n = n + 1 end
	for _, rk in ipairs(plan.ranks or {}) do if not rk.cost then n = n + 1 break end end
	if not plan.covered then n = n + 1 end
	if plan.priceAge and plan.priceAge > STALE_PRICES then n = n + 1 end
	return n
end

function UI:DrawRoute(plan)
	local f = self.frame
	local steps = plan.result.steps
	self.rowCount = #steps
	if #steps == 0 then
		if plan.target > plan.skill and plan.bagsOnly then
			f.Empty:SetText("Nothing in your bags makes a recipe that still gives points. Untick \"Only mats in my bags\" for the full route.")
		elseif plan.target > plan.skill and (plan.maxSkill or 0) <= plan.skill and plan.ranks and plan.ranks[1] then
			f.Empty:SetText(CPa.Craft:Now(plan).text)
		elseif plan.target > plan.skill and #(plan.recipes or {}) == 0 and #(plan.unpriced or {}) > 0 then
			f.Empty:SetText("No prices yet, so no route.\n\n1. Go to the Auction House (in a capital city).\n2. Click CraftProfit Scan (bottom left of the Auction House).\n3. Come back: the route fills in by itself.")
		elseif plan.target > plan.skill then
			local lines = { plan.result.gap and string.format("No recipe CraftPath knows gives a point at %d.", plan.result.gap)
				or "No priced recipe can take you further." }
			if not plan.covered then
				lines[#lines + 1] = string.format("\nCraftPath has no trainer data for %s yet, so it only uses the recipes you know.", tostring(plan.prof))
				lines[#lines + 1] = "Learn a recipe that is orange or yellow at your skill, or open your trainer: CraftPath records what it teaches."
			else
				lines[#lines + 1] = "\nLearn a recipe that is orange or yellow there, or open your trainer again: it shows more recipes as your skill grows, and CraftPath records them."
			end
			f.Empty:SetText(table.concat(lines, "\n"))
		end
		return
	end
	-- steps and rank milestones in skill order (a rank sits where you hit the old cap)
	local list = {}
	for _, st in ipairs(steps) do
		-- what the step crafts first (Bolts of Linen Cloth for the bags) gets its own row above it
		-- (a part gets its own row only while making the ones still needed gives skill; one made just for the
		-- recipe stays in that step's line: "needs ~252 Bolt of Linen Cloth (you make them)")
		for k, sg in ipairs(Parts(st)) do
			if sg.it then list[#list + 1] = { kind = "inter", st = st, it = sg.it, part = sg, key = st.from - 0.1 + k * 0.01 } end
		end
		list[#list + 1] = { kind = "step", st = st, key = st.from }
	end
	for _, rk in ipairs(plan.ranks or {}) do
		if rk.by >= plan.skill then list[#list + 1] = { kind = "rank", rk = rk, key = rk.by - 0.5 } end
	end
	table.sort(list, function(a, b) return a.key < b.key end)
	self.rowCount = #list
	local offset = self.offset or 0
	local acc = 0
	for _, e in ipairs(list) do
		if e.kind == "step" then
			acc = acc + e.st.cost + e.st.learnCost
		elseif e.kind == "rank" then
			acc = acc + (e.rk.cost or 0)
		end -- an intermediate's cost is inside its step
		e.soFar = acc
	end
	local stepNo = 0
	for i = 1, offset do if list[i] and (list[i].kind == "step" or list[i].kind == "inter") then stepNo = stepNo + 1 end end
	-- each row shows the skill range of its part (bolts first, then the step's own recipe)
	local function PartOf(st, it)
		for _, sg in ipairs(Parts(st)) do if sg.it == it then return sg end end
		return { from = st.from, to = st.to }
	end
	for i = 1, self:VisibleRows() do
		local e = list[i + offset]
		local row = f.Rows[i]
		if e and e.kind == "inter" then
			local st, it = e.st, e.it
			local mr = it.recipe
			row.kind, row.step, row.rank, row.inter = "inter", st, nil, it
			row.Icon:SetTexture((it.itemID and ItemIcon(it.itemID)) or mr.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
			stepNo = stepNo + 1
			row.Num:SetText(tostring(stepNo))
			local cb = CPa.DIFF[mr.th and CPa.Solver.Colour(mr.th, st.from) or 2]
			row.Band:SetColorTexture(cb[1], cb[2], cb[3], 1)
			row.Band:Show()
			local part = e.part or PartOf(st, it)
			local n = math.ceil((part.crafts or it.crafts) - 1e-9)
			local itemName = it.itemID and ItemName(it.itemID) or tostring(mr.name)
			row.Name:SetText(itemName)
			local total = st.to - st.from
			local sub = string.format("%d-%d%s~%d crafts%s", part.from, part.to, DOT, n, DOT)
				.. Col(C.good, string.format("gives ~%d of the %d points", part.to - part.from, total))
			if mr.th then
				local a, b = CPa.Solver.Colour(mr.th, part.from), CPa.Solver.Colour(mr.th, math.max(part.from, part.to - 1))
				local function cn(c) return Col(CPa.DIFF[c].hex, CPa.DIFF[c].name) end
				sub = sub .. DOT .. (a == b and cn(a) or (cn(a) .. " to " .. cn(b)))
			end
			sub = sub .. DOT .. string.format("part for %s", tostring(st.recipe.name))
			if not mr.learned and mr.npc then
				sub = sub .. DOT .. Col(C.label, string.format("learn at skill %s from %s", tostring(mr.learnAt or "?"), mr.npc.name))
			end
			row.Sub:SetText(sub)
			row.Value:SetText("")
			row.Note:SetText(Col(C.muted, "cost: next row"))
			row:Show()
		elseif e and e.kind == "rank" then
			local rk = e.rk
			row.kind, row.step, row.rank = "rank", nil, rk
			row.Icon:SetTexture(plan.icon or "Interface\\Icons\\INV_Misc_Book_11")
			row.Num:SetText("")
			row.Band:SetColorTexture(1, 0.82, 0, 1)
			row.Band:Show()
			row.Name:SetText(Col(C.gold, "Train: ") .. rk.name)
			local okL, myLevel = pcall(function() return UnitLevel("player") end)
			local levelText = (okL and type(myLevel) == "number" and myLevel < rk.level)
				and Col(C.loss, string.format("level %d (you are %d)", rk.level, myLevel)) or ("level " .. rk.level)
			row.Sub:SetText(string.format("before %d%sneeds skill %d, %s%s", rk.by, DOT, rk.at, levelText,
				rk.npc and (DOT .. rk.npc.name) or ""))
			row.Value:SetText(rk.cost and Money(rk.cost, { compact = true }) or Col(C.muted, "price ?"))
			row.Note:SetText("total " .. Net(e.soFar))
			row:Show()
		elseif e then
			local st = e.st
			stepNo = stepNo + 1
			local r = st.recipe
			row.kind, row.step, row.rank = "step", st, nil
			row.Icon:SetTexture(r.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
			row.Num:SetText(tostring(stepNo))
			local c = CPa.DIFF[CPa.Solver.Colour(r.th, st.from)]
			row.Band:SetColorTexture(c[1], c[2], c[3], 1)
			row.Band:Show()
			row.Name:SetText((r.learned and "" or Col(C.gold, "Learn: ")) .. tostring(r.name) .. (Estimated(r.th) and Col(C.muted, " *") or ""))
			local part = PartOf(st, nil)
			local sub = string.format("%d-%d%s%s%s%s", part.from, part.to, DOT, Crafts(st.crafts), DOT, StepColourRange(st))
			local fromInter = 0
			for _, it in ipairs(st.inter or {}) do
				fromInter = fromInter + it.points
				local nm = it.itemID and ItemName(it.itemID) or tostring(it.recipe.name)
				if it.top and it.points < 0.5 and it.crafts >= 0.5 then
					local early = plan.result.madeEarlier and plan.result.madeEarlier[it.itemID]
					if early and early ~= st then
						sub = sub .. DOT .. Col(C.muted, string.format("needs ~%d %s (made at %d-%d)", math.ceil(it.crafts - 1e-9), nm, early.from, early.to))
					else
						sub = sub .. DOT .. Col(C.muted, string.format("needs ~%d %s (you make them)", math.ceil(it.crafts - 1e-9), nm))
					end
				end
				if it.top and (it.bought or 0) >= 0.5 then
					sub = sub .. DOT .. Col(C.muted, string.format("buys ~%d %s", math.ceil(it.bought - 1e-9), nm))
				end
			end
			if fromInter >= 0.5 then
				sub = sub .. DOT .. Col(C.label, string.format("~%d points from this recipe", math.floor((st.own or 0) + 0.5)))
			end
			if st.forLater then
				sub = sub .. DOT .. Col(C.good, string.format("make ~%d extra for %s", math.ceil(st.forLater.crafts - 1e-9), st.forLater.usedBy))
			end
			local sdet = CPa.Model.StepDetail(st)
			local tool = sdet and sdet.tools and sdet.tools[1]
			if not r.learned and r.npc then
				sub = sub .. DOT .. Col(C.label, string.format("learn at skill %s from %s, %s", tostring(r.learnAt or "?"), r.npc.name,
					Money(st.learnCost, { compact = true })))
			end
			if tool and not tool.have then sub = sub .. DOT .. Col(C.loss, "needs " .. ItemName(tool.itemID)) end
			row.Sub:SetText(sub)
			row.Value:SetText(Net(st.cost + st.learnCost))
			row.Note:SetText("total " .. Net(e.soFar))
			row:Show()
		end
	end
end

function UI:ShopScope() return (CPa.db and CPa.db.shopScope) or "25" end

-- The Shopping list for the chosen scope (cached per plan and scope; bag changes recount what you own).
function UI:ShopList(plan)
	local scope = self:ShopScope()
	if not (self.shopCache and self.shopCache.plan == plan and self.shopCache.scope == scope and not self.shopDirty) then
		local list, training = CPa.Model:ShoppingFor(plan, scope)
		self.shopCache = { plan = plan, scope = scope, list = list, training = training }
		self.shopDirty = false
	end
	return self.shopCache.list, self.shopCache.training
end

local function SourceText(e)
	if e.kind == "vendor" then return "Vendor" end
	if e.kind == "tool" then return "tool, kept (AH or an enchanter)" end
	if e.kind == "craft" then return "you make it" end
	return "Auction House"
end

function UI:DrawShopping(plan)
	local f = self.frame
	local list, training = self:ShopList(plan)
	-- the bar: scope, what is left to buy, the buy button for where you stand
	local sb = f.ShopBar
	local scope = self:ShopScope()
	for _, b in ipairs(sb.Scopes) do
		if b.SetEnabled then b:SetEnabled(b.scope ~= scope) end
	end
	local toBuy, rowsLeft, noPrice = 0, 0, 0
	for _, e in ipairs(list) do
		if e.kind ~= "craft" and (e.need or e.qty) > 0 then
			toBuy = toBuy + (e.unit or 0) * (e.need or e.qty)
			rowsLeft = rowsLeft + 1
			if not e.unit then noPrice = noPrice + 1 end
		end
	end
	sb.Info:SetText(rowsLeft > 0 and (string.format("%d to buy, %s", rowsLeft, Money(toBuy, { compact = true }))
		.. (noPrice > 0 and Col(C.loss, string.format(" +%d no price", noPrice)) or "")) or Col(C.good, "you have it all"))
	local Shop = CPa.Shop
	if Shop:AtAuctionHouse() then
		sb.Buy:SetText("Buy next")
		sb.Buy:Show()
	elseif Shop:AtMerchant() then
		sb.Buy:SetText("Buy vendor mats")
		sb.Buy:Show()
	else
		sb.Buy:Hide()
	end

	local items = {}
	for _, e in ipairs(list) do items[#items + 1] = { kind = "item", e = e } end
	for _, t in ipairs(training) do items[#items + 1] = { kind = "train", e = t } end
	self.rowCount = #items
	if #items == 0 then
		f.Empty:SetPoint("TOPLEFT", f.ListArea, "TOPLEFT", 14, -14 - SHOPBAR_H)
		f.Empty:SetText("Nothing to buy for this part of the route.")
		return
	end
	local offset = self.offset or 0
	for i = 1, self:VisibleRows() do
		local it = items[i + offset]
		local row = f.Rows[i]
		if it then
			row.kind, row.step = it.kind, it.e
			row.Band:Hide()
			row.Num:SetText("")
			if it.kind == "item" then
				local e = it.e
				row.Icon:SetTexture(ItemIcon(e.itemID) or "Interface\\Icons\\INV_Misc_QuestionMark")
				local need = e.need or e.qty
				local covered = e.have and need <= 0
				row.Name:SetText((covered and Col(C.muted, tostring(e.qty) .. " x ") or (tostring(e.qty) .. " x ")) .. ItemName(e.itemID))
				if plan.bagsOnly and e.have then
					row.Sub:SetText(string.format("from your bags: %d, %d left after", e.have, math.max(0, e.have - e.qty)))
				else
					local inBank = (e.have and e.bags and e.have > e.bags) and string.format(" (%d in bank)", e.have - e.bags) or ""
					local own = e.have and (covered and Col(C.good, string.format("have all (%d)", e.have) .. inBank)
						or string.format("%s%shave %d%s", Col(C.white, "need " .. need), DOT, e.have, inBank)) or ""
					local src = SourceText(e)
					if e.kind == "craft" and e.maker and not e.maker.recipe.learned then
						src = src .. Col(C.label, string.format("%slearn %s from %s", DOT, tostring(e.maker.recipe.name),
							e.maker.recipe.npc and e.maker.recipe.npc.name or "a trainer"))
					end
					row.Sub:SetText(own ~= "" and (own .. DOT .. src) or src)
				end
				if e.kind == "craft" then
					-- its gold is in the rows of what it is made from
					row.Value:SetText(Col(C.muted, "you make it"))
					row.Note:SetText(e.unit and (Money(e.unit) .. " each to make") or "")
				elseif covered then
					row.Value:SetText(Col(C.muted, "-"))
					row.Note:SetText("")
				else
					row.Value:SetText(e.unit and Money(e.unit * need, { compact = true }) or Col(C.loss, "no price"))
					row.Note:SetText(e.unit and (Money(e.unit) .. " each") or "")
				end
			else
				local t = it.e
				row.Icon:SetTexture(t.recipe.icon or "Interface\\Icons\\INV_Misc_Book_11")
				row.Name:SetText(Col(C.gold, t.rank and "Train: " or "Learn: ") .. tostring(t.recipe.name))
				local where = (t.reagent and ("to make " .. ItemName(t.reagent) .. DOT) or "")
					.. (t.npc and (t.npc.name .. ((t.npc.place and t.npc.place ~= "") and (DOT .. t.npc.place) or "")) or "")
				row.Sub:SetText((t.recipe.learnAt and ("skill " .. t.recipe.learnAt .. DOT) or "") .. where)
				row.Value:SetText(t.unknownCost and Col(C.muted, "price ?") or Money(t.cost, { compact = true }))
				row.Note:SetText(t.npc and t.npc.kind or "")
			end
			row:Show()
		end
	end
end

function UI:BuyClick()
	local plan = self.plan
	if not plan then return end
	local list = self:ShopList(plan)
	if CPa.Shop:AtAuctionHouse() then
		CPa.Shop:BuyNext(list)
	elseif CPa.Shop:AtMerchant() then
		CPa.Shop:BuyVendor(list)
	end
end

function UI:BuyTooltip(owner)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if CPa.Shop:AtAuctionHouse() then
		local plan = self.plan
		local e = plan and CPa.Shop:NextAH((self:ShopList(plan)))
		GameTooltip:AddLine("Buy next")
		GameTooltip:AddLine(e and string.format("Opens %s with %d filled in. You press Buy.", ItemName(e.itemID), e.need)
			or "Nothing left to buy here.", 1, 1, 1, true)
		GameTooltip:AddLine("Press again to skip to the next item. Works on the scope shown (This step / Next 25 / Whole route).", 0.7, 0.7, 0.7, true)
	else
		GameTooltip:AddLine("Buy vendor mats")
		GameTooltip:AddLine("Buys what the list still needs that this merchant sells.", 1, 1, 1, true)
	end
	GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Tooltips and clicks
---------------------------------------------------------------------------

-- part: the stretch of the bar this recipe covers itself (after the parts crafted first), from Parts(st)
function UI:StepTooltip(owner, st, skill, part)
	local r = st.recipe
	local th = r.th
	part = part or Parts(st)[#Parts(st)]
	GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
	GameTooltip:AddLine(tostring(r.name))
	GameTooltip:AddDoubleLine("Skill", string.format("%d - %d", part.from, part.to), 0.8, 0.8, 0.8, 1, 1, 1)
	if part.from > st.from then
		local names = {}
		for _, sg in ipairs(Parts(st)) do
			if sg.it then names[#names + 1] = (sg.it.itemID and ItemName(sg.it.itemID)) or tostring(sg.it.recipe.name) end
		end
		GameTooltip:AddLine(string.format("%d - %d: the %s you make for it (crafted first).", st.from, part.from, table.concat(names, ", ")),
			0.6, 0.6, 0.6, true)
	end
	local lo, hi = CPa.Solver.Range(st)
	GameTooltip:AddDoubleLine("Expected crafts", hi > lo and string.format("%.0f (usually %d-%d)", st.crafts, lo, hi)
		or string.format("%.1f", st.crafts), 0.8, 0.8, 0.8, 1, 1, 1)
	if skill then
		GameTooltip:AddDoubleLine(string.format("Chance of a point at %d", skill),
			string.format("%d%%", math.floor(CPa.Solver.Chance(th, skill) * 100 + 0.5)), 0.8, 0.8, 0.8, 1, 1, 1)
		for _, b in ipairs((st.variant or r).bonus or {}) do
			local bc = CPa.Solver.Chance(b.th, skill)
			if bc >= 0.005 then
				GameTooltip:AddDoubleLine(string.format("+ %.1f %s per craft", b.per, tostring(b.recipe.name)),
					string.format("%d%% each", math.floor(bc * 100 + 0.5)), 0.8, 0.8, 0.8, 1, 1, 1)
			end
		end
	end
	GameTooltip:AddDoubleLine("Cost of this step", Money(st.cost), 0.8, 0.8, 0.8, 1, 1, 1)
	if st.learnCost > 0 then
		if r.learnAt then
			GameTooltip:AddDoubleLine("Learn at skill", tostring(r.learnAt), 0.8, 0.8, 0.8, 1, 1, 1)
		end
		GameTooltip:AddDoubleLine("Training", Money(st.learnCost) .. (r.npc and (" (" .. r.npc.name .. ")") or ""), 0.8, 0.8, 0.8, 1, 1, 1)
		if r.npc and r.npc.place and r.npc.place ~= "" then GameTooltip:AddLine(r.npc.place, 0.6, 0.6, 0.6) end
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Per craft", 1, 0.82, 0)
	local d = CPa.Model.StepDetail(st) or {}
	for _, rg in ipairs(d.reagents or {}) do
		GameTooltip:AddDoubleLine(string.format("%dx %s%s", rg.qty, ItemName(rg.itemID), rg.kind == "craft" and " (crafted)" or ""),
			rg.unit and Money(rg.unit * rg.qty) or "no price", 0.8, 0.8, 0.8, 1, 1, 1)
	end
	for _, tool in ipairs(d.tools or {}) do
		GameTooltip:AddDoubleLine(ItemName(tool.itemID) .. " (tool, not used up)", tool.have and "in bags" or "missing",
			0.8, 0.8, 0.8, tool.have and 0.3 or 1, tool.have and 0.8 or 0.35, tool.have and 0.3 or 0.3)
	end
	for _, req in ipairs(r.requirements or {}) do
		GameTooltip:AddDoubleLine("Requires " .. req.name, req.met and "ok" or "missing", 0.8, 0.8, 0.8, req.met and 0.3 or 1, req.met and 0.8 or 0.35, 0.3)
	end
	if (d.worth or 0) > 0 then
		GameTooltip:AddDoubleLine("Made item worth", "-" .. Money(d.worth), 0.8, 0.8, 0.8, 1, 1, 1)
	end
	GameTooltip:AddLine(" ")
	local function Mark(known) return known and "" or "*" end
	GameTooltip:AddLine(string.format("%s %d%s   %s %d%s   %s %d%s",
		Col(CPa.DIFF[1].hex, "yellow"), th.yellow, Mark(th.yellowKnown),
		Col(CPa.DIFF[2].hex, "green"), th.green, Mark(th.greenKnown),
		Col(CPa.DIFF[3].hex, "gray"), th.gray, Mark(th.grayKnown)), 1, 1, 1)
	if Estimated(th) then
		GameTooltip:AddLine("* estimated (most recipes change colour every 20 points; green starts halfway between yellow and gray). Colours seen in your profession window replace estimates.", 0.6, 0.6, 0.6, true)
	end
	GameTooltip:AddLine(Col(CPa.DIFF[0].hex, "orange") .. " every craft gives a point, " .. Col(CPa.DIFF[1].hex, "yellow")
		.. " most do, " .. Col(CPa.DIFF[2].hex, "green") .. " fewer than half.", 0.6, 0.6, 0.6, true)
	if th.mismatch then
		GameTooltip:AddLine("The client's gray level does not match the colours seen; the colours seen win.", 1, 0.5, 0.3, true)
	end
	GameTooltip:Show()
end

-- Footer hover: which recipes were left out and why.
function UI:IssuesTooltip(owner)
	local plan = self.plan
	if not plan then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:AddLine("Some data missing")
	GameTooltip:AddLine("The route is the cheapest with what CraftPath knows. Filling these in can change it.", 0.8, 0.8, 0.8, true)
	if not plan.covered then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(string.format("No trainer data for %s", tostring(plan.prof)), 1, 0.82, 0)
		GameTooltip:AddLine("Only the recipes you know are used. Open your trainer once and CraftPath adds the recipes it teaches.", 0.6, 0.6, 0.6, true)
	end
	if plan.priceAge and plan.priceAge > STALE_PRICES then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(string.format("Prices are %d days old", math.floor(plan.priceAge / 86400 + 0.5)), 1, 0.82, 0)
		GameTooltip:AddLine("Scan the Auction House with CraftProfit again.", 0.6, 0.6, 0.6, true)
	end
	if plan.result and plan.result.gap and plan.target > plan.skill then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(string.format("No known recipe gives a point at %d", plan.result.gap), 1, 0.4, 0.4)
		GameTooltip:AddLine("The route stops there. Trainers show only the next recipes for your skill: open yours again as you level and the route goes further, or learn a recipe that is orange or yellow there.", 0.6, 0.6, 0.6, true)
	end
	local unknownRanks = {}
	for _, rk in ipairs(plan.ranks or {}) do if not rk.cost then unknownRanks[#unknownRanks + 1] = rk.name end end
	if #unknownRanks > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Rank price not recorded", 1, 0.82, 0)
		for _, nm in ipairs(unknownRanks) do GameTooltip:AddLine(nm, 0.8, 0.8, 0.8) end
		GameTooltip:AddLine("Not in the total yet. Open the trainer once and CraftPath records the price.", 0.6, 0.6, 0.6, true)
	end
	if #(plan.unsourced or {}) > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Bought: no recorded trainer or vendor for its recipe", 1, 0.82, 0)
		for _, un in ipairs(plan.unsourced) do GameTooltip:AddLine(un.name, 0.8, 0.8, 0.8) end
		GameTooltip:AddLine("You could craft these, but CraftPath does not know where the recipe is taught. Open your trainer or the vendor that sells the pattern (or learn it) and the route crafts them.", 0.6, 0.6, 0.6, true)
	end
	if #(plan.unchecked or {}) > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Bought without checking the craft", 1, 0.82, 0)
		for _, u in ipairs(plan.unchecked) do
			local names = {}
			for _, id in ipairs(u.missing) do names[#names + 1] = ItemName(id) end
			GameTooltip:AddDoubleLine(string.format("%s (%s)", ItemName(u.itemID), tostring(u.maker.recipe.name)),
				"no price: " .. table.concat(names, ", "), 0.8, 0.8, 0.8, 1, 0.4, 0.4)
		end
		GameTooltip:AddLine("Search those mats at the AH (or scan) and the route checks crafting them yourself.", 0.6, 0.6, 0.6, true)
	end
	if #(plan.unpriced or {}) > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Left out: a reagent has no price", 1, 0.82, 0)
		for _, r in ipairs(plan.unpriced) do
			local names = {}
			for _, id in ipairs(r.detail and r.detail.missing or {}) do names[#names + 1] = ItemName(id) end
			GameTooltip:AddDoubleLine(tostring(r.name), table.concat(names, ", "), 0.8, 0.8, 0.8, 1, 0.4, 0.4)
		end
		GameTooltip:AddLine("Scan the AH with CraftProfit (or search the item there) so it gets a price.", 0.6, 0.6, 0.6, true)
	end
	if plan.otherFaction then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Trainer data was recorded on the other faction: your trainer teaches the same recipes, but early recipes and pattern vendors may be missing. They fill in when you open your trainer.", 0.6, 0.6, 0.6, true)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("/cpath report: every candidate recipe and price in a copy window.", 0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

function UI:HelpTooltip(owner)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:AddLine("How CraftPath works")
	GameTooltip:AddLine("The cheapest way from your skill to the target skill, with the recipes you know and the ones you can learn.", 1, 1, 1, true)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("0. Prices: at the Auction House click CraftProfit Scan (bottom left).", 1, 1, 1, true)
	GameTooltip:AddLine("1. The target starts at 300 (the top); type a lower one for a shorter plan. Saved per character.", 1, 1, 1, true)
	GameTooltip:AddLine("2. Shopping list tab: buy what you need for the next 25 points. At the Auction House press Buy next; at a vendor, Buy vendor mats.", 1, 1, 1, true)
	GameTooltip:AddLine("3. Press Craft next (or its key: Key Bindings > AddOns > CraftPath) until the target. It picks the right recipe every time.", 1, 1, 1, true)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("The Now line at the bottom always says what to do. Hover a step or the bar for details.", 0.8, 0.8, 0.8, true)
	GameTooltip:AddLine("Crafts are averages: luck moves them, and the route plans again after every skill-up.", 0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

function UI:CraftTooltip(owner)
	local plan = self.plan
	local now = CPa.Craft:Now(plan)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:AddLine(now.kind == "buy" and "Get mats first" or now.kind == "learn" and "Learn next" or now.kind == "rank" and "Train first" or "Craft next")
	GameTooltip:AddLine(now.text, 1, 1, 1, true)
	if now.kind == "buy" then
		GameTooltip:AddLine("Click: opens the Shopping list (at the Auction House it also opens the next item to buy).", 0.8, 0.8, 0.8, true)
	end
	if now.recipe and (now.kind == "craft" or now.kind == "part") then
		local n = CPa.Craft:Available(now.recipe.id)
		if n then GameTooltip:AddLine(string.format("Your bags have mats for %d.", n), 0.8, 0.8, 0.8) end
	end
	GameTooltip:AddLine("Crafts one item of the current step and picks the right recipe for you.", 0.8, 0.8, 0.8, true)
	GameTooltip:AddLine("Key binding: Key Bindings > AddOns > CraftPath. Macro: /click CraftPathCraftButton", 0.6, 0.6, 0.6, true)
	if plan and not plan.bagsOnly then
		local src = (CPa.CP and CPa.CP.GetSourceName and CPa.CP:GetSourceName()) or "CraftProfit"
		local age = plan.priceAge and (plan.priceAge < 3600 and "less than an hour old" or string.format("%d hours old", math.floor(plan.priceAge / 3600)))
		GameTooltip:AddLine(string.format("Crafts are averages; luck moves them. Prices: %s%s, lowest listing per unit.", src,
			age and (", " .. age) or ""), 0.6, 0.6, 0.6, true)
	end
	GameTooltip:Show()
end

function UI:InterTooltip(owner, st, it, skill, part)
	if not part then
		for _, sg in ipairs(Parts(st)) do if sg.it == it then part = sg end end
	end
	GameTooltip:SetOwner(owner, owner == self.frame.Bar and "ANCHOR_BOTTOM" or "ANCHOR_RIGHT")
	GameTooltip:AddLine(it.itemID and ItemName(it.itemID) or tostring(it.recipe.name))
	if part then GameTooltip:AddDoubleLine("Skill", string.format("%d - %d", part.from, part.to), 0.8, 0.8, 0.8, 1, 1, 1) end
	GameTooltip:AddDoubleLine("Crafts still to make", string.format("~%d", math.ceil(((part and part.crafts) or it.crafts) - 1e-9)), 0.8, 0.8, 0.8, 1, 1, 1)
	GameTooltip:AddDoubleLine("Points", string.format("~%d", part and (part.to - part.from) or math.floor(it.points + 0.5)), 0.8, 0.8, 0.8, 1, 1, 1)
	if skill and it.recipe and it.recipe.th then
		GameTooltip:AddDoubleLine(string.format("Chance of a point at %d", skill),
			string.format("%d%%", math.floor(CPa.Solver.Chance(it.recipe.th, skill) * 100 + 0.5)), 0.8, 0.8, 0.8, 1, 1, 1)
	end
	GameTooltip:AddLine(string.format("Made for the %s step (about %.1f per craft), all of them first: their points come in the order orange, yellow, green. The ones you already have are left out.",
		tostring(st.recipe.name), it.crafts / math.max(st.crafts, 1e-9)), 1, 1, 1, true)
	GameTooltip:AddLine("Craft next makes them before the step's own recipe when you have too few.", 0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

function UI:RowTooltip(row)
	if row.kind == "inter" and row.inter then
		self:InterTooltip(row, row.step, row.inter)
		return
	end
	if row.kind == "rank" and row.rank then
		local rk = row.rank
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:AddLine(rk.name)
		GameTooltip:AddLine(string.format("Your skill stops at %d until you train it. Needs skill %d and character level %d; raises the cap to %d.",
			rk.by, rk.at, rk.level, rk.cap), 1, 1, 1, true)
		if rk.npc then GameTooltip:AddLine(rk.npc.name .. (rk.npc.place ~= "" and (", " .. rk.npc.place) or ""), 0.8, 0.8, 0.8) end
		if not rk.cost then
			GameTooltip:AddLine("Price not recorded yet: open the trainer once and it fills in.", 0.6, 0.6, 0.6, true)
		end
		GameTooltip:Show()
		return
	end
	if row.kind == "step" then
		self:StepTooltip(row, row.step)
	elseif row.kind == "item" and row.step.itemID then
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		if GameTooltip.SetItemByID then GameTooltip:SetItemByID(row.step.itemID) end
		GameTooltip:Show()
	end
end

-- Click a step: select its recipe in the profession window's list. Blizzard's RecipeList:SelectRecipe fires the
-- list's selection callback (the recipe pane shows it) and scrolls to the row. A recipe the list hides (search
-- text, filters) still opens in the recipe pane. With the window closed: C_TradeSkillUI.OpenRecipe.
function UI:RowClick(row)
	if row.kind == "inter" and row.inter then
		CPa.Craft:Select(row.inter.recipe.id)
		return
	end
	if row.kind ~= "step" then return end
	local id = row.step.recipe.id
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	local list = page and page.RecipeList
	if ProfessionsFrame and ProfessionsFrame:IsShown() and list and list.SelectRecipe and C_TradeSkillUI then
		local okInfo, info = pcall(C_TradeSkillUI.GetRecipeInfo, id)
		if okInfo and type(info) == "table" then
			local ok, elementData = pcall(list.SelectRecipe, list, info, true)
			if ok and elementData then return end
			if page.SelectRecipe then
				local skipSelectInList = true
				pcall(page.SelectRecipe, page, info, skipSelectInList)
				return
			end
		end
	end
	if C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then
		pcall(C_TradeSkillUI.OpenRecipe, id)
	end
end

CPa:On("PLAN_UPDATED", function() UI:Refresh() end)
-- names asked for above arrive one by one; redraw once after a burst
CPa:RegisterEvent("ITEM_DATA_LOAD_RESULT", function()
	if not UI.waitingItems or UI.redrawQueued then return end
	UI.redrawQueued = true
	local function Redraw() UI.redrawQueued = false; UI.waitingItems = false; UI:Refresh() end
	if C_Timer and C_Timer.After then C_Timer.After(0.5, Redraw) else Redraw() end
end)
CPa:On("SETTINGS_CHANGED", function() UI:Refresh() end)

-- the Shopping list follows what you own and where you stand (AH / merchant)
local function ShopChanged()
	UI.shopDirty = true
	if not UI:IsShown() or UI.view ~= "shop" or UI.shopQueued then return end
	UI.shopQueued = true
	local function Run() UI.shopQueued = false; UI:Refresh() end
	if C_Timer and C_Timer.After then C_Timer.After(0.2, Run) else Run() end
end
for _, ev in ipairs({ "BAG_UPDATE_DELAYED", "MERCHANT_SHOW", "MERCHANT_CLOSED", "AUCTION_HOUSE_CLOSED" }) do
	CPa:RegisterEvent(ev, ShopChanged)
end
-- at the Auction House the Shopping tab is what you need
CPa:RegisterEvent("AUCTION_HOUSE_SHOW", function()
	if UI:IsShown() and UI.view ~= "shop" then UI:SetView("shop") else ShopChanged() end
end)

-- the window (and with it CraftPathCraftButton for the key binding and macros) exists from login on
CPa:On("READY", function() UI:GetFrame() end)

---------------------------------------------------------------------------
-- Entry in the profession window's filter menu
---------------------------------------------------------------------------

CPa:On("READY", function()
	if Menu and type(Menu.ModifyMenu) == "function" then
		pcall(Menu.ModifyMenu, "MENU_PROFESSIONS_FILTER", function(_, root)
			root:CreateDivider()
			root:CreateTitle("CraftPath")
			root:CreateButton("Cheapest leveling route", function() UI:Open() end)
		end)
	end
end)

---------------------------------------------------------------------------
-- Button in the profession window: right of the rank bar's chat-link button (Blizzard_ProfessionsCrafting.xml on
-- Forever: CraftingPage.RankBar at the top, LinkButton anchored to its right), toggles the route window
---------------------------------------------------------------------------

function UI:SetupProfessionButton()
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	if self.profButton or not page then return self.profButton end
	local b = CreateFrame("Button", "CraftPathProfessionButton", page)
	b:SetSize(22, 22)
	b:SetFrameStrata("HIGH")
	local anchor = page.LinkButton or page.RankBar
	if anchor then
		b:SetPoint("LEFT", anchor, "RIGHT", anchor == page.LinkButton and 4 or 6, 0)
	else
		b:SetPoint("TOPRIGHT", ProfessionsFrame, "TOPRIGHT", -30, -34)
	end
	b.Icon = b:CreateTexture(nil, "ARTWORK")
	b.Icon:SetAllPoints()
	b.Icon:SetTexture("Interface\\Icons\\INV_Misc_Book_11")
	b.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.2)
	b:SetScript("OnClick", function() UI:Toggle() end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("CraftPath")
		GameTooltip:AddLine("Cheapest leveling route for this profession. Click to open or close (/cpath).", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	self.profButton = b
	return b
end

-- Blizzard_Professions loads on the first open, possibly after this event: try again once it has loaded
CPa:RegisterEvent("TRADE_SKILL_SHOW", function()
	UI:SetupProfessionButton()
	if C_Timer and C_Timer.After then C_Timer.After(0, function() UI:SetupProfessionButton() end) end
end)
CPa:RegisterEvent("TRADE_SKILL_LIST_UPDATE", function() UI:SetupProfessionButton() end)
CPa:RegisterEvent("ADDON_LOADED", function(_, name) if name == "Blizzard_Professions" then UI:SetupProfessionButton() end end)
CPa:On("READY", function() UI:SetupProfessionButton() end)
