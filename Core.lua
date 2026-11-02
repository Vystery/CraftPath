-- CraftPath :: Core
-- Namespace, settings, saved variables (through CraftProfit's watcher: late-loading safe, console vault
-- fallback), events and slash commands. CraftPath shows the cheapest route from your skill to a target skill
-- for the open profession, priced with CraftProfit.

local ADDON_NAME, CPa = ...
_G.CraftPath = CPa

CPa.name = ADDON_NAME
CPa.version = "dev"
CPa.CP = _G.CraftProfit

CPa.DEFAULTS = {
	outputs = "vendor",   -- what crafted items are counted as worth: "vendor" | "ah" | "none"
	bagsOnly = false,     -- route from the mats in your bags only (no buying, no training)
	craftReagents = true, -- false: reagents whose crafts give no skill-up at that point are bought instead
	autoReplace = false,  -- answer "Do you want to replace this enchant?" with yes
	targets = {},         -- ["Name-Realm:Profession"] = target skill (a bare profession key = from 0.1, any character)
	starts = {},          -- ["Name-Realm:Profession"] = skill when that target was set (the bar's left end: progress)
	shopScope = "25",     -- Shopping list: "step" | "25" (next 25 points) | "all"
	pace = "balanced",    -- "cheapest" | "balanced" | "fastest": what a craft of your time is worth (Data.PACE)
	recorded = {},        -- trainers and recipe vendors visited on this account (Recorder.lua)
}

-- Key Bindings > AddOns > CraftPath (Bindings.xml clicks the Craft next button)
BINDING_HEADER_CRAFTPATH = "CraftPath"
_G["BINDING_NAME_CLICK CraftPathCraftButton:LeftButton"] = "Craft next"

function CPa:Print(msg, ...)
	if select("#", ...) > 0 then msg = string.format(msg, ...) end
	(DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage("|cff8fd4ffCraftPath:|r " .. tostring(msg))
end

---------------------------------------------------------------------------
-- Events and internal messages
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers, listeners = {}, {}

function CPa:RegisterEvent(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		pcall(eventFrame.RegisterEvent, eventFrame, event)
	end
	table.insert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	for _, fn in ipairs(handlers[event] or {}) do
		local ok, err = pcall(fn, event, ...)
		if not ok then CPa:Print("error in %s: %s", event, tostring(err)) end
	end
end)

function CPa:On(msg, fn)
	listeners[msg] = listeners[msg] or {}
	table.insert(listeners[msg], fn)
end

function CPa:Fire(msg, ...)
	for _, fn in ipairs(listeners[msg] or {}) do
		local ok, err = pcall(fn, ...)
		if not ok then self:Print("error in %s: %s", msg, tostring(err)) end
	end
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
-- Never assign the global at load: keep the working table local, adopt the client's copy when it appears.

local function InitDB(db)
	db = type(db) == "table" and db or {}
	for k, v in pairs(CPa.DEFAULTS) do
		if db[k] == nil then db[k] = type(v) == "table" and {} or v end
	end
	return db
end
CPa.InitDB = InitDB

-- The loaded table wins; settings made this session before it arrived fill only what it lacks.
local function Adopt(loaded, provisional)
	loaded = InitDB(loaded)
	for k, v in pairs(provisional or {}) do
		if k == "targets" or k == "starts" then
			for prof, value in pairs(v) do
				if loaded[k][prof] == nil then loaded[k][prof] = value end
			end
		elseif k == "recorded" and type(v) == "table" then
			-- visits made this session before the file arrived join the loaded ones (merge is idempotent)
			for _, kind in ipairs({ "trainers", "vendors" }) do
				local listField = kind == "trainers" and "services" or "items"
				local idField = kind == "trainers" and "tipID" or "itemID"
				loaded.recorded[kind] = type(loaded.recorded[kind]) == "table" and loaded.recorded[kind] or {}
				for npc, rec in pairs(type(v[kind]) == "table" and v[kind] or {}) do
					local into = loaded.recorded[kind][npc]
					if type(into) ~= "table" then
						loaded.recorded[kind][npc] = rec
					elseif type(rec) == "table" then
						-- the newer visit's name, place and time win, so pruning keeps the NPC just visited
						if (tonumber(rec.seen) or 0) > (tonumber(into.seen) or 0) then
							into.seen, into.name, into.loc, into.faction = rec.seen, rec.name or into.name, rec.loc or into.loc, rec.faction or into.faction
						end
						if CPa.Recorder and type(rec[listField]) == "table" then
							into[listField] = type(into[listField]) == "table" and into[listField] or {}
							CPa.Recorder.Merge(into[listField], rec[listField], idField)
						end
					end
				end
				if CPa.Recorder and CPa.Recorder.Prune then CPa.Recorder.Prune(loaded.recorded[kind]) end
			end
		elseif loaded[k] == nil then
			loaded[k] = v
		end
	end
	CPa.db = loaded
	_G.CraftPathDB = loaded
	CPa:Fire("SETTINGS_CHANGED")
	return loaded
end
CPa.AdoptDB = Adopt

CPa:RegisterEvent("ADDON_LOADED", function(_, name)
	if name ~= ADDON_NAME then return end
	local g = _G.CraftPathDB
	CPa.db = InitDB(type(g) == "table" and g or nil)
	if CPa.CP and CPa.CP.WatchSavedVariable then
		CPa.CP:WatchSavedVariable("CraftPathDB", CPa.db, Adopt, nil, "CraftPath")
	end
end)

CPa:RegisterEvent("PLAYER_LOGIN", function()
	if C_AddOns and C_AddOns.GetAddOnMetadata then
		local ok, v = pcall(C_AddOns.GetAddOnMetadata, ADDON_NAME, "Version")
		if ok and v then CPa.version = v end
	end
	CPa:Fire("READY")
end)

-- without CraftProfit's watcher (should not happen: it is a dependency) the table still gets saved
CPa:RegisterEvent("PLAYER_LOGOUT", function()
	if not (CPa.CP and CPa.CP.WatchSavedVariable) then _G.CraftPathDB = CPa.db end
end)

function CPa:Setting(key) return self.db and self.db[key] end

-- Copper one craft of your time is worth for the route (the Pace setting).
function CPa:CraftTime()
	local pace = (self.db and self.db.pace) or "balanced"
	return (self.Data and self.Data.PACE and self.Data.PACE[pace]) or (self.Data and self.Data.CRAFT_TIME) or 10
end

function CPa:SetSetting(key, value)
	if not self.db then self.db = InitDB(nil) end
	self.db[key] = value
	self:Fire("SETTINGS_CHANGED", key)
end

-- Targets and progress belong to one character: "Name-Realm:Profession". Values saved by 0.1 under the bare
-- profession key are read as a fallback, so an existing target carries over.
function CPa:CharKey()
	if self.charKey then return self.charKey end
	local okN, name = pcall(function() return UnitName("player") end)
	local okR, realm = pcall(function() return GetRealmName() end)
	if okN and type(name) == "string" and name ~= "" then
		self.charKey = name .. "-" .. ((okR and realm) or "")
	end
	return self.charKey
end

-- nil until the character's name is known (then nothing is written under the shared key)
local function ProfKey(prof)
	local char = CPa:CharKey()
	return char and (char .. ":" .. tostring(prof)) or nil
end
CPa.ProfKey = ProfKey

-- Target skill: up to the game's maximum (300), past the current rank's cap; the route trains the ranks on the way.
function CPa:GetTarget(prof, skill, maxSkill)
	local top = (self.Data and self.Data.MAX_SKILL) or 300
	local targets = self.db and self.db.targets
	local key = ProfKey(prof)
	local t = targets and ((key and targets[key]) or targets[prof])
	if type(t) ~= "number" then t = top end
	if t > top then t = top end
	return t
end

-- A new target starts the progress bar at the current skill.
function CPa:SetTarget(prof, target, skill)
	if not self.db then self.db = InitDB(nil) end
	local key = ProfKey(prof)
	if not key then return end
	self.db.targets[key] = target
	if skill then self.db.starts[key] = skill end
	self:Fire("SETTINGS_CHANGED", "targets")
end

-- Left end of the progress bar: the skill the target was set at (never above the current skill).
function CPa:GetStart(prof, skill)
	if not self.db then self.db = InitDB(nil) end
	local key = ProfKey(prof)
	local start = (key and self.db.starts[key]) or self.db.starts[prof]
	if type(start) ~= "number" or start > skill then start = skill end
	if key then self.db.starts[key] = start end
	return start
end

---------------------------------------------------------------------------
-- "Do you want to replace <old> with <new>?": with autoReplace on, CraftPath answers yes and closes the popup.
-- Verified in Blizzard's Forever source (Gethe wow-ui-source, branch forever):
--   REPLACE_ENCHANT            -> popup REPLACE_ENCHANT,            C_Item.ReplaceEnchant()
--   REPLACE_TRADESKILL_ENCHANT -> popup REPLACE_TRADESKILL_ENCHANT, C_Item.ReplaceTradeskillEnchant()
--     (the second one is enchanting from the profession window onto its target item slot)
-- The global ReplaceEnchant() of older clients is gone. Blizzard shows the popup from the same event, possibly
-- after us, so it is closed again on the next frame.
-- Only an enchant cast from the profession window in the last few seconds is answered (Craft.lua stamps every
-- craft there), so an enchant scroll or someone else's enchant on your gear still asks.
---------------------------------------------------------------------------

local REPLACE = {
	REPLACE_ENCHANT = { fn = "ReplaceEnchant", popup = "REPLACE_ENCHANT" },
	REPLACE_TRADESKILL_ENCHANT = { fn = "ReplaceTradeskillEnchant", popup = "REPLACE_TRADESKILL_ENCHANT" },
}

local function ReplaceFunction(name)
	if C_Item and type(C_Item[name]) == "function" then return C_Item[name] end
	if type(_G[name]) == "function" then return _G[name] end
	return nil
end

for event, spec in pairs(REPLACE) do
	CPa:RegisterEvent(event, function()
		if not CPa:Setting("autoReplace") then
			if event == "REPLACE_TRADESKILL_ENCHANT" and not CPa.replaceHinted then
				CPa.replaceHinted = true
				CPa:Print("tired of this popup while leveling? Tick \"Skip replace popup\" in the CraftPath window.")
			end
			return
		end
		local Craft = CPa.Craft
		local now = GetTime and GetTime() or 0
		local recent = Craft and Craft.lastCraft and now - Craft.lastCraft <= 5
		local inBatch = Craft and Craft.batchUntil and now <= Craft.batchUntil
		if not (recent or inBatch) then return end
		local fn = ReplaceFunction(spec.fn)
		if not fn then
			CPa:Print("this client has no C_Item.%s; the replace popup stays.", spec.fn)
			return
		end
		local ok, err = pcall(fn)
		if not ok then
			CPa:Print("could not confirm the enchant replacement: %s", tostring(err))
			return
		end
		local function Hide() if StaticPopup_Hide then pcall(StaticPopup_Hide, spec.popup) end end
		Hide()
		if C_Timer and C_Timer.After then C_Timer.After(0, Hide) end
	end)
end

---------------------------------------------------------------------------
-- Formatting (CraftProfit's helpers, so money looks the same in every addon)
---------------------------------------------------------------------------

function CPa:Money(copper, opts)
	if self.CP and self.CP.FormatMoney then return self.CP:FormatMoney(copper, opts) end
	return tostring(math.floor((copper or 0) + 0.5)) .. "c"
end

function CPa:Color(hex, text) return "|cff" .. hex .. tostring(text) .. "|r" end

-- Blizzard's recipe difficulty colours
CPa.DIFF = {
	[0] = { 1.00, 0.50, 0.25, hex = "ff8040", name = "orange" },
	[1] = { 1.00, 1.00, 0.00, hex = "ffff00", name = "yellow" },
	[2] = { 0.25, 0.75, 0.25, hex = "40bf40", name = "green" },
	[3] = { 0.50, 0.50, 0.50, hex = "808080", name = "gray" },
}

---------------------------------------------------------------------------
-- Slash
---------------------------------------------------------------------------

local HELP = {
	"/cpath                 open or close the route window",
	"/cpath target <skill>  target skill for the open profession",
	"/cpath outputs vendor|ah|none   what crafted items count as worth",
	"/cpath pace cheapest|balanced|fastest   gold only, or fewer crafts",
	"/cpath report          every candidate recipe and reagent price, to copy",
	"/cpath forget          forget the items Craft next puts in the enchant slot",
	"/cpath debug           versions and data coverage, for bug reports",
	"Key binding: Key Bindings > AddOns > CraftPath > Craft next (or a macro: /click CraftPathCraftButton)",
}

SLASH_CRAFTPATH1 = "/cpath"
SLASH_CRAFTPATH2 = "/craftpath"
SlashCmdList.CRAFTPATH = function(msg)
	msg = (msg or ""):match("^%s*(.-)%s*$")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()
	if not CPa.db then CPa.db = InitDB(nil) end
	if cmd == "" then
		CPa.UI:Toggle()
	elseif cmd == "target" then
		local n = tonumber(rest)
		local plan = CPa.Model and CPa.Model.plan
		if not n or not plan then
			CPa:Print("open a profession window first, then /cpath target 200.")
			return
		end
		CPa:SetTarget(plan.key or plan.prof, math.floor(n), plan.skill)
		CPa.UI:Open()
	elseif cmd == "report" then
		CPa.Report:Show()
	elseif cmd == "forget" then
		if CPa.db then CPa.db.enchantTargets = {} end
		CPa:Print("forgot every remembered enchant target.")
	elseif cmd == "debug" then
		for _, line in ipairs(CPa:DebugLines()) do CPa:Print(line) end
	elseif cmd == "pace" and CPa.Data.PACE[rest] then
		CPa:SetSetting("pace", rest)
		CPa:Print("pace: %s.", rest)
	elseif cmd == "outputs" and (rest == "vendor" or rest == "ah" or rest == "none") then
		CPa:SetSetting("outputs", rest)
		CPa:Print("crafted items count as %s.", rest == "ah" and "AH price after the cut" or rest == "vendor" and "vendor price" or "nothing")
	else
		for _, line in ipairs(HELP) do CPa:Print(line) end
	end
end

-- /cpath debug: what a bug report needs, one line each
function CPa:DebugLines()
	local out = {}
	local function V(addon)
		if not (C_AddOns and C_AddOns.GetAddOnMetadata) then return "?" end
		local ok, v = pcall(C_AddOns.GetAddOnMetadata, addon, "Version")
		return ok and v or "not loaded"
	end
	local okB, version, buildNo = pcall(function() return GetBuildInfo() end)
	local build = okB and (tostring(version) .. "." .. tostring(buildNo)) or "?"
	local okL, locale = pcall(function() return GetLocale() end)
	local okF, faction = pcall(function() return UnitFactionGroup("player") end)
	out[#out + 1] = string.format("CraftPath %s, CraftProfit %s, ProfessionRecorder %s, client %s %s, %s",
		tostring(self.version), V("CraftProfit"), V("ProfessionRecorder"), build, okL and tostring(locale) or "?",
		okF and tostring(faction) or "?")
	out[#out + 1] = "recorded: " .. (self.Recorder and self.Recorder:Summary() or "?")
	out[#out + 1] = "prices: " .. ((self.CP and self.CP.GetSourceName and self.CP:GetSourceName()) or "CraftProfit missing")
	local plan = self.Model and self.Model.plan
	if not plan then
		out[#out + 1] = "no plan yet (open a profession window)"
		return out
	end
	local age = plan.priceAge and string.format("%.1f h", plan.priceAge / 3600) or "unknown"
	out[#out + 1] = string.format("%s (key %s, id %s): skill %d/%d, target %d, start %d",
		tostring(plan.prof), tostring(plan.key), tostring(plan.profID), plan.skill, plan.maxSkill or 0, plan.target, plan.start or 0)
	out[#out + 1] = string.format("recipes: %d usable, %d priced, %d left out (no price), %d sources, trainer data %s%s",
		#(plan.usable or {}), #(plan.recipes or {}), #(plan.unpriced or {}), plan.sourceCount or 0,
		plan.covered and "recorded" or "none", plan.otherFaction and " (other faction: shown as your trainer)" or "")
	out[#out + 1] = string.format("route: %d steps, reached %s, gap %s, price age %s, bags only %s",
		#(plan.result.steps or {}), tostring(plan.result.reached), tostring(plan.result.gap), age, tostring(plan.bagsOnly))
	out[#out + 1] = string.format("settings: pace %s, made items %s, craft reagents %s, skip replace %s, shopping scope %s",
		tostring(self:Setting("pace")), tostring(self:Setting("outputs")), tostring(self:Setting("craftReagents") ~= false), tostring(self:Setting("autoReplace") and true or false),
		tostring(self:Setting("shopScope")))
	return out
end
