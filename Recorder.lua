-- CraftPath :: Recorder
-- Records the profession trainers and recipe vendors you visit, so the route can use recipes you have not learned
-- yet right away (ProfessionRecorder is no longer needed for that; its recordings are still read when installed).
-- Verified on the last beta build (CraftPathVerify, 2026-10-23):
--   * the trainer's list is empty at TRAINER_SHOW and filled at TRAINER_UPDATE; every update is read again
--   * the type filters change nothing, and the default already lists "unavailable" services: never touched here
--   * a visit lists only part of the ladder (skill 0 at Snang: recipes 1-55; Alchemy 15: 20-50) and never what the
--     character already learned, so visits are merged per service and the list grows as you level
--   * C_TooltipInfo.GetTrainerService(i).id is the recipe spell ID (24 of 24); rank services have no profession
--   * "Requires <Profession> (<skill>)" is on the merchant tooltip and on the item's own tooltip; "Pattern: X"
--     names the recipe (7 of 7 matched)
-- Stored account-wide in CraftPathDB.recorded in the shape ProfessionRecorder uses, so Model reads both alike:
--   trainers[npcID] = { name, loc, faction, seen, services = { { name, prof, skill, cost, level, tipID }, ... } }
--   vendors[npcID]  = { name, loc, faction, seen, items = { { name, itemID, price, reqProf, reqSkill }, ... } }

local _, CPa = ...
local Rec = {}
CPa.Recorder = Rec

Rec.CAP = 40 -- trainers and vendors each; the oldest visit goes first (the console vault is parsed at every login)

local function After(seconds, fn)
	if C_Timer and C_Timer.After then C_Timer.After(seconds, fn) else fn() end
end

local function Call(fn, ...)
	if type(fn) ~= "function" then return false end
	return pcall(fn, ...)
end

local function Now() return time and time() or 0 end

function Rec:Store()
	local db = CPa.db
	if type(db) ~= "table" then return nil end
	local r = db.recorded
	if type(r) ~= "table" then r = {}; db.recorded = r end
	r.trainers = type(r.trainers) == "table" and r.trainers or {}
	r.vendors = type(r.vendors) == "table" and r.vendors or {}
	return r
end

local function NpcID()
	local guid = UnitGUID and UnitGUID("npc")
	return type(guid) == "string" and tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)")) or nil
end

local function Location()
	local zone = GetRealZoneText and GetRealZoneText() or nil
	local sub = GetSubZoneText and GetSubZoneText() or nil
	return { zone = zone, subzone = (sub ~= "" and sub ~= zone) and sub or nil }
end

local function Faction()
	local ok, f = pcall(function() return UnitFactionGroup("player") end)
	return ok and f or nil
end

-- Keep the newest CAP entries of a table keyed by NPC.
local function Prune(list)
	if type(list) ~= "table" then return end
	local keys = {}
	for k, v in pairs(list) do keys[#keys + 1] = { k, tonumber(v.seen) or 0 } end
	if #keys <= Rec.CAP then return end
	table.sort(keys, function(a, b) return a[2] > b[2] end)
	for i = Rec.CAP + 1, #keys do list[keys[i][1]] = nil end
end
Rec.Prune = Prune

-- Merge one visit into the stored list (by recipe ID, else name): a service seen again is updated, one this
-- visit no longer lists (learned since) stays. Returns true when something new or changed was stored.
local function Merge(stored, fresh, idField)
	local changed = false
	local byKey = {}
	for i, s in ipairs(stored) do byKey[tostring(s[idField] or s.name)] = i end
	for _, s in ipairs(fresh) do
		local k = tostring(s[idField] or s.name)
		local i = byKey[k]
		if not i then
			stored[#stored + 1] = s
			byKey[k] = #stored
			changed = true
		else
			local old = stored[i]
			for field, v in pairs(s) do
				if old[field] ~= v then old[field] = v; changed = true end
			end
		end
	end
	return changed
end
Rec.Merge = Merge

local function Changed()
	CPa:Fire("RECORDED")
	if CPa.Model then
		CPa.Model.dirty = CPa.Model.dirty + 1
		CPa.Model:Queue()
	end
end

---------------------------------------------------------------------------
-- Trainers
---------------------------------------------------------------------------

local function ReadService(i)
	local ok, name, _, _, level = Call(GetTrainerServiceInfo, i)
	if not (ok and type(name) == "string" and name ~= "") then return nil end
	local s = { name = name }
	if type(level) == "number" and level > 0 then s.level = level end
	local okR, prof, skill = Call(GetTrainerServiceSkillReq, i)
	if okR and type(prof) == "string" and prof ~= "" then s.prof = prof end
	if okR then s.skill = tonumber(skill) end
	local okC, cost = Call(GetTrainerServiceCost, i)
	if okC then s.cost = tonumber(cost) end
	if C_TooltipInfo and C_TooltipInfo.GetTrainerService then
		local okT, data = pcall(C_TooltipInfo.GetTrainerService, i)
		if okT and type(data) == "table" and type(data.id) == "number" then s.tipID = data.id end
	end
	return s
end

function Rec:RecordTrainer()
	local store = self:Store()
	if not store or type(GetNumTrainerServices) ~= "function" then return nil end
	-- class trainers use the same window
	if type(IsTradeskillTrainer) == "function" then
		local ok, isTrade = pcall(IsTradeskillTrainer)
		if ok and not isTrade then return nil end
	end
	local okN, n = pcall(GetNumTrainerServices)
	n = okN and tonumber(n) or 0
	if n <= 0 then return nil end
	local fresh, count = {}, {}
	for i = 1, n do
		local s = ReadService(i)
		if s then
			fresh[#fresh + 1] = s
			if s.prof then count[s.prof] = (count[s.prof] or 0) + 1 end
		end
	end
	-- rank services may come without a profession (Apprentice did): they belong to the one the recipes name
	local main, best = nil, 0
	for prof, c in pairs(count) do if c > best then main, best = prof, c end end
	for _, s in ipairs(fresh) do if not s.prof then s.prof = main end end
	local key = NpcID() or (UnitName and UnitName("npc")) or "?"
	local rec = store.trainers[key]
	local isNew = not rec
	if isNew then
		rec = { services = {} }
		store.trainers[key] = rec
	end
	rec.name, rec.loc, rec.faction, rec.seen = UnitName and UnitName("npc") or rec.name, Location(), Faction(), Now()
	rec.services = type(rec.services) == "table" and rec.services or {}
	local changed = Merge(rec.services, fresh, "tipID")
	Prune(store.trainers)
	if changed or isNew then Changed() end
	return rec, changed
end

---------------------------------------------------------------------------
-- Recipe vendors
---------------------------------------------------------------------------

local function TooltipLines(data)
	local out = {}
	if type(data) == "table" and type(data.lines) == "table" then
		for _, line in ipairs(data.lines) do
			-- a pattern's tooltip embeds the made item's tooltip as one line with newlines in it
			for part in tostring(line.leftText or ""):gmatch("[^\r\n]+") do
				part = part:match("^%s*(.-)%s*$")
				if part ~= "" then out[#out + 1] = part end
			end
		end
	end
	return out
end

-- "Requires Tailoring (125)" -> "Tailoring", 125, read with the client's own ITEM_REQ_SKILL ("Requires %s (%d)"),
-- so the profession name comes out in the client's language like the profession window's.
local reqPattern
local function ReqPattern()
	if reqPattern then return reqPattern end
	local fmt = type(ITEM_REQ_SKILL) == "string" and ITEM_REQ_SKILL or "Requires %s (%d)"
	fmt = fmt:gsub("%%%d%$", "%%") -- "%1$s" style
	local escaped = fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
	reqPattern = "^" .. escaped:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)") .. "$"
	return reqPattern
end

local function RequiredSkill(lines)
	local pat = ReqPattern()
	for _, text in ipairs(lines) do
		local prof, skill = text:match(pat)
		if prof and tonumber(skill) then return prof, tonumber(skill) end
	end
	return nil
end
Rec.RequiredSkill = RequiredSkill

local function RecipeClass() return (Enum and Enum.ItemClass and Enum.ItemClass.Recipe) or 9 end

function Rec:RecordVendor()
	local store = self:Store()
	if not store or type(GetMerchantNumItems) ~= "function" then return nil end
	local okN, n = pcall(GetMerchantNumItems)
	n = okN and tonumber(n) or 0
	local fresh, pending = {}, 0
	for i = 1, n do
		local okL, link = Call(GetMerchantItemLink, i)
		local itemID = okL and type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
		if not itemID then
			pending = pending + 1
		elseif C_Item and C_Item.GetItemInfoInstant and select(7, pcall(C_Item.GetItemInfoInstant, itemID)) == RecipeClass() then
			local item = { itemID = itemID, name = link:match("%[(.-)%]") }
			if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
				local ok, info = pcall(C_MerchantFrame.GetItemInfo, i)
				if ok and type(info) == "table" then
					item.name = info.name or item.name
					item.price = info.price
				end
			end
			local lines = {}
			if C_TooltipInfo and C_TooltipInfo.GetMerchantItem then
				local ok, data = pcall(C_TooltipInfo.GetMerchantItem, i)
				if ok then lines = TooltipLines(data) end
			end
			item.reqProf, item.reqSkill = RequiredSkill(lines)
			if not item.reqSkill and C_TooltipInfo and C_TooltipInfo.GetItemByID then
				local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
				if ok then item.reqProf, item.reqSkill = RequiredSkill(TooltipLines(data)) end
			end
			if not (item.name and item.reqSkill) then pending = pending + 1 end
			fresh[#fresh + 1] = item
		end
	end
	if #fresh == 0 then return nil, false, pending end
	local key = NpcID() or (UnitName and UnitName("npc")) or "?"
	local rec = store.vendors[key]
	local isNew = not rec
	if isNew then
		rec = { items = {} }
		store.vendors[key] = rec
	end
	rec.name, rec.loc, rec.faction, rec.seen = UnitName and UnitName("npc") or rec.name, Location(), Faction(), Now()
	rec.items = type(rec.items) == "table" and rec.items or {}
	local changed = Merge(rec.items, fresh, "itemID")
	Prune(store.vendors)
	if changed or isNew then Changed() end
	return rec, changed, pending
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local trainerToken, vendorToken = 0, 0

local function TrainerSoon()
	trainerToken = trainerToken + 1
	local token = trainerToken
	After(0.2, function() if token == trainerToken then Rec:RecordTrainer() end end)
end

CPa:RegisterEvent("TRAINER_SHOW", TrainerSoon)
CPa:RegisterEvent("TRAINER_UPDATE", TrainerSoon)
CPa:RegisterEvent("TRAINER_CLOSED", function() trainerToken = trainerToken + 1 end)

CPa:RegisterEvent("MERCHANT_SHOW", function()
	vendorToken = vendorToken + 1
	local token = vendorToken
	After(0.3, function()
		if token ~= vendorToken then return end
		local _, _, pending = Rec:RecordVendor()
		-- item data not cached yet: look again once it has had time to arrive
		if (pending or 0) > 0 then
			After(2, function()
				if token ~= vendorToken then return end
				local _, _, still = Rec:RecordVendor()
				if (still or 0) > 0 then After(4, function() if token == vendorToken then Rec:RecordVendor() end end) end
			end)
		end
	end)
end)
CPa:RegisterEvent("MERCHANT_CLOSED", function() vendorToken = vendorToken + 1 end)

-- How much was recorded, for /cpath debug.
function Rec:Summary()
	local store = self:Store()
	if not store then return "no data" end
	local t, s, v, i = 0, 0, 0, 0
	for _, tr in pairs(store.trainers) do t = t + 1; s = s + #(tr.services or {}) end
	for _, vd in pairs(store.vendors) do v = v + 1; i = i + #(vd.items or {}) end
	return string.format("%d trainers (%d services), %d recipe vendors (%d patterns)", t, s, v, i)
end
